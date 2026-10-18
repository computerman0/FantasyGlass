import {d} from "./decimal.js";
import {object} from "./providers.js";
import {alertKinds, type Rule, type Subscription} from "./types.js";

export class InputError extends Error {}
function string(value: unknown, field: string, max = 256, required = true): string | undefined {
  if (value == null && !required) return;
  if (typeof value !== "string" || (required && !value.length) || value.length > max || /[\r\n\x00]/.test(value)) throw new InputError(`Invalid ${field}`);
  return value;
}
function decimal(value: unknown, field: string): string {
  const text = string(value,field,128)!;
  try { return d(text).toString(); } catch { throw new InputError(`Invalid decimal for ${field}`); }
}
function stringMap(value: unknown, field: string, numeric: boolean): Record<string,string> {
  const map = object(value), entries = Object.entries(map);
  if (entries.length > 512) throw new InputError(`Too many ${field}`);
  return Object.fromEntries(entries.map(([k,v])=>{
    if (!/^\d{1,20}$/.test(k)) throw new InputError(`Invalid ${field} key`);
    const parsed = numeric ? decimal(v,field) : string(v,field,32)!;
    if (!numeric && !/^\d{1,20}$/.test(parsed)) throw new InputError(`Invalid ${field} value`);
    return [k,parsed];
  }));
}
function rule(value: unknown): Rule {
  const r = object(value), mode = string(r.mode,"rule mode");
  if (!["linear","threshold","range","perWhole"].includes(mode!)) throw new InputError("Unknown rule mode");
  const result: Rule = {id:string(r.id,"rule ID")!,stat:string(r.stat,"stat ID",32)!,label:string(r.label,"rule label")!,multiplier:decimal(r.multiplier,"multiplier"),mode:mode as Rule["mode"],positionMultipliers:stringMap(r.positionMultipliers,"position multipliers",true)};
  if (!/^\d{1,20}$/.test(result.stat)) throw new InputError("Stat ID must be numeric");
  if (r.lower != null) result.lower = decimal(r.lower,"lower");
  if (r.upper != null) result.upper = decimal(r.upper,"upper");
  if (mode !== "linear" && result.lower == null) throw new InputError("Rule lower bound is required");
  if (mode === "perWhole" && d(result.lower).compare(d(0)) <= 0) throw new InputError("Whole-unit size must be positive");
  if (mode === "range" && (result.upper == null || d(result.lower).compare(d(result.upper)) > 0)) throw new InputError("Invalid range");
  return result;
}
export function validateSubscription(value: unknown, pathID: string): Subscription {
  const v = object(value), id = string(v.id,"subscription ID",256)!;
  if (id !== pathID || !/^[A-Za-z0-9:_-]+$/.test(id)) throw new InputError("Invalid subscription ID");
  const leagueID = string(v.leagueID,"league ID",20)!;
  if (!/^\d+$/.test(leagueID)) throw new InputError("League ID must be numeric");
  if (!Number.isInteger(v.season) || Number(v.season) < 2018 || Number(v.season) > 2100) throw new InputError("Invalid season");
  if (!Number.isInteger(v.teamID) || Number(v.teamID) < 0 || Number(v.teamID) > 1000) throw new InputError("Invalid team ID");
  const token = (value: unknown, field: string): string | undefined => {
    const text = string(value,field,512,false);
    if (text != null && !/^[a-fA-F0-9]{32,512}$/.test(text)) throw new InputError(`Invalid ${field}`);
    return text;
  };
  const s2 = string(v.s2,"ESPN cookie",8192,false), swid = string(v.swid,"SWID",256,false);
  if (!!s2 !== !!swid || s2?.includes(";") || swid?.includes(";")) throw new InputError("Both valid ESPN cookies are required for private access");
  if (!Array.isArray(v.enabledAlerts) || v.enabledAlerts.some(a=>!alertKinds.includes(a))) throw new InputError("Invalid alert preferences");
  if (!Array.isArray(v.ruleIssues) || v.ruleIssues.length > 256) throw new InputError("Invalid rule issues");
  let rules: Rule[] | undefined;
  if (v.rules != null) {
    if (!Array.isArray(v.rules) || !v.rules.length || v.rules.length > 256) throw new InputError("Supply 1–256 local rules");
    rules = v.rules.map(rule);
  }
  if (v.activityStartedAt != null && (!Number.isFinite(v.activityStartedAt) || Number(v.activityStartedAt) > Date.now()/1000+60)) throw new InputError("Invalid activity start time");
  return {id,connectionID:string(v.connectionID,"connection ID")!,leagueID,season:Number(v.season),teamID:Number(v.teamID),
    matchupID:string(v.matchupID,"matchup ID",40,false),activityToken:token(v.activityToken,"activity token"),deviceToken:token(v.deviceToken,"device token"),
    activityStartedAt:v.activityStartedAt == null ? undefined : Number(v.activityStartedAt),s2,swid,rules,
    ruleIssues:v.ruleIssues.map(x=>string(x,"rule issue",512)!),enabledAlerts:[...new Set(v.enabledAlerts)],
    thresholds:stringMap(v.thresholds,"thresholds",true),sportsDataKey:string(v.sportsDataKey,"SportsDataIO key",256,false),
    playerMappings:stringMap(v.playerMappings,"player mappings",false),accurateFeedConfirmed:v.accurateFeedConfirmed === true};
}
