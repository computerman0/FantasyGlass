import {createHash,timingSafeEqual} from "node:crypto";
import type {IncomingMessage,ServerResponse} from "node:http";
import {EncryptedStore} from "./store.js";
import {InputError,validateSubscription} from "./validation.js";

export interface ServerConfig { ownerToken: string; apnsConfigured: boolean; environment: string; maxSubscriptions: number; }
export function requestHandler(store: EncryptedStore, config: ServerConfig) {
  const expected = createHash("sha256").update(config.ownerToken).digest();
  const rateLimits = new Map<string,{window:number;count:number}>();
  function reply(res: ServerResponse, code: number, value: unknown): void {
    res.writeHead(code,{"Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store","X-Content-Type-Options":"nosniff"});
    res.end(JSON.stringify(value));
  }
  return async (req: IncomingMessage, res: ServerResponse): Promise<void> => {
    try {
      const ip = req.socket.remoteAddress ?? "unknown", now = Date.now();
      const bucket = rateLimits.get(ip);
      if (!bucket || now-bucket.window >= 60000) rateLimits.set(ip,{window:now,count:1});
      else if (++bucket.count > 120) { res.setHeader("Retry-After","60"); reply(res,429,{error:"Request rate limit exceeded"}); return; }
      if (rateLimits.size > 10000) for (const [key,value] of rateLimits) if (now-value.window >= 60000) rateLimits.delete(key);
      const url = new URL(req.url ?? "/","http://localhost");
      if (url.pathname === "/health" && req.method === "GET") { reply(res,200,{status:"ok"}); return; }
      const header = req.headers.authorization ?? "";
      const supplied = createHash("sha256").update(header.startsWith("Bearer ") ? header.slice(7) : "").digest();
      if (!timingSafeEqual(expected,supplied)) { reply(res,401,{error:"Invalid owner token"}); return; }
      if (url.pathname === "/v1/status" && req.method === "GET") { reply(res,200,{apnsConfigured:config.apnsConfigured,environment:config.environment,subscriptions:store.status(),polling:"60 seconds while games are active; 15 minutes idle; one hour for old completed weeks"}); return; }
      const match = /^\/v1\/subscriptions\/([^/]+)$/.exec(url.pathname);
      if (!match) { reply(res,404,{error:"Endpoint not found"}); return; }
      const id = decodeURIComponent(match[1]!);
      if (req.method === "DELETE") { store.remove(id); reply(res,200,{removed:true}); return; }
      if (req.method !== "PUT") { res.setHeader("Allow","PUT, DELETE"); reply(res,405,{error:"Method not allowed"}); return; }
      if (!String(req.headers["content-type"] ?? "").startsWith("application/json")) { reply(res,415,{error:"Use application/json"}); return; }
      if (Number(req.headers["content-length"] ?? 0) > 131072) { reply(res,413,{error:"Request exceeds 128 KiB"}); return; }
      const chunks: Buffer[] = []; let length = 0;
      for await (const chunk of req) {
        const data = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
        length += data.length;
        if (length > 131072) { reply(res,413,{error:"Request exceeds 128 KiB"}); return; }
        chunks.push(data);
      }
      let body: unknown;
      try { body = JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { throw new InputError("Malformed JSON"); }
      const sub = validateSubscription(body,id);
      if (!store.get(id) && store.count() >= config.maxSubscriptions) { reply(res,409,{error:"Subscription limit reached"}); return; }
      store.upsert(sub);
      reply(res,200,{saved:true});
    } catch (error) {
      if (error instanceof InputError || error instanceof URIError) reply(res,400,{error:error.message});
      else reply(res,500,{error:"Internal error; no credentials are included in this response"});
    }
  };
}
