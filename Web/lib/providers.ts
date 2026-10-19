import {statNames} from "./catalog.js";
import {parseProviderJSON, d} from "./decimal.js";
import type {Subscription, League, Rule, Player, Team, Game, Phase} from "./types.js";

export const object = (x: unknown): Record<string,unknown> => x != null && typeof x === "object" && !Array.isArray(x) ? x as Record<string,unknown> : {};
export const array = (x: unknown): unknown[] => Array.isArray(x) ? x : [];
const str = (x: unknown, fallback = ""): string => typeof x === "string" || typeof x === "number" ? String(x) : fallback;
const number = (x: unknown, fallback = 0): number => x == null || !Number.isFinite(Number(x)) ? fallback : Number(x);
const stats = (x: unknown): Record<string,string> => Object.fromEntries(Object.entries(object(x)).flatMap(([k,v])=>typeof v === "string" || typeof v === "number" ? [[k,d(v).toString()]] : []));
const optionalStats = (x: unknown): Record<string,string> | undefined => Object.keys(object(x)).length ? stats(x) : undefined;

export class ProviderFailure extends Error {
  constructor(readonly status: number, readonly retryAfter: number, message: string) { super(message); }
}
export class ProviderClient {
  private cache = new Map<string,{expires:number; value:unknown}>();
  private cooldown = new Map<string,number>();
  constructor(private readonly transport: typeof fetch = fetch) {}
  async get(url: string, headers: Record<string,string> = {}, ttl = 45): Promise<unknown> {
    const target = new URL(url);
    if (target.protocol !== "https:" || !["lm-api-reads.fantasy.espn.com","site.api.espn.com","api.sportsdata.io"].includes(target.hostname)) throw new Error("Provider URL is not allowed");
    const hash = await crypto.subtle.digest("SHA-256",new TextEncoder().encode(url+JSON.stringify(headers)));
    const key = Array.from(new Uint8Array(hash),x=>x.toString(16).padStart(2,"0")).join("");
    const cached = this.cache.get(key), now = Date.now();
    if (cached && cached.expires > now) return structuredClone(cached.value);
    const cooldown = this.cooldown.get(target.hostname) ?? 0;
    if (cooldown > now) throw new ProviderFailure(429,Math.ceil((cooldown-now)/1000),"Provider cooldown active");
    for (let attempt = 0; attempt < 3; attempt++) {
      const response = await this.transport(url,{headers,redirect:"error",signal:AbortSignal.timeout(25000)});
      if (response.status === 429) {
        const header = response.headers.get("retry-after");
        const retry = header && /^\d+$/.test(header) ? Number(header) : header ? Math.ceil((Date.parse(header)-Date.now())/1000) : 60;
        const seconds = Math.max(1,Number.isFinite(retry) ? retry : 60);
        this.cooldown.set(target.hostname,Date.now()+seconds*1000);
        throw new ProviderFailure(429,seconds,"Provider rate limit reached");
      }
      if (!response.ok) {
        if (response.status >= 500 && attempt < 2) { await new Promise(resolve=>setTimeout(resolve,500*(2**attempt))); continue; }
        throw new ProviderFailure(response.status,300,`Provider returned HTTP ${response.status}; check visibility, credentials or subscription`);
      }
      if (Number(response.headers.get("content-length")) > 8*1024*1024) throw new Error("Provider response is too large");
      const reader = response.body?.getReader();
      if (!reader) throw new Error("Provider returned an empty response");
      const decoder = new TextDecoder(); let text = "", bytes = 0;
      try {
        while (true) {
          const part = await reader.read(); if (part.done) break;
          bytes += part.value.byteLength;
          if (bytes > 8*1024*1024) { await reader.cancel(); throw new Error("Provider response is too large"); }
          text += decoder.decode(part.value,{stream:true});
        }
        text += decoder.decode();
      } finally { reader.releaseLock(); }
      const value = parseProviderJSON(text);
      if (this.cache.size >= 16) this.cache.delete(this.cache.keys().next().value!);
      this.cache.set(key,{expires:Date.now()+ttl*1000,value});
      return structuredClone(value);
    }
    throw new Error("Provider retry exhausted");
  }
  async league(sub: Subscription): Promise<League> {
    const url = new URL(`https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/${sub.season}/segments/0/leagues/${sub.leagueID}`);
    for (const view of ["mSettings","mTeam","mRoster","mMatchup","mMatchupScore"]) url.searchParams.append("view",view);
    const headers: Record<string,string> = {Accept:"application/json"};
    if (sub.s2 && sub.swid) headers.Cookie = `espn_s2=${sub.s2}; SWID=${sub.swid}`;
    return decodeLeague(await this.get(url.toString(),headers),sub);
  }
  async games(season: number, week: number): Promise<Game[]> {
    return decodeGames(await this.get(`https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard?dates=${season}&seasontype=2&week=${week}&limit=100`));
  }
  async applySportsData(sub: Subscription, league: League): Promise<void> {
    if (!sub.sportsDataKey || !sub.accurateFeedConfirmed) return;
    const rows = array(await this.get(`https://api.sportsdata.io/v3/nfl/stats/json/PlayerGameStatsByWeek/${sub.season}REG/${league.week}`,{"Ocp-Apim-Subscription-Key":sub.sportsDataKey}));
    const mapped = new Map(rows.map(raw=>{ const row = object(raw); return [str(row.PlayerID),sportsStats(row)] as const; }));
    for (const team of league.teams) for (const player of team.players) {
      const id = sub.playerMappings[player.id], raw = id ? mapped.get(id) : undefined;
      if (!raw) continue;
      const missing = (sub.rules ?? league.rules).some(rule=>d(rule.positionMultipliers[player.position] ?? rule.multiplier).compare(d(0)) !== 0 && raw[rule.stat] == null);
      if (!missing) player.stats = raw;
    }
  }
}

