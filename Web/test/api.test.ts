import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync,readdirSync} from 'node:fs';
import {makeAPI,type Env} from '../server/api';
import {ProviderClient} from '../lib/providers';
const fixture=(name:string)=>readFileSync(new URL('./fixtures/'+name,import.meta.url),'utf8');
function setup(){
 const db=new DatabaseSync(':memory:');for(const name of readdirSync('drizzle').filter(f=>f.endsWith('.sql')).sort())db.exec(readFileSync('drizzle/'+name,'utf8'));
 const statement=(sql:string,values:unknown[]=[])=>({bind:(...v:unknown[])=>statement(sql,v),first:async()=>db.prepare(sql).get(...values as never[])??null,all:async()=>({results:db.prepare(sql).all(...values as never[])}),run:async()=>db.prepare(sql).run(...values as never[])});
 const env={DB:{prepare:statement,batch:async(s:{run:()=>Promise<unknown>}[])=>{db.exec('BEGIN');try{const result=[];for(const q of s)result.push(await q.run());db.exec('COMMIT');return result;}catch(e){db.exec('ROLLBACK');throw e;}}},FANTASYGLASS_ENCRYPTION_KEY:'b'.repeat(64)} as unknown as Env;
 const provider=new ProviderClient(async(url)=>new Response(String(url).includes('scoreboard')?fixture('espn-scoreboard.json'):fixture('espn-league.json')));
 const api=makeAPI(provider);
 const request=(path:string,method='GET',body?:unknown,user='owner',origin='https://site.test')=>api(new Request('https://site.test/api'+path,{method,headers:{...(user?{'oai-authenticated-user-id':user}:{}),...(body?{'Content-Type':'application/json','Origin':origin}:{})},body:body?JSON.stringify(body):undefined}),env);
 return {db,env,request};
}
test('API requires identity and same-origin mutations',async()=>{const {request,db}=setup();try{assert.equal((await request('/leagues','GET',undefined,'')).status,401);assert.equal((await request('/connect','POST',{leagueID:'123',season:2026},'owner','https://evil.test')).status,403);}finally{db.close();}});
test('league import, team selection, persistence, overrides and deletion stay owner-scoped',async()=>{
 const {request,db}=setup();try{
 const preview=await request('/connect','POST',{leagueID:'123',season:2026});assert.equal(preview.status,200);
 const add=await request('/leagues','POST',{leagueID:'123',season:2026,teamIDs:[1,2],s2:'secret-test-session',swid:'{test-user}'});assert.equal(add.status,201);
 const data=await add.json() as {connections:{id:string;snapshot:{rules:unknown[]}}[]};assert.equal(data.connections.length,2);assert(!JSON.stringify(data).includes('secret-test-session'));
 const saved=db.prepare('SELECT secret FROM leagues').get() as {secret:string};assert(!saved.secret.includes('secret-test-session'));
 const stranger=await request('/leagues','GET',undefined,'other');assert.deepEqual((await stranger.json() as {connections:unknown[]}).connections,[]);
 const id=data.connections[0].id;
 assert.equal((await request(`/leagues/${id}/rules`,'PATCH',{rules:data.connections[0].snapshot.rules},'other')).status,404);
 assert.equal((await request(`/leagues/${id}/rules`,'PATCH',{rules:data.connections[0].snapshot.rules})).status,200);
 const cached=await request(`/leagues/${id}/refresh`,'POST',{force:true});assert.equal((await cached.json() as {cached:boolean}).cached,true);
 const deletion=new Request('https://site.test/api/leagues/'+id,{method:'DELETE',headers:{'oai-authenticated-user-id':'owner',Origin:'https://site.test'}});
 const handler=makeAPI();assert.equal((await handler(deletion,setupEnv(db))).status,200);
 assert.equal((await request('/leagues').then(r=>r.json()) as {connections:unknown[]}).connections.length,1);
 }finally{db.close();}
});
function setupEnv(db:DatabaseSync){return {DB:{prepare:(sql:string)=>({bind:(...v:never[])=>({first:async()=>db.prepare(sql).get(...v),run:async()=>db.prepare(sql).run(...v)})})}} as unknown as Env;}
