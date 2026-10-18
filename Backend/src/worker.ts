import {createHash} from "node:crypto";
import {ProviderClient,ProviderFailure} from "./providers.js";
import {EncryptedStore, type QueuedPush} from "./store.js";
import {APNsClient,livePayload} from "./apns.js";
import {observation,active,remaining} from "./scoring.js";
import {detectEvents} from "./events.js";
import type {ContentState, Game} from "./types.js";
import {canonicalJSON} from "./canonical.js";

export function pollInterval(games: Game[], now: number): number {
  if (games.some(active)) return 60;
  if (games.some(g=>g.phase === "scheduled" && g.start > now && g.start-now < 900)) return 120;
  if (games.length && games.every(g=>g.phase === "final" || g.phase === "canceled") && Math.max(...games.map(g=>g.start)) < now-172800) return 3600;
  return 900;
}
export class Worker {
  private running = false;
  constructor(private readonly store: EncryptedStore, private readonly providers: ProviderClient, private readonly apns?: APNsClient) {}
  async tick(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      for (const stored of this.store.due()) {
        const sub = stored.subscription;
        try {
          const league = await this.providers.league(sub);
          const games = await this.providers.games(sub.season,league.week);
          let warning: string | undefined;
          try { await this.providers.applySportsData(sub,league); }
          catch { warning = "SportsDataIO unavailable; ESPN raw statistics retained"; }
          // A disconnect or configuration edit during I/O invalidates this fetch result.
          const latest = this.store.get(sub.id);
          if (!latest || canonicalJSON(latest.subscription) !== canonicalJSON(sub)) continue;
          const now = Date.now()/1000;
          const {content,frame} = observation(sub,league,games,now);
          const pushes: Omit<QueuedPush,"attempts"|"created">[] = [];
          if (sub.deviceToken) for (const event of detectEvents(stored.frame,frame,sub)) {
            const link = new URL("fantasyglass://matchup"); link.searchParams.set("connection",sub.connectionID); link.searchParams.set("matchup",league.matchup?.id ?? "");
            pushes.push({id:event.id,subscriptionID:sub.id,token:sub.deviceToken,kind:"alert",payload:{aps:{alert:{title:event.title,body:event.body},sound:"default","thread-id":createHash("sha256").update(sub.connectionID).digest("hex")},url:link.toString()}});
          }
          if (sub.activityToken) {
            const changedMatchup = sub.matchupID !== league.matchup?.id;
            const expired = sub.activityStartedAt == null || now-sub.activityStartedAt >= 7.9*3600;
            const finished = games.length > 0 && games.every(g=>g.phase === "final" || g.phase === "canceled");
            const ending = changedMatchup || expired || finished;
            const state: ContentState = changedMatchup ? {...content,myScore:stored.frame?.ownScore ?? "—",opponentScore:stored.frame?.opponentScore ?? "—",myProjection:undefined,opponentProjection:undefined,myRemaining:0,opponentRemaining:0,myPlaying:0,opponentPlaying:0,progress:1,status:"Matchup changed. Reopen FantasyGlass to track the new matchup."} : content;
            pushes.push({id:`live:${sub.id}`,subscriptionID:sub.id,token:sub.activityToken,kind:"liveactivity",payload:livePayload(state,now,ending)});
          }
          this.store.commit(sub.id,frame,pollInterval(games,now),pushes,warning);
        } catch (error) {
          // Never log provider bodies, cookie headers, API keys, or request objects.
          const message = error instanceof ProviderFailure ? error.message : "Provider data could not be refreshed; cached state retained";
          this.store.fail(sub.id,message,error instanceof ProviderFailure ? error.retryAfter : 300);
        }
      }
      await this.deliver();
      this.store.prune();
    } finally { this.running = false; }
  }
  private async deliver(): Promise<void> {
    if (!this.apns) return;
    for (const push of this.store.pending()) {
      const sub = this.store.get(push.subscriptionID)?.subscription;
      const currentToken = push.kind === "alert" ? sub?.deviceToken : sub?.activityToken;
      if (!sub || currentToken !== push.token || (push.kind === "alert" && !sub.enabledAlerts.length)) { this.store.delivered(push.id); continue; }
      if (Date.now()-push.created > (push.kind === "liveactivity" ? 180000 : 3600000)) { this.store.delivered(push.id); continue; }
      try {
        const result = await this.apns.send(push.token,push.kind,push.payload,push.id);
        if (result.status === 200) {
          this.store.delivered(push.id);
          if (push.kind === "liveactivity" && (push.payload as {aps?:{event?:string}}).aps?.event === "end") this.store.invalidateToken(push.subscriptionID,push.token,push.kind);
        } else if (result.status === 410 || ["BadDeviceToken","DeviceTokenNotForTopic","Unregistered"].includes(result.reason ?? "")) {
          this.store.invalidateToken(push.subscriptionID,push.token,push.kind); this.store.delivered(push.id);
          this.store.fail(push.subscriptionID,`APNs token rejected: ${result.reason ?? result.status}. Re-register with matching provisioning.`,60);
        } else {
          this.store.retry(push);
          this.store.fail(push.subscriptionID,`APNs returned ${result.status}${result.reason ? ` (${result.reason})` : ""}`,60);
        }
      } catch {
        this.store.retry(push);
        this.store.fail(push.subscriptionID,"APNs transport failed; retry scheduled",60);
      }
    }
  }
}
