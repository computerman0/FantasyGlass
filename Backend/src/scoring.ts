import {d} from "./decimal.js";
import type {Rule, League, Team, Game, Player, ContentState, Frame, Subscription} from "./types.js";

export function score(stats: Record<string,string>, position: string, rules: Rule[]): string {
  let total = d(0);
  for (const rule of rules) {
    const raw = d(stats[rule.stat] ?? "0"), rate = d(rule.positionMultipliers[position] ?? rule.multiplier);
    let units = raw;
    if (rule.mode === "threshold") {
      if (rule.lower == null) throw new Error("Missing threshold");
      units = d(raw.compare(d(rule.lower)) >= 0 ? 1 : 0);
    } else if (rule.mode === "range") {
      if (rule.lower == null || rule.upper == null || d(rule.lower).compare(d(rule.upper)) > 0) throw new Error("Invalid range");
      units = d(raw.compare(d(rule.lower)) >= 0 && raw.compare(d(rule.upper)) <= 0 ? 1 : 0);
    } else if (rule.mode === "perWhole") {
      if (rule.lower == null) throw new Error("Missing whole-unit size");
      units = raw.wholeDivide(d(rule.lower));
    }
    total = total.add(units.multiply(rate));
  }
  return total.toString();
}
export const isStarter = (p: Player): boolean => ![20,21,24,25].includes(p.slot);
export const active = (g: Game): boolean => g.phase === "live" || g.phase === "halftime";
export const remaining = (g: Game): boolean => g.phase === "scheduled" || g.phase === "postponed";
export const gameFor = (player: Player, games: Game[]): Game | undefined => games.find(g=>g.home === player.team || g.away === player.team);

export function teamScore(team: Team, league: League, rules: Rule[], games: Game[], issues: string[]) {
  const starters = team.players.filter(isStarter);
  let total = d(0), projected = d(0), complete = starters.length > 0 && !issues.length, projectedComplete = starters.length > 0 && !issues.length;
  for (const player of starters) {
    if (player.stats) total = total.add(d(score(player.stats,player.position,rules)));
    else if (gameFor(player,games)?.phase !== "scheduled") complete = false;
    if (player.projections) projected = projected.add(d(score(player.projections,player.position,rules)));
    else projectedComplete = false;
  }
  if ((league.matchup?.weeks.length ?? 0) > 1) { complete = false; projectedComplete = false; }
  const home = league.matchup?.homeID === team.id;
  total = total.add(d(home ? league.matchup?.homeAdjustment : league.matchup?.awayAdjustment));
  return { local:complete ? total.toString() : undefined,
    official:home ? league.matchup?.homeOfficial : league.matchup?.awayOfficial,
    projected:projectedComplete ? projected.toString() : undefined,
    playing:starters.filter(p=>{ const g = gameFor(p,games); return g && active(g); }).length,
    remaining:starters.filter(p=>{ const g = gameFor(p,games); return g && remaining(g); }).length,
    total:starters.length };
}
export function observation(sub: Subscription, league: League, games: Game[], now: number): {content:ContentState; frame:Frame} {
  const own = league.teams.find(t=>t.id === sub.teamID);
  const opponentID = league.matchup?.homeID === sub.teamID ? league.matchup.awayID : league.matchup?.homeID;
  const opponent = league.teams.find(t=>t.id === opponentID);
  if (!own || !opponent || !league.matchup) throw new Error("Selected team has no head-to-head matchup");
  const rules = sub.rules ?? league.rules, issues = sub.rules ? sub.ruleIssues : league.issues;
  const mine = teamScore(own,league,rules,games,issues), theirs = teamScore(opponent,league,rules,games,issues);
  const ownScore = mine.local ?? mine.official, opponentScore = theirs.local ?? theirs.official;
  const leader = ownScore == null || opponentScore == null ? 0 : d(ownScore).compare(d(opponentScore));
  const teams = new Set([...own.players,...opponent.players].filter(isStarter).map(p=>p.team));
  const liveGame = games.find(g=>active(g) && (teams.has(g.home) || teams.has(g.away)));
  const total = mine.total+theirs.total;
  const outstanding = mine.playing+mine.remaining+theirs.playing+theirs.remaining;
  const content: ContentState = {myScore:ownScore ?? "—",opponentScore:opponentScore ?? "—",myProjection:mine.projected,opponentProjection:theirs.projected,
    myRemaining:mine.remaining,opponentRemaining:theirs.remaining,myPlaying:mine.playing,opponentPlaying:theirs.playing,
    progress:total ? Math.min(1,Math.max(0,(total-outstanding)/total)) : 0, leader,
    status:liveGame ? `${liveGame.away} @ ${liveGame.home} · ${liveGame.detail}`.slice(0,140) : `${mine.playing} playing · ${mine.remaining} upcoming`,
    updatedAt:now,scoreSource:mine.local != null && theirs.local != null ? "Local scoring" : "ESPN / partial local"};
  const frame: Frame = {scope:`${sub.connectionID}:${league.week}`,players:{},games:Object.fromEntries(games.map(g=>[g.id,g.phase])),ownScore,opponentScore,
    lastGameLive:games.filter(active).length === 1 && !games.some(remaining),finished:games.length > 0 && games.every(g=>g.phase === "final" || g.phase === "canceled")};
  for (const p of own.players) {
    const td = ["4","25","43","63","101","102","103","104"].reduce((sum,key)=>sum.add(d(p.stats?.[key])),d(0));
    frame.players[p.id] = {name:p.name,touchdowns:td.toString(),points:p.stats && !issues.length ? score(p.stats,p.position,rules) : undefined,injury:p.injury};
  }
  return {content,frame};
}
