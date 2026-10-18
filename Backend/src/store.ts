import {DatabaseSync} from "node:sqlite";
import {createCipheriv,createDecipheriv,randomBytes,createHash} from "node:crypto";
import {mkdirSync,chmodSync} from "node:fs";
import {dirname} from "node:path";
import type {Subscription, Frame} from "./types.js";
import {canonicalJSON} from "./canonical.js";

export interface QueuedPush { id: string; subscriptionID: string; token: string; kind: "alert"; payload: unknown; attempts: number; created: number; }
export interface StoredSubscription { subscription: Subscription; frame?: Frame; nextPoll: number; lastError?: string; }

export class EncryptedStore {
  readonly db: DatabaseSync;
  constructor(path: string, private readonly key: Buffer) {
    if (key.length !== 32) throw new Error("DATA_ENCRYPTION_KEY must decode to 32 bytes");
    if (path !== ":memory:") mkdirSync(dirname(path),{recursive:true,mode:0o700});
    this.db = new DatabaseSync(path);
    if (path !== ":memory:") chmodSync(path,0o600);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS subscriptions (id TEXT PRIMARY KEY, payload BLOB NOT NULL, frame BLOB, configHash TEXT NOT NULL, updated INTEGER NOT NULL, nextPoll INTEGER NOT NULL DEFAULT 0, lastError TEXT);
      CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, created INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS outbox (id TEXT PRIMARY KEY, subscriptionID TEXT NOT NULL, payload BLOB NOT NULL, created INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, nextAttempt INTEGER NOT NULL DEFAULT 0);`);
  }
  private encrypt(value: unknown): Buffer {
    const nonce = randomBytes(12), cipher = createCipheriv("aes-256-gcm",this.key,nonce);
    const ciphertext = Buffer.concat([cipher.update(JSON.stringify(value),"utf8"),cipher.final()]);
    return Buffer.concat([Buffer.from([1]),nonce,cipher.getAuthTag(),ciphertext]);
  }
  private decrypt<T>(data: Uint8Array): T {
    const blob = Buffer.from(data);
    if (blob[0] !== 1 || blob.length < 30) throw new Error("Unsupported encrypted record");
    const decipher = createDecipheriv("aes-256-gcm",this.key,blob.subarray(1,13));
    decipher.setAuthTag(blob.subarray(13,29));
    return JSON.parse(Buffer.concat([decipher.update(blob.subarray(29)),decipher.final()]).toString("utf8")) as T;
  }
  count(): number { return Number(this.db.prepare("SELECT COUNT(*) AS n FROM subscriptions").get()!.n); }
  get(id: string): StoredSubscription | undefined {
    const row = this.db.prepare("SELECT * FROM subscriptions WHERE id=?").get(id);
    if (!row) return;
    return {subscription:this.decrypt<Subscription>(row.payload as Uint8Array),frame:row.frame ? this.decrypt<Frame>(row.frame as Uint8Array) : undefined,nextPoll:Number(row.nextPoll),lastError:row.lastError ? String(row.lastError) : undefined};
  }
  upsert(sub: Subscription): void {
    const old = this.get(sub.id);
    const hash = createHash("sha256").update(canonicalJSON([sub.rules,sub.ruleIssues,sub.thresholds,sub.playerMappings,sub.sportsDataKey,sub.accurateFeedConfirmed])).digest("hex");
    this.db.prepare(`INSERT INTO subscriptions (id,payload,configHash,updated,nextPoll) VALUES (?,?,?,?,0)
      ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,updated=excluded.updated,
        frame=CASE WHEN subscriptions.configHash=excluded.configHash THEN subscriptions.frame ELSE NULL END,
        nextPoll=CASE WHEN subscriptions.configHash=excluded.configHash THEN subscriptions.nextPoll ELSE 0 END,configHash=excluded.configHash`).run(sub.id,this.encrypt(sub),hash,Date.now());
    if (old?.subscription.deviceToken !== sub.deviceToken || !sub.enabledAlerts.length) {
      const queued = this.db.prepare("SELECT id FROM outbox WHERE subscriptionID=?").all(sub.id);
      for (const row of queued) this.db.prepare("DELETE FROM outbox WHERE id=?").run(String(row.id));
    }
  }
  remove(id: string): void {
    this.db.exec("BEGIN IMMEDIATE");
    try { this.db.prepare("DELETE FROM outbox WHERE subscriptionID=?").run(id); this.db.prepare("DELETE FROM subscriptions WHERE id=?").run(id); this.db.exec("COMMIT"); }
    catch (error) { this.db.exec("ROLLBACK"); throw error; }
  }
  due(now = Date.now()): StoredSubscription[] {
    return this.db.prepare("SELECT id FROM subscriptions WHERE nextPoll<=? ORDER BY nextPoll LIMIT 20").all(now).flatMap(row=>{ const value = this.get(String(row.id)); return value ? [value] : []; });
  }
  fail(id: string, error: string, delay: number): void {
    this.db.prepare("UPDATE subscriptions SET lastError=?,nextPoll=? WHERE id=?").run(error.slice(0,400),Date.now()+delay*1000,id);
  }
  commit(id: string, frame: Frame, delay: number, pushes: Omit<QueuedPush,"attempts"|"created">[], warning?: string): void {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      for (const push of pushes) {
        if (push.kind === "alert") {
          const added = this.db.prepare("INSERT OR IGNORE INTO events (id,created) VALUES (?,?)").run(push.id,Date.now());
          if (!added.changes) continue;
        }
        this.db.prepare(`INSERT INTO outbox (id,subscriptionID,payload,created) VALUES (?,?,?,?)
          ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,created=excluded.created,attempts=0,nextAttempt=0`).run(push.id,id,this.encrypt(push),Date.now());
      }
      this.db.prepare("UPDATE subscriptions SET frame=?,nextPoll=?,lastError=? WHERE id=?").run(this.encrypt(frame),Date.now()+delay*1000,warning ?? null,id);
      this.db.exec("COMMIT");
    } catch (error) { this.db.exec("ROLLBACK"); throw error; }
  }
  pending(now = Date.now()): QueuedPush[] {
    return this.db.prepare("SELECT * FROM outbox WHERE nextAttempt<=? ORDER BY created LIMIT 100").all(now).map(row=>({...this.decrypt<Omit<QueuedPush,"attempts"|"created">>(row.payload as Uint8Array),attempts:Number(row.attempts),created:Number(row.created)}));
  }
  delivered(id: string): void { this.db.prepare("DELETE FROM outbox WHERE id=?").run(id); }
  retry(push: QueuedPush): void {
    this.db.prepare("UPDATE outbox SET attempts=attempts+1,nextAttempt=? WHERE id=?").run(Date.now()+Math.min(900,15*2**Math.min(push.attempts,6))*1000,push.id);
  }
  invalidateToken(id: string, token: string, kind: QueuedPush["kind"]): void {
    const stored = this.get(id); if (!stored) return;
    const sub = stored.subscription;
    if (kind === "alert" && sub.deviceToken === token) delete sub.deviceToken;
    this.db.prepare("UPDATE subscriptions SET payload=? WHERE id=?").run(this.encrypt(sub),id);
  }
  status(): {id:string;lastError:string|null;nextPoll:number}[] {
    return this.db.prepare("SELECT id,lastError,nextPoll FROM subscriptions ORDER BY id").all().map(row=>({id:String(row.id),lastError:row.lastError ? String(row.lastError) : null,nextPoll:Number(row.nextPoll)}));
  }
  prune(now = Date.now()): void {
    this.db.prepare("DELETE FROM events WHERE created<?").run(now-30*86400000);
    this.db.prepare("DELETE FROM outbox WHERE created<?").run(now-86400000);
    for (const row of this.db.prepare("SELECT id FROM subscriptions WHERE updated<?").all(now-30*86400000)) this.remove(String(row.id));
  }
  close(): void { this.db.close(); }
}