const teamCodes: Record<number,string> = {0:"FA",1:"ATL",2:"BUF",3:"CHI",4:"CIN",5:"CLE",6:"DAL",7:"DEN",8:"DET",9:"GB",10:"TEN",11:"IND",12:"KC",13:"LV",14:"LAR",15:"MIA",16:"MIN",17:"NE",18:"NO",19:"NYG",20:"NYJ",21:"PHI",22:"ARI",23:"PIT",24:"LAC",25:"SF",26:"SEA",27:"TB",28:"WSH",29:"CAR",30:"JAX",33:"BAL",34:"HOU"};
const scoringPositions: Record<number,string> = {1:"0",2:"2",3:"4",4:"6",5:"17",16:"16",6:"9",7:"8",8:"10",9:"12",10:"13",11:"18"};
function player(raw: unknown, season: number, week: number): Player | undefined {
  const entry = object(raw), p = object(object(entry.playerPoolEntry).player);
  if (p.id == null || p.fullName == null) return;
  const result: Player = {id:str(p.id),name:str(p.fullName),team:teamCodes[number(p.proTeamId)] ?? "FA",position:scoringPositions[number(p.defaultPositionId)] ?? str(p.defaultPositionId),slot:number(entry.lineupSlotId,20),injury:str(p.injuryStatus,"UNKNOWN")};
  result.history = [];
  for (const rawLine of array(p.stats)) {
    const line = object(rawLine);
    if (number(line.seasonId) === season && number(line.statSourceId) === 0 && number(line.statSplitTypeId) !== 2 && number(line.scoringPeriodId)>0 && optionalStats(line.stats)) result.history.push({week:number(line.scoringPeriodId),stats:stats(line.stats)});
    if (number(line.seasonId) !== season || number(line.scoringPeriodId) !== week || number(line.statSplitTypeId) === 2) continue;
    if (number(line.statSourceId) === 0) result.stats = optionalStats(line.stats);
    else if (number(line.statSourceId) === 1) result.projections = optionalStats(line.stats);
  }
  return result;
}
export function decodeLeague(raw: unknown, sub: Subscription): League {
  const root = object(raw), settings = object(root.settings), scoring = object(settings.scoringSettings), status = object(root.status);
  if (str(root.id) !== sub.leagueID || number(root.seasonId) !== sub.season || !array(root.teams).length) throw new Error("Provider league ID, season, or teams are missing");
  const week = number(root.scoringPeriodId,1), period = number(status.currentMatchupPeriod,week), issues: string[] = [];
  const rules: Rule[] = array(scoring.scoringItems).flatMap(rawItem=>{
    const item = object(rawItem);
    if (item.statId == null || item.points == null) { issues.push("Malformed scoring rule"); return []; }
    if (item.isReverseItem === true) issues.push(`Reverse-scoring category ${str(item.statId)} requires review`);
    return [{id:str(item.statId),stat:str(item.statId),label:statNames[str(item.statId)] ?? `ESPN stat ${str(item.statId)}`,multiplier:d(item.points).toString(),mode:"linear",positionMultipliers:stats(item.pointsOverrides)}];
  });
  if (!rules.length) issues.push("Missing scoring rules");
  if (str(scoring.scoringType) !== "H2H_POINTS") issues.push("Unsupported scoring format");
  if (d(scoring.homeTeamBonus).compare(d(0)) !== 0 || d(scoring.playoffHomeTeamBonus).compare(d(0)) !== 0) issues.push("Home bonuses require review");
  const schedule = array(root.schedule).map(object);
  const current = schedule.filter(m=>number(m.matchupPeriodId) === period);
  const overrides = new Map<number,unknown[]>();
  for (const match of current) for (const side of [object(match.home),object(match.away)]) {
    const entries = array(object(side.rosterForCurrentScoringPeriod).entries);
    if (side.teamId != null && entries.length) overrides.set(number(side.teamId),entries);
  }
  const teams: Team[] = array(root.teams).map(rawTeam=>{
    const team = object(rawTeam), id = number(team.id);
    const entries = overrides.get(id) ?? array(object(team.roster).entries);
    const record = object(object(team.record).overall);
    return {id,name:str(team.name) || `${str(team.location)} ${str(team.nickname)}`.trim() || `Team ${id}`,record:record.wins == null ? undefined : {wins:number(record.wins),losses:number(record.losses),ties:number(record.ties)},rank:team.playoffSeed == null ? undefined : number(team.playoffSeed),players:entries.flatMap(e=>{ const p = player(e,sub.season,week); return p ? [p] : []; })};
  });
  const match = current.find(m=>number(object(m.home).teamId,-1) === sub.teamID || number(object(m.away).teamId,-1) === sub.teamID);
  const home = object(match?.home), away = object(match?.away);
  const periods = object(object(settings.scheduleSettings).matchupPeriods);
  return {id:sub.leagueID,name:str(settings.name,`League ${sub.leagueID}`),week,teams,rules,issues,schedule:schedule.map(m=>({id:str(m.id),week:number(m.matchupPeriodId),homeID:number(object(m.home).teamId),awayID:object(m.away).teamId == null ? undefined:number(object(m.away).teamId),homeScore:object(m.home).totalPoints == null ? undefined:d(object(m.home).totalPoints).toString(),awayScore:object(m.away).totalPoints == null ? undefined:d(object(m.away).totalPoints).toString()})),matchup:match ? {
    id:str(match.id),homeID:number(home.teamId),awayID:away.teamId == null ? undefined : number(away.teamId),
    homeOfficial:home.totalPoints == null ? undefined : d(home.totalPoints).toString(),awayOfficial:away.totalPoints == null ? undefined : d(away.totalPoints).toString(),
    homeAdjustment:d(home.adjustment).toString(),awayAdjustment:d(away.adjustment).toString(),weeks:array(periods[String(period)]).map(x=>number(x))} : undefined};
}
export function decodeGames(raw: unknown): Game[] {
  const root = object(raw);
  if (!Array.isArray(root.events)) throw new Error("Missing NFL events array");
  return root.events.flatMap(rawEvent=>{
    const event = object(rawEvent), competitors = array(object(array(event.competitions)[0]).competitors).map(object);
    const home = object(competitors.find(c=>c.homeAway === "home")?.team), away = object(competitors.find(c=>c.homeAway === "away")?.team);
    const type = object(object(event.status).type), name = str(type.name), start = Date.parse(str(event.date))/1000;
    if (!event.id || !home.abbreviation || !away.abbreviation || !Number.isFinite(start)) return [];
    const phase: Phase = name === "STATUS_HALFTIME" ? "halftime" : ["STATUS_POSTPONED","STATUS_DELAYED","STATUS_SUSPENDED"].includes(name) ? "postponed" : name === "STATUS_CANCELED" ? "canceled" : type.completed === true ? "final" : type.state === "in" ? "live" : type.state === "pre" ? "scheduled" : "unknown";
    return [{id:str(event.id),home:str(home.abbreviation),away:str(away.abbreviation),start,phase,detail:str(type.detail,"Status unavailable"),homeScore:str(competitors.find(c=>c.homeAway === "home")?.score),awayScore:str(competitors.find(c=>c.homeAway === "away")?.score)}];
  });
}
const sportsFields: Record<string,string> = {"0":"PassingAttempts","1":"PassingCompletions","3":"PassingYards","4":"PassingTouchdowns","20":"PassingInterceptions","19":"TwoPointConversionPasses","23":"RushingAttempts","24":"RushingYards","25":"RushingTouchdowns","26":"TwoPointConversionRuns","41":"Receptions","53":"Receptions","42":"ReceivingYards","43":"ReceivingTouchdowns","44":"TwoPointConversionReceptions","58":"ReceivingTargets","68":"Fumbles","72":"FumblesLost","63":"FumbleReturnTouchdowns","64":"PassingSacks","74":"FieldGoalsMade50Plus","77":"FieldGoalsMade40to49","83":"FieldGoalsMade","84":"FieldGoalsAttempted","86":"ExtraPointsMade","87":"ExtraPointsAttempted","101":"KickReturnTouchdowns","102":"PuntReturnTouchdowns","95":"Interceptions","96":"FumblesRecovered","99":"Sacks","106":"FumblesForced","107":"AssistedTackles","108":"SoloTackles","113":"PassesDefended"};
function sportsStats(row: Record<string,unknown>): Record<string,string> {
  const result: Record<string,string> = {};
  for (const [key,field] of Object.entries(sportsFields)) if (row[field] != null) result[key] = d(row[field]).toString();
  if (["FieldGoalsMade0to19","FieldGoalsMade20to29","FieldGoalsMade30to39"].every(k=>row[k] != null)) result["80"] = d(row.FieldGoalsMade0to19).add(d(row.FieldGoalsMade20to29)).add(d(row.FieldGoalsMade30to39)).toString();
  if (row.FieldGoalsAttempted != null && row.FieldGoalsMade != null) result["85"] = d(row.FieldGoalsAttempted).subtract(d(row.FieldGoalsMade)).toString();
  if (row.ExtraPointsAttempted != null && row.ExtraPointsMade != null) result["88"] = d(row.ExtraPointsAttempted).subtract(d(row.ExtraPointsMade)).toString();
  return result;
}
