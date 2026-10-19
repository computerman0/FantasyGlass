import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {d,parseProviderJSON} from '../lib/decimal';
import {score,teamScore} from '../lib/scoring';
import {ProviderClient,ProviderFailure,decodeLeague} from '../lib/providers';
import {subscription,credentials,leagueInput,validateRules,seal,unseal,type Env} from '../server/api';
import type {Rule} from '../lib/types';
const fixture=(name:string)=>readFileSync(new URL('./fixtures/'+name,import.meta.url),'utf8');
test('shared scoring contract: standard, PPR, negative, fractional, kickers, defense, bonuses and corrections',()=>{
 const cases=JSON.parse(fixture('scoring-contract.json')) as {name:string;stats:Record<string,string>;position:string;rules:Rule[];expected:string}[];
 for(const c of cases)assert.equal(score(c.stats,c.position,c.rules),c.expected,c.name);
});
test('decimal math and provider parsing preserve exact precision',()=>{
 assert.equal(d('0.123456789123456789').multiply(d('3')).toString(),'0.370370367370370367');
 assert.deepEqual(parseProviderJSON('{"value":0.123456789123456789,"text":"42"}'),{value:'0.123456789123456789',text:'42'});
});
test('provider import keeps actual stats and readable rule labels',()=>{
 const league=decodeLeague(parseProviderJSON(fixture('espn-league.json')),subscription('123',2026,1));
 assert.equal(league.teams.length,2);assert.equal(league.week,7);assert.equal(league.rules.find(r=>r.stat==='3')?.label,'Passing yards');
 assert.equal(teamScore(league.teams[0],league,league.rules,[],[]).local,'27.5');
});
test('provider requests use allowlisted hosts, cache by credentials, and respect limits',async()=>{
 let calls=0;const cookies:string[]=[];
 const client=new ProviderClient(async(_url,options)=>{calls++;cookies.push((options?.headers as Record<string,string>).Cookie??'');return new Response(fixture('espn-league.json'));});
 await client.league(subscription('123',2026,1,{s2:'session-one',swid:'{user}'}));
 await client.league(subscription('123',2026,2,{s2:'session-one',swid:'{user}'}));
 await client.league(subscription('123',2026,1,{s2:'session-two',swid:'{user}'}));
 assert.equal(calls,2);assert.equal(cookies[0],'espn_s2=session-one; SWID={user}');
 await assert.rejects(client.get('https://untrusted.invalid/'),/not allowed/);
 const limited=new ProviderClient(async()=>new Response('',{status:429,headers:{'Retry-After':'300'}}));
 await assert.rejects(limited.league(subscription('123',2026)),e=>e instanceof ProviderFailure&&e.retryAfter===300);
 await assert.rejects(limited.league(subscription('123',2026)),e=>e instanceof ProviderFailure&&e.status===429);
});
test('missing stats and multi-week playoffs use official totals',()=>{
 const l=decodeLeague(parseProviderJSON(fixture('espn-league.json')),subscription('123',2026,1));
 delete l.teams[0].players[0].stats;assert.equal(teamScore(l.teams[0],l,l.rules,[],[]).local,undefined);
 assert.equal(teamScore(l.teams[0],l,l.rules,[],[]).official,'27.5');
});
test('credentials and custom rules reject injection and malformed input',()=>{
 assert.throws(()=>credentials({s2:'a; SWID=bad',swid:'{x}'}));assert.throws(()=>credentials({s2:'a'}));
 assert.equal(leagueInput({leagueID:'https://fantasy.espn.com/football/league?leagueId=123',season:2026}).leagueID,'123');
 assert.throws(()=>leagueInput({leagueID:'https://evil.test/?leagueId=123',season:2026}));
 const r:Rule={id:'x',stat:'3',label:'Pass yards',mode:'linear',multiplier:'0.04',positionMultipliers:{}};
 assert.equal(validateRules([r])?.[0].multiplier,'0.04');assert.equal(validateRules(null),undefined);
 assert.throws(()=>validateRules([r,r]));assert.throws(()=>validateRules([{...r,mode:'perWhole',lower:'0'}]));
});
test('encrypted private cookies are authenticated and bound to user and league',async()=>{
 const env={FANTASYGLASS_ENCRYPTION_KEY:'a'.repeat(64)} as Env;
 const encrypted=await seal({s2:'private-cookie',swid:'{private-user}'},env,'owner:league');
 assert(!encrypted.includes('private-cookie'));assert.deepEqual(await unseal(encrypted,env,'owner:league'),{s2:'private-cookie',swid:'{private-user}'});
 await assert.rejects(unseal(encrypted,env,'another-owner:league'));
});
test('real historical public ESPN league', {skip:process.env.FANTASYGLASS_LIVE_TESTS!=='1'},async()=>{
 const l=await new ProviderClient().league(subscription('48153503',2019,1));assert.equal(l.id,'48153503');assert(l.teams.length>0);console.log(`Verified historical public ESPN league: ${l.name}, ${l.teams.length} teams. Current/private access not tested.`);
});
