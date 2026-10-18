import {connect, type IncomingHttpHeaders} from "node:http2";
import {createPrivateKey, sign, createHash, type KeyObject} from "node:crypto";
import type {ContentState} from "./types.js";

export interface APNsConfig { teamID: string; keyID: string; privateKey: string; bundleID: string; environment: "sandbox"|"production"; }
export interface PushResult { status: number; reason?: string; }
export function livePayload(content: ContentState, now: number, ending = false): unknown {
  return {aps:{timestamp:Math.floor(now),event:ending ? "end" : "update","content-state":content,"stale-date":Math.floor(now+180),...(ending ? {"dismissal-date":Math.floor(now+3600)} : {})}};
}
export class APNsClient {
  private key: KeyObject;
  private jwt?: {value:string;created:number};
  constructor(private readonly config: APNsConfig) {
    this.key = createPrivateKey(config.privateKey);
    if (this.key.asymmetricKeyType !== "ec" || this.key.asymmetricKeyDetails?.namedCurve !== "prime256v1") throw new Error("APNs requires a P-256 EC signing key");
  }
  authorization(now = Math.floor(Date.now()/1000)): string {
    if (this.jwt && now-this.jwt.created < 3000) return this.jwt.value;
    const header = Buffer.from(JSON.stringify({alg:"ES256",kid:this.config.keyID})).toString("base64url");
    const claims = Buffer.from(JSON.stringify({iss:this.config.teamID,iat:now})).toString("base64url");
    const unsigned = `${header}.${claims}`;
    const signature = sign("sha256",Buffer.from(unsigned),{key:this.key,dsaEncoding:"ieee-p1363"}).toString("base64url");
    this.jwt = {value:`${unsigned}.${signature}`,created:now}; return this.jwt.value;
  }
  async send(token: string, kind: "alert"|"liveactivity", payload: unknown, collapseID: string): Promise<PushResult> {
    const body = JSON.stringify(payload);
    if (Buffer.byteLength(body) > 4096) throw new Error("APNs payload exceeds 4 KB");
    if (!/^[a-fA-F0-9]{32,512}$/.test(token)) throw new Error("Invalid push token");
    const origin = this.config.environment === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
    return new Promise((resolve,reject)=>{
      const session = connect(origin);
      const timer = setTimeout(()=>{ session.destroy(); reject(new Error("APNs request timed out")); },20000);
      session.on("error",error=>{ clearTimeout(timer); reject(error); });
      const request = session.request({":method":"POST",":path":`/3/device/${token}`,authorization:`bearer ${this.authorization()}`,
        "apns-topic":kind === "liveactivity" ? `${this.config.bundleID}.push-type.liveactivity` : this.config.bundleID,
        "apns-push-type":kind,"apns-priority":kind === "liveactivity" ? "5" : "10",
        "apns-expiration":String(Math.floor(Date.now()/1000)+(kind === "liveactivity" ? 180 : 3600)),
        "apns-collapse-id":createHash("sha256").update(collapseID).digest("hex"),"content-type":"application/json"});
      let headers: IncomingHttpHeaders = {}, response = "";
      request.on("response",value=>{ headers = value; });
      request.setEncoding("utf8"); request.on("data",chunk=>{ response += String(chunk); });
      request.on("error",error=>{ clearTimeout(timer); session.destroy(); reject(error); });
      request.on("end",()=>{
        clearTimeout(timer); session.close();
        let reason: string | undefined;
        try { reason = (JSON.parse(response) as {reason?:string}).reason; } catch { /* Successful APNs responses have no body. */ }
        resolve({status:Number(headers[":status"] ?? 500),reason});
      });
      request.end(body);
    });
  }
}
