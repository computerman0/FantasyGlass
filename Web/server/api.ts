import {ProviderClient,ProviderFailure} from '../lib/providers';
import {d} from '../lib/decimal';
import type {Connection,Rule,Subscription} from '../lib/types';
export interface Env {DB:D1Database;FANTASYGLASS_ENCRYPTION_KEY?:string;}
interface Stored {connection:string;secret:string|null;}
export class HTTPError extends Error {constructor(public status:number,message:string){super(message);}}
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
export function identity(request:Request){
  const id=request.headers.get('oai-authenticated-user-id');
  if(!id||id.length>256)throw new HTTPError(401,'Sign in to open your private FantasyGlass dashboard.');
  return id;
}
export function enforceOrigin(request:Request){
  const origin=request.headers.get('origin');
  if(!origin||origin!==new URL(request.url).origin||request.headers.get('sec-fetch-site')==='cross-site')throw new HTTPError(403,'This request must come from your FantasyGlass website.');
}
export function credentials(v:Record<string,unknown>){
  const s2=typeof v.s2==='string'?v.s2.trim():'';
  const swid=typeof v.swid==='string'?v.swid.trim():'';
  if(!!s2!==!!swid||s2.length>8192||swid.length>256||/[;\r\n\0]/.test(s2+swid))throw new HTTPError(400,'Private access requires both valid espn_s2 and SWID cookies.');
  return s2?{s2,swid}:{};
}
export function leagueInput(v:Record<string,unknown>){
  let leagueID=String(v.leagueID??'').trim();
  if(leagueID.startsWith('https://')){try{const u=new URL(leagueID);if(!/(^|\.)espn\.com$/.test(u.hostname))throw 0;leagueID=u.searchParams.get('leagueId')??'';}catch{throw new HTTPError(400,'Use an ESPN league link or a numeric league ID.');}}
  const season=Number(v.season);
  if(!/^\d{1,20}$/.test(leagueID)||!Number.isInteger(season)||season<2018||season>new Date().getUTCFullYear()+1)throw new HTTPError(400,'Enter a valid league ID and season (2018 or newer).');
  return {leagueID,season,...credentials(v)};
}
export function validateRules(value:unknown):Rule[]|undefined{
  if(value===null)return undefined;
  if(!Array.isArray(value)||!value.length||value.length>256)throw new HTTPError(400,'Provide between 1 and 256 scoring rules.');
  const ids=new Set<string>();
  return value.map(v=>{
    if(!v||typeof v!=='object')throw new HTTPError(400,'Invalid scoring rule.');
    const r=v as Rule;
    if(typeof r.id!=='string'||r.id.length>100||!r.id||ids.has(r.id)||!/^\d{1,20}$/.test(r.stat)||typeof r.label!=='string'||r.label.length>150||!['linear','threshold','range','perWhole'].includes(r.mode))throw new HTTPError(400,'Invalid or duplicate scoring rule.');
    ids.add(r.id);
    const dec=(v:unknown)=>{if(typeof v!=='string'||v.length>96)throw new HTTPError(400,'Scoring values must be decimal text.');try{return d(v).toString();}catch{throw new HTTPError(400,'Invalid scoring decimal.');}};
    const positions=Object.entries(r.positionMultipliers??{});
    if(positions.length>30||positions.some(([k])=>!/^\d{1,3}$/.test(k)))throw new HTTPError(400,'Invalid position overrides.');
    const result:Rule={id:r.id,stat:r.stat,label:r.label,multiplier:dec(r.multiplier),mode:r.mode,positionMultipliers:Object.fromEntries(positions.map(([k,v])=>[k,dec(v)]))};
    if(r.lower!=null)result.lower=dec(r.lower);
    if(r.upper!=null)result.upper=dec(r.upper);
    if(r.mode!=='linear'&&result.lower==null)throw new HTTPError(400,'This rule requires a lower bound or unit size.');
    if(r.mode==='range'&&(result.upper==null||d(result.lower).compare(d(result.upper))>0))throw new HTTPError(400,'The range bounds are invalid.');
    if(r.mode==='perWhole'&&d(result.lower).compare(d(0))<=0)throw new HTTPError(400,'The unit size must be positive.');
    return result;
  });
}
const b64=(bytes:Uint8Array)=>btoa(Array.from(bytes,b=>String.fromCharCode(b)).join(''));
const un64=(s:string)=>Uint8Array.from(atob(s),c=>c.charCodeAt(0));
async function key(env:Env){
  const s=env.FANTASYGLASS_ENCRYPTION_KEY;
  if(!s||!/^[a-f0-9]{64}$/i.test(s))throw new HTTPError(503,'Private league storage is not configured. Public leagues remain available.');
  return crypto.subtle.importKey('raw',Uint8Array.from(s.match(/../g)!,x=>parseInt(x,16)),{name:'AES-GCM'},false,['encrypt','decrypt']);
}
export async function seal(value:unknown,env:Env,scope:string){
  const iv=crypto.getRandomValues(new Uint8Array(12));
  const body=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:new TextEncoder().encode(scope)},await key(env),new TextEncoder().encode(JSON.stringify(value)));
  return JSON.stringify({v:1,iv:b64(iv),body:b64(new Uint8Array(body))});
}
export async function unseal(value:string,env:Env,scope:string):Promise<{s2?:string;swid?:string}>{
  const data=JSON.parse(value);
  const body=await crypto.subtle.decrypt({name:'AES-GCM',iv:un64(data.iv),additionalData:new TextEncoder().encode(scope)},await key(env),un64(data.body));
  return JSON.parse(new TextDecoder().decode(body));
}
export const subscription=(leagueID:string,season:number,teamID=0,auth:{s2?:string;swid?:string}={}):Subscription=>({id:`${season}:${leagueID}:${teamID}`,connectionID:`${season}:${leagueID}:${teamID}`,leagueID,season,teamID,...auth,ruleIssues:[],enabledAlerts:[],thresholds:{},playerMappings:{},accurateFeedConfirmed:false});
async function body(request:Request):Promise<Record<string,unknown>>{
  if(!request.headers.get('content-type')?.startsWith('application/json'))throw new HTTPError(415,'Send JSON.');
  if(Number(request.headers.get('content-length'))>180000)throw new HTTPError(413,'Request is too large.');
  const reader=request.body?.getReader();if(!reader)throw new HTTPError(400,'Missing request.');
  let data='',size=0;const decoder=new TextDecoder();
  try{while(true){const p=await reader.read();if(p.done)break;size+=p.value.length;if(size>180000){await reader.cancel();throw new HTTPError(413,'Request is too large.');}data+=decoder.decode(p.value,{stream:true});}data+=decoder.decode();}finally{reader.releaseLock();}
  try{const v=JSON.parse(data);if(!v||Array.isArray(v)||typeof v!=='object')throw 0;return v;}catch{throw new HTTPError(400,'Invalid JSON.');}
}
async function limit(db:D1Database,user:string){
  const window=Math.floor(Date.now()/60000);
  const row=await db.prepare('INSERT INTO request_limits(user_id,window,count) VALUES(?,?,1) ON CONFLICT(user_id) DO UPDATE SET window=excluded.window,count=CASE WHEN request_limits.window=excluded.window THEN request_limits.count+1 ELSE 1 END RETURNING count').bind(user,window).first<{count:number}>();
  if((row?.count??0)>40)throw new HTTPError(429,'Too many requests. Try again in one minute.');
}
async function read(db:D1Database,user:string,id:string){
  const row=await db.prepare('SELECT connection,secret FROM leagues WHERE user_id=? AND id=?').bind(user,id).first<Stored>();
  if(!row)throw new HTTPError(404,'This league was not found in your account.');
  return {row,connection:JSON.parse(row.connection) as Connection};
}
const interval=(c:Connection)=>c.games.some(g=>g.phase==='live'||g.phase==='halftime')?60000:900000;
export function makeAPI(client=new ProviderClient()){
  return async(request:Request,env:Env):Promise<Response>=>{
    try{
      const user=identity(request),path=new URL(request.url).pathname;
      if(!['GET','HEAD'].includes(request.method))enforceOrigin(request);
      if(!env.DB)throw new HTTPError(503,'The league database is not ready. Please try again shortly.');
      if(request.method==='GET'&&path==='/api/status')return json({userID:user,privateStorage:!!env.FANTASYGLASS_ENCRYPTION_KEY,provider:'ESPN unofficial read-only endpoints',version:'1.0.0-web'});
      if(request.method==='GET'&&path==='/api/leagues'){
        const rows=await env.DB.prepare('SELECT connection FROM leagues WHERE user_id=? ORDER BY updated_at DESC').bind(user).all<{connection:string}>();
        return json({userID:user,connections:rows.results.map(r=>JSON.parse(r.connection))});
      }
      await limit(env.DB,user);
      if(request.method==='POST'&&path==='/api/connect'){
        const v=leagueInput(await body(request));
        const league=await client.league(subscription(v.leagueID,v.season,0,v));
        return json({name:league.name,week:league.week,teams:league.teams.map(t=>({id:t.id,name:t.name,record:t.record})),rules:league.rules.length,issues:league.issues});
      }
      if(request.method==='POST'&&path==='/api/leagues'){
        const input=await body(request),v=leagueInput(input),teamIDs=input.teamIDs;
        if(!Array.isArray(teamIDs)||!teamIDs.length||teamIDs.length>20||teamIDs.some(x=>!Number.isInteger(x)||Number(x)<0||Number(x)>1000))throw new HTTPError(400,'Select at least one of your teams.');
        const count=await env.DB.prepare('SELECT count(*) AS count FROM leagues WHERE user_id=?').bind(user).first<{count:number}>();
        if((count?.count??0)+teamIDs.length>30)throw new HTTPError(400,'You can follow up to 30 teams. Remove an old connection first.');
        const connections:Connection[]=[];const statements:D1PreparedStatement[]=[];
        for(const teamID of [...new Set(teamIDs)] as number[]){
          const snapshot=await client.league(subscription(v.leagueID,v.season,teamID,v));
          if(!snapshot.teams.some(t=>t.id===teamID))throw new HTTPError(400,'Selected team is not in this league.');
          let games:Connection['games']=[],gamesError:string|undefined;
          try{games=await client.games(v.season,snapshot.week);}catch{gamesError='NFL game status is unavailable. Scores below still use the league feed.';}
          const now=Date.now();
          const c:Connection={id:`${v.season}:${v.leagueID}:${teamID}`,leagueID:v.leagueID,season:v.season,teamID,snapshot,games,fetchedAt:now,gamesFetchedAt:gamesError?0:now,nextRefreshAt:now+60000,privateLeague:!!v.s2,gamesError};
          c.nextRefreshAt=now+interval(c);
          const existing=await env.DB.prepare('SELECT connection FROM leagues WHERE user_id=? AND id=?').bind(user,c.id).first<{connection:string}>();
          if(existing)c.localRules=(JSON.parse(existing.connection) as Connection).localRules;
          const encrypted=v.s2?await seal({s2:v.s2,swid:v.swid},env,`${user}:${c.id}`):null;
          statements.push(env.DB.prepare('INSERT INTO leagues(user_id,id,connection,secret,updated_at) VALUES(?,?,?,?,?) ON CONFLICT(user_id,id) DO UPDATE SET connection=excluded.connection,secret=excluded.secret,updated_at=excluded.updated_at').bind(user,c.id,JSON.stringify(c),encrypted,now));
          connections.push(c);
        }
        await env.DB.batch(statements);return json({connections},201);
      }
      const match=/^\/api\/leagues\/([^/]+)(?:\/(refresh|rules))?$/.exec(path);
      if(match){
        const id=decodeURIComponent(match[1]);const {connection:c,row}=await read(env.DB,user,id);
        if(request.method==='DELETE'&&!match[2]){await env.DB.prepare('DELETE FROM leagues WHERE user_id=? AND id=?').bind(user,id).run();return json({deleted:id});}
        if(request.method==='PATCH'&&match[2]==='rules'){
          c.localRules=validateRules((await body(request)).rules);
          await env.DB.prepare('UPDATE leagues SET connection=?,updated_at=? WHERE user_id=? AND id=?').bind(JSON.stringify(c),Date.now(),user,id).run();return json({connection:c});
        }
        if(request.method==='POST'&&match[2]==='refresh'){
          const v=await body(request),now=Date.now();
          if(now<c.fetchedAt+30000||(!v.force&&now<c.nextRefreshAt))return json({connection:c,cached:true});
          try{
            const auth=row.secret?await unseal(row.secret,env,`${user}:${id}`):{};
            c.snapshot=await client.league(subscription(c.leagueID,c.season,c.teamID,auth));c.fetchedAt=Date.now();c.error=undefined;
            try{c.games=await client.games(c.season,c.snapshot.week);c.gamesFetchedAt=Date.now();c.gamesError=undefined;}catch{c.gamesError='Game status could not refresh. Last known game information is shown.';}
            c.nextRefreshAt=Date.now()+interval(c);
          }catch(error){
            c.error=error instanceof ProviderFailure?`ESPN returned HTTP ${error.status}. ${[401,403].includes(error.status)?'Reconnect this league to update its cookies.':'Your last saved scores are still available.'}`:'The provider could not refresh. Your last saved scores are still available.';
            c.nextRefreshAt=Date.now()+(error instanceof ProviderFailure?Math.max(60,error.retryAfter):300)*1000;
          }
          await env.DB.prepare('UPDATE leagues SET connection=?,updated_at=? WHERE user_id=? AND id=?').bind(JSON.stringify(c),Date.now(),user,id).run();return json({connection:c});
        }
      }
      throw new HTTPError(404,'This endpoint does not exist.');
    }catch(error){
      if(error instanceof HTTPError)return json({error:error.message},error.status);
      if(error instanceof ProviderFailure)return json({error:error.status===404?'ESPN could not find that league and season. Check both values and provide cookies for a private league.':error.status===401||error.status===403?'ESPN refused access. Private leagues need valid espn_s2 and SWID cookies from your own browser session.':error.status===429?'ESPN is limiting requests. Wait before trying again.':`ESPN returned HTTP ${error.status}. Please try again later.`,providerStatus:error.status,retryAfter:error.retryAfter},error.status===429?429:502);
      return json({error:'The request could not complete. Your saved leagues have not been deleted.'},500);
    }
  };
}
