import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync,mkdtempSync,rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {randomBytes,generateKeyPairSync,verify} from "node:crypto";
import {createServer} from "node:http";
import {d,parseProviderJSON} from "../src/decimal.js";
import {score,observation} from "../src/scoring.js";
import {ProviderClient,ProviderFailure,decodeLeague,decodeGames} from "../src/providers.js";
import {EncryptedStore} from "../src/store.js";
import {requestHandler} from "../src/http.js";
import {validateSubscription} from "../src/validation.js";
import {detectEvents} from "../src/events.js";
import {Worker,pollInterval} from "../src/worker.js";
import {APNsClient,livePayload} from "../src/apns.js";
import type {Subscription,Rule,Frame,Game} from "../src/types.js";
import {canonicalJSON} from "../src/canonical.js";

const fixtures = new URL("../../../Core/Tests/FantasyCoreTests/Fixtures/",import.meta.url);
const fixture = (name: string)=>readFileSync(new URL(name,fixtures),"utf8");
const sub = (): Subscription=>({id:"device:espn:2026:123:1",connectionID:"espn:2026:123:1",leagueID:"123",season:2026,teamID:1,ruleIssues:[],enabledAlerts:["touchdown","leadChange","threshold","injuredOut","halftime","final","closeFinalGame","correction"],thresholds:{"3918298":"30"},playerMappings:{},accurateFeedConfirmed:false});
const linear = (stat: string,multiplier: string): Rule=>({id:stat,stat,label:stat,multiplier,mode:"linear",positionMultipliers:{}});
const league = ()=>decodeLeague(parseProviderJSON(fixture("espn-league.json")),sub());

