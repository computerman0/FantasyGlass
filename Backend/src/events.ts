import {d} from "./decimal.js";
import type {Subscription, Frame, FantasyEvent, AlertKind} from "./types.js";

function leader(frame: Frame): number | undefined { return frame.ownScore == null || frame.opponentScore == null ? undefined : d(frame.ownScore).compare(d(frame.opponentScore)); }
export function detectEvents(previous: Frame | undefined, current: Frame, sub: Subscription): FantasyEvent[] {
  if (!previous || previous.scope !== current.scope) return [];
  const events: FantasyEvent[] = [];
  const emit = (kind: AlertKind, suffix: string, title: string, body: string) => {
    if (sub.enabledAlerts.includes(kind)) events.push({id:`${sub.id}:${current.scope}:${kind}:${suffix}`,kind,title,body});
  };
  for (const [id,player] of Object.entries(current.players)) {
    const before = previous.players[id]; if (!before) continue;
    if (d(player.touchdowns).compare(d(before.touchdowns)) > 0) emit("touchdown",`${id}:${player.touchdowns}`,`${player.name} touchdown`,"New touchdown reported; stat corrections may follow.");
    if (player.injury.toUpperCase() === "OUT" && before.injury.toUpperCase() !== "OUT") emit("injuredOut",id,`${player.name} is out`,"Review your fantasy lineup.");
    const threshold = sub.thresholds[id];
    if (threshold != null && player.points != null && before.points != null && d(before.points).compare(d(threshold)) < 0 && d(player.points).compare(d(threshold)) >= 0) emit("threshold",`${id}:${threshold}`,`${player.name} reached ${threshold}`,`Now at ${player.points} fantasy points in this league.`);
  }
  const currentLeader = leader(current), previousLeader = leader(previous);
  if (currentLeader != null && previousLeader != null && currentLeader !== previousLeader) {
    const corrected = previous.finished && current.finished, scores = `${current.ownScore}–${current.opponentScore}`;
    emit(corrected ? "correction" : "leadChange",`${currentLeader}:${scores}`,corrected ? "Stat correction changed the result" : "Matchup leader changed",scores);
  }
  if (current.lastGameLive && !previous.lastGameLive && current.ownScore != null && current.opponentScore != null) {
    const difference = d(current.ownScore).subtract(d(current.opponentScore));
    if (difference.compare(d(-10)) >= 0 && difference.compare(d(10)) <= 0) emit("closeFinalGame","last","A close finish","Your matchup is within 10 points as the final NFL game is underway.");
  }
  for (const [id,phase] of Object.entries(current.games)) {
    if (previous.games[id] == null || previous.games[id] === phase) continue;
    if (phase === "halftime" || phase === "final") emit(phase,id,phase === "halftime" ? "NFL halftime" : "NFL game final",`Game ${id}: ${phase}. Stat corrections remain possible.`);
  }
  return events;
}
