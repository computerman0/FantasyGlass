export interface Rule {
  id: string; stat: string; label: string; multiplier: string;
  mode: "linear" | "threshold" | "range" | "perWhole";
  lower?: string; upper?: string; positionMultipliers: Record<string,string>;
}
export const alertKinds = ["touchdown","leadChange","closeFinalGame","injuredOut","halftime","final","correction","threshold"] as const;
export type AlertKind = typeof alertKinds[number];
export interface Subscription {
  id: string; connectionID: string; leagueID: string; season: number; teamID: number;
  matchupID?: string; deviceToken?: string;
  s2?: string; swid?: string; rules?: Rule[]; ruleIssues: string[];
  enabledAlerts: AlertKind[]; thresholds: Record<string,string>;
  sportsDataKey?: string; playerMappings: Record<string,string>; accurateFeedConfirmed: boolean;
}
export type Phase = "scheduled" | "live" | "halftime" | "final" | "postponed" | "canceled" | "unknown";
export interface Game { id: string; home: string; away: string; start: number; phase: Phase; detail: string; homeScore?: string; awayScore?: string; }
export interface Player { id: string; name: string; team: string; position: string; slot: number; injury: string; stats?: Record<string,string>; projections?: Record<string,string>; history?: {week:number;stats:Record<string,string>}[]; }
export interface Team { id: number; name: string; players: Player[]; record?: {wins:number;losses:number;ties:number}; rank?: number; }
export interface Matchup { id: string; homeID: number; awayID?: number; homeOfficial?: string; awayOfficial?: string; homeAdjustment: string; awayAdjustment: string; weeks: number[]; }
export interface League { id: string; name: string; week: number; teams: Team[]; rules: Rule[]; issues: string[]; matchup?: Matchup; schedule?: {id:string;week:number;homeID:number;awayID?:number;homeScore?:string;awayScore?:string}[]; }
export interface Connection { id:string; leagueID:string; season:number; teamID:number; snapshot:League; games:Game[]; fetchedAt:number; gamesFetchedAt:number; nextRefreshAt:number; localRules?:Rule[]; error?:string; gamesError?:string; privateLeague:boolean; }
export interface MatchupSummary {
  myScore: string; opponentScore: string; myProjection?: string; opponentProjection?: string;
  myRemaining: number; opponentRemaining: number; myPlaying: number; opponentPlaying: number;
  progress: number; leader: number; status: string; updatedAt: number; scoreSource: string;
}
export interface ObservedPlayer { name: string; touchdowns: string; points?: string; injury: string; }
export interface Frame { scope: string; players: Record<string,ObservedPlayer>; games: Record<string,Phase>; ownScore?: string; opponentScore?: string; lastGameLive: boolean; finished: boolean; }
export interface FantasyEvent { id: string; kind: AlertKind; title: string; body: string; }