test("exact decimal arithmetic and JSON number preservation",()=>{
  assert.equal(d("0.123456789123456789").multiply(d(3)).toString(),"0.370370367370370367");
  assert.equal(d("-19").wholeDivide(d(10)).toString(),"-1");
  assert.equal(d("2.5e-3").toString(),"0.0025");
  assert.deepEqual(parseProviderJSON('{"n":0.123456789123456789,"name":"Player 99","quote":"a\\\"7","active":true}'),{n:"0.123456789123456789",name:"Player 99",quote:'a"7',active:true});
  assert.throws(()=>d("NaN"));
});
test("standard, half PPR, full PPR and independent league settings",()=>{
  for (const [rate,expected] of [["0","7.6"],["0.5","11.1"],["1","14.6"]]) assert.equal(score({"42":"76","53":"7"},"4",[linear("42","0.1"),linear("53",rate!)]),expected);
});
test("shared Swift/backend scoring contract",()=>{
  const cases = parseProviderJSON(fixture("scoring-contract.json")) as {name:string;stats:Record<string,string>;position:string;rules:Rule[];expected:string}[];
  for (const example of cases) assert.equal(score(example.stats,example.position,example.rules),example.expected,example.name);
});
test("bonuses, penalties, corrections and position overrides",()=>{
  const rules: Rule[] = [linear("3","0.033333"),{...linear("3","3"),id:"bonus",mode:"threshold",lower:"300"},linear("20","-3"),{...linear("24","1"),mode:"perWhole",lower:"10"}];
  assert.equal(score({"3":"301","20":"6","24":"-19"},"0",rules),"-5.966767");
  const defense = [{...linear("95","0"),positionMultipliers:{"16":"2"}}];
  assert.equal(score({"95":"2"},"16",defense),"4");
  assert.equal(score({"95":"2"},"0",defense),"0");
  assert.equal(score({"24":"99","72":"2"},"2",[linear("24","0.1"),linear("72","-2")]),"5.9");
});
test("real-shaped league import and live content contract",()=>{
  const parsed = league(); assert.equal(parsed.teams.length,2); assert.equal(parsed.week,7);
  const result = observation(sub(),parsed,[],1760000000);
  assert.equal(result.content.myScore,"27.5"); assert.equal(result.content.opponentScore,"16");
  assert.equal(result.content.leader,1); assert.equal(result.content.updatedAt,1760000000);
  assert.equal(result.frame.players["3918298"]?.touchdowns,"3");
  const payload = livePayload(result.content,1760000000) as {aps:Record<string,unknown>};
  assert.equal(payload.aps.event,"update"); assert.equal(payload.aps["stale-date"],1760000180);
  assert(Buffer.byteLength(JSON.stringify(payload)) < 3500);
});
test("missing data and multi-week rosters cannot assert local aggregates",()=>{
  const parsed = league(); delete parsed.teams[0]!.players[0]!.stats;
  assert.equal(observation(sub(),parsed,[],0).content.myScore,"27.5");
  assert.equal(observation(sub(),parsed,[],0).content.scoreSource,"ESPN / partial local");
  parsed.matchup!.weeks = [7,8]; assert.equal(observation(sub(),parsed,[],0).content.myProjection,undefined);
});
test("historical ESPN scoreboard and idle polling",()=>{
  const games = decodeGames(parseProviderJSON(fixture("espn-scoreboard.json")));
  assert(games.length > 0); assert(games.some(g=>g.phase === "final"));
  assert.equal(pollInterval(games,Date.now()/1000),3600);
  assert.equal(pollInterval([{...games[0]!,phase:"live"}],Date.now()/1000),60);
});
test("provider request construction and private auth",async()=>{
  let requested = "", cookie = "";
  const transport: typeof fetch = async (url,options)=>{ requested = String(url); cookie = (options?.headers as Record<string,string>).Cookie ?? ""; return new Response(fixture("espn-league.json")); };
  const auth = {...sub(),s2:"fixture-cookie",swid:"{fixture-user}"};
  const parsed = await new ProviderClient(transport).league(auth);
  assert.equal(parsed.id,"123"); assert(requested.includes("view=mSettings")); assert.equal(cookie,"espn_s2=fixture-cookie; SWID={fixture-user}");
});
test("provider cooldown and error responses",async()=>{
  let count = 0;
  const limited = new ProviderClient(async()=>{ count++; return new Response("",{status:429,headers:{"Retry-After":"300"}}); });
  for (let i=0;i<2;i++) await assert.rejects(limited.league(sub()),(e:unknown)=>e instanceof ProviderFailure && e.status === 429);
  assert.equal(count,1);
  for (const status of [401,403,404]) await assert.rejects(new ProviderClient(async()=>new Response("",{status})).league(sub()),(e:unknown)=>e instanceof ProviderFailure && e.status === status);
  await assert.rejects(limited.get("https://untrusted.example/"),/not allowed/);
});
test("event transitions, thresholds and stat correction results",()=>{
  const before = observation(sub(),league(),[],1).frame;
  const current = structuredClone(before);
  current.players["3918298"]!.touchdowns = "4"; current.players["3918298"]!.points = "31.5"; current.players["3918298"]!.injury = "OUT";
  current.ownScore = "15"; current.opponentScore = "16"; current.lastGameLive = true;
  assert.equal(detectEvents(undefined,current,sub()).length,0);
  const kinds = detectEvents(before,current,sub()).map(e=>e.kind);
  for (const kind of ["touchdown","threshold","injuredOut","leadChange","closeFinalGame"]) assert(kinds.includes(kind as typeof kinds[number]));
  assert.equal(detectEvents(current,current,sub()).length,0);
  before.finished = true; current.finished = true;
  assert(detectEvents(before,current,sub()).some(e=>e.kind === "correction"));
});
test("encrypted persistence, deduplication, retry and deletion",()=>{
  const directory = mkdtempSync(join(tmpdir(),"fantasyglass-test-")), path = join(directory,"test.sqlite"), key = randomBytes(32);
  try {
    let store = new EncryptedStore(path,key);
    store.upsert({...sub(),s2:"fixture-secret-never-plaintext",swid:"{fixture}"});
    assert.equal(store.get(sub().id)?.subscription.s2,"fixture-secret-never-plaintext");
    const raw = store.db.prepare("SELECT payload FROM subscriptions").get()!.payload as Uint8Array;
    assert(!Buffer.from(raw).includes(Buffer.from("fixture-secret-never-plaintext")));
    const frame = observation(sub(),league(),[],1).frame;
    const push = {id:"event-1",subscriptionID:sub().id,token:"a".repeat(64),kind:"alert" as const,payload:{aps:{alert:"score"}}};
    store.commit(sub().id,frame,60,[push]); store.commit(sub().id,frame,60,[push]);
    assert.equal(store.pending().length,1); store.retry(store.pending()[0]!); assert.equal(store.pending().length,0);
    store.close(); store = new EncryptedStore(path,key);
    assert.equal(store.get(sub().id)?.frame?.ownScore,"27.5");
    store.remove(sub().id); assert.equal(store.count(),0); assert.equal(store.pending(Date.now()+999999).length,0); store.close();
  } finally { rmSync(directory,{recursive:true,force:true}); }
});
test("configuration changes reset event baselines and token rotation removes obsolete pushes",()=>{
  const store = new EncryptedStore(":memory:",randomBytes(32)), original = {...sub(),activityToken:"a".repeat(64)};
  store.upsert(original); const frame = observation(sub(),league(),[],0).frame;
  store.commit(original.id,frame,900,[{id:`live:${original.id}`,subscriptionID:original.id,token:original.activityToken,kind:"liveactivity",payload:{}}]);
  store.upsert({...original,activityToken:"b".repeat(64)}); assert.equal(store.pending().length,0); assert(store.get(original.id)?.frame);
  store.upsert({...original,rules:[linear("3","1")]}); assert.equal(store.get(original.id)?.frame,undefined); store.close();
});
test("map key ordering does not reset persisted notification baselines",()=>{
  const store = new EncryptedStore(":memory:",randomBytes(32));
  const first = {...sub(),thresholds:{"1":"20","2":"30"}};
  store.upsert(first); store.commit(first.id,observation(sub(),league(),[],0).frame,60,[]);
  store.upsert({...first,thresholds:{"2":"30","1":"20"}});
  assert(store.get(first.id)?.frame); assert.equal(canonicalJSON({z:1,a:2}),canonicalJSON({a:2,z:1})); store.close();
});
test("APNs JWT signature uses ES256 and cached tokens",()=>{
  const {privateKey,publicKey} = generateKeyPairSync("ec",{namedCurve:"prime256v1"});
  const client = new APNsClient({teamID:"TESTTEAMID",keyID:"TESTKEY123",bundleID:"com.example.FantasyGlass",environment:"sandbox",privateKey:privateKey.export({type:"pkcs8",format:"pem"}).toString()});
  const token = client.authorization(1000), pieces = token.split(".");
  assert(verify("sha256",Buffer.from(`${pieces[0]}.${pieces[1]}`),{key:publicKey,dsaEncoding:"ieee-p1363"},Buffer.from(pieces[2]!,"base64url")));
  assert.equal(client.authorization(2000),token); assert.notEqual(client.authorization(5001),token);
});
test("validation rejects header injection, invalid rules and arbitrary destinations",()=>{
  assert.deepEqual(JSON.parse(JSON.stringify(validateSubscription(sub(),sub().id))),sub());
  for (const value of [{...sub(),s2:"x\nheader",swid:"x"},{...sub(),leagueID:"../evil"},{...sub(),rules:[{...linear("3","1"),mode:"perWhole",lower:"0"}]},{...sub(),activityToken:"not-a-token"}]) assert.throws(()=>validateSubscription(value,sub().id));
});
test("authenticated HTTP import, status and deletion never echo secrets",async()=>{
  const store = new EncryptedStore(":memory:",randomBytes(32)), owner = randomBytes(32).toString("hex");
  const server = createServer((req,res)=>{ void requestHandlerSingleton(req,res); });
  const requestHandlerSingleton = requestHandler(store,{ownerToken:owner,apnsConfigured:false,environment:"sandbox",maxSubscriptions:3});
  await new Promise<void>(resolve=>server.listen(0,"127.0.0.1",resolve));
  const address = server.address(); assert(address && typeof address !== "string");
  const base = `http://127.0.0.1:${address.port}`, headers = {Authorization:`Bearer ${owner}`,"Content-Type":"application/json"};
  try {
    assert.equal((await fetch(base+"/v1/status")).status,401);
    const response = await fetch(base+`/v1/subscriptions/${sub().id}`,{method:"PUT",headers,body:JSON.stringify({...sub(),s2:"fixture-secret",swid:"{user}"})});
    assert.equal(response.status,200); assert(!(await response.text()).includes("fixture-secret"));
    const status = await fetch(base+"/v1/status",{headers}); assert.equal(status.status,200); assert(!(await status.text()).includes("fixture-secret"));
    assert.equal((await fetch(base+`/v1/subscriptions/${sub().id}`,{method:"DELETE",headers})).status,200); assert.equal(store.count(),0);
  } finally { await new Promise<void>(resolve=>server.close(()=>resolve())); store.close(); }
});
test("scheduled refresh retains cached frame during provider outage",async()=>{
  const store = new EncryptedStore(":memory:",randomBytes(32)); store.upsert(sub());
  const transport: typeof fetch = async url=>new Response(String(url).includes("scoreboard") ? fixture("espn-scoreboard.json") : fixture("espn-league.json"));
  await new Worker(store,new ProviderClient(transport)).tick();
  assert.equal(store.get(sub().id)?.frame?.ownScore,"27.5");
  store.db.prepare("UPDATE subscriptions SET nextPoll=0").run();
  await new Worker(store,new ProviderClient(async()=>new Response("",{status:401}))).tick();
  assert.equal(store.get(sub().id)?.frame?.ownScore,"27.5"); assert.match(store.get(sub().id)?.lastError ?? "",/401/); store.close();
});
test("public ESPN request through the backend adapter",{skip:process.env.FANTASYGLASS_LIVE_SMOKE !== "1"},async()=>{
  const result = await new ProviderClient().league({...sub(),leagueID:"48153503",season:2019});
  assert.equal(result.teams.length,14); assert(result.rules.length > 0);
  const games = await new ProviderClient().games(2025,6);
  assert.equal(games.length,15); assert(games.every(game=>game.phase === "final"));
});
