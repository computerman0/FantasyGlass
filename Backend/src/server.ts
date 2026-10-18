import {createServer as httpServer} from "node:http";
import {createServer as httpsServer} from "node:https";
import {readFileSync} from "node:fs";
import {EncryptedStore} from "./store.js";
import {ProviderClient} from "./providers.js";
import {APNsClient} from "./apns.js";
import {requestHandler} from "./http.js";
import {Worker} from "./worker.js";

function required(name: string): string { const value = process.env[name]; if (!value) throw new Error(`Missing ${name}`); return value; }
const ownerToken = required("OWNER_TOKEN");
if (ownerToken.length < 32) throw new Error("OWNER_TOKEN must be at least 32 random characters");
const encryptionKey = Buffer.from(required("DATA_ENCRYPTION_KEY"),"base64");
const host = process.env.BIND_HOST ?? "127.0.0.1", port = Number(process.env.PORT ?? 8080);
const tlsKey = process.env.TLS_KEY_FILE, tlsCert = process.env.TLS_CERT_FILE;
if (!!tlsKey !== !!tlsCert) throw new Error("Supply both TLS_KEY_FILE and TLS_CERT_FILE");
if (!["127.0.0.1","::1","localhost"].includes(host) && !tlsKey) throw new Error("Public binding requires TLS. Prefer a local HTTPS reverse proxy.");
const environment = process.env.APNS_ENVIRONMENT ?? "sandbox";
if (!["sandbox","production"].includes(environment)) throw new Error("Invalid APNS_ENVIRONMENT");
const apns = process.env.APNS_KEY_FILE ? new APNsClient({teamID:required("APNS_TEAM_ID"),keyID:required("APNS_KEY_ID"),privateKey:readFileSync(required("APNS_KEY_FILE"),"utf8"),bundleID:required("APNS_BUNDLE_ID"),environment:environment as "sandbox"|"production"}) : undefined;
const store = new EncryptedStore(process.env.DATABASE_PATH ?? "./data/fantasyglass.sqlite",encryptionKey);
const handler = requestHandler(store,{ownerToken,apnsConfigured:!!apns,environment,maxSubscriptions:100});
const listener = (req: Parameters<typeof handler>[0], res: Parameters<typeof handler>[1])=>{ void handler(req,res); };
const server = tlsKey && tlsCert ? httpsServer({key:readFileSync(tlsKey),cert:readFileSync(tlsCert),minVersion:"TLSv1.2"},listener) : httpServer(listener);
server.requestTimeout = 30000; server.headersTimeout = 10000;
server.listen(port,host,()=>{ console.log(`FantasyGlass backend listening on ${host}:${port}; APNs ${apns ? environment : "not configured"}`); });
const worker = new Worker(store,new ProviderClient(),apns);
const tick = ()=>{ void worker.tick().catch(()=>console.error("Worker cycle failed; inspect authenticated status without logging credentials")); };
const timer = setInterval(tick,15000); tick();
let shuttingDown = false;
for (const signal of ["SIGINT","SIGTERM"] as const) process.on(signal,()=>{
  if (shuttingDown) return; shuttingDown = true;
  clearInterval(timer);
  server.close(()=>{ process.exit(0); });
  setTimeout(()=>process.exit(0),25000).unref();
});
