import {d} from './decimal';
import {score,teamScore,gameFor,isStarter,active} from './scoring';
import type {Connection,Player,Rule} from './types';
export const rulesFor=(c:Connection)=>c.localRules ?? c.snapshot.rules;
export const ownTeam=(c:Connection)=>c.snapshot.teams.find(t=>t.id===c.teamID);
export const opposingTeam=(c:Connection)=>c.snapshot.teams.find(t=>t.id===(c.snapshot.matchup?.homeID===c.teamID?c.snapshot.matchup.awayID:c.snapshot.matchup?.homeID));
export const scoresFor=(c:Connection,opponent=false)=>{
  const team=opponent?opposingTeam(c):ownTeam(c);
  return team?teamScore(team,c.snapshot,rulesFor(c),c.games,c.snapshot.issues):undefined;
};
export const points=(p:Player,c:Connection,projected=false)=>{
  const stats=projected?p.projections:p.stats;
  if(!stats||c.snapshot.issues.length)return undefined;
  try{return score(stats,p.position,rulesFor(c));}catch{return undefined;}
};
export const exact=(x:string|undefined)=>x??'—';
export const formatRecord=(c:Connection)=>{const r=ownTeam(c)?.record;return r?`${r.wins}–${r.losses}${r.ties?`–${r.ties}`:''}`:'Record unavailable';};
export const formatScoring=(c:Connection)=>{
  const rule=rulesFor(c).find(r=>['53','41'].includes(r.stat)&&r.multiplier!=='0');
  const name=rule?.multiplier==='1'?'PPR':rule?.multiplier==='0.5'?'Half PPR':rule?'Custom':'Standard';
  return c.localRules?`${name} · local`:name;
};
export const isStale=(c:Connection)=>!!c.error||Date.now()>c.nextRefreshAt+60000;
export const nextInterval=(c:Connection)=>c.games.some(active)?60000:900000;
export function breakdown(p:Player,rules:Rule[]){
  if(!p.stats)return [];
  return rules.map(r=>({rule:r,raw:p.stats![r.stat]??'0',rate:r.positionMultipliers[p.position]??r.multiplier,earned:score(p.stats!,p.position,[r])})).filter(r=>d(r.earned).compare(d(0))!==0||d(r.raw).compare(d(0))!==0&&d(r.rate).compare(d(0))!==0);
}
export function holdings(connections:Connection[]){
  const map=new Map<string,{player:Player;leagues:{connection:Connection;player:Player}[]}>();
  for(const c of connections)for(const p of ownTeam(c)?.players??[]){
    const row=map.get(p.id)??{player:p,leagues:[]};row.leagues.push({connection:c,player:p});map.set(p.id,row);
  }
  return [...map.values()];
}
export {d,gameFor,isStarter,active};
