import {createServer} from 'node:http';
import {DatabaseSync} from 'node:sqlite';
import {mkdirSync,readFileSync,readdirSync} from 'node:fs';
import {randomBytes} from 'node:crypto';
const {default:worker}=await import('../dist/server/index.js');
mkdirSync('.local',{recursive:true});const db=new DatabaseSync('.local/fantasyglass.sqlite');
db.exec('CREATE TABLE IF NOT EXISTS _migrations (name TEXT PRIMARY KEY)');
for(const name of readdirSync('drizzle').filter(f=>f.endsWith('.sql')).sort()){if(!db.prepare('SELECT name FROM _migrations WHERE name=?').get(name)){db.exec(readFileSync('drizzle/'+name,'utf8'));db.prepare('INSERT INTO _migrations(name) VALUES(?)').run(name);}}
class Statement{constructor(sql,values=[]){this.sql=sql;this.values=values;}bind(...values){return new Statement(this.sql,values);}async first(){return db.prepare(this.sql).get(...this.values)??null;}async all(){return {results:db.prepare(this.sql).all(...this.values),success:true};}async run(){db.prepare(this.sql).run(...this.values);return {success:true};}}
const env={DB:{prepare:sql=>new Statement(sql),batch:async statements=>{db.exec('BEGIN');try{const r=[];for(const s of statements)r.push(await s.run());db.exec('COMMIT');return r;}catch(e){db.exec('ROLLBACK');throw e;}}},FANTASYGLASS_ENCRYPTION_KEY:process.env.FANTASYGLASS_ENCRYPTION_KEY??randomBytes(32).toString('hex')};
const server=createServer(async(req,res)=>{try{const chunks=[];for await(const chunk of req)chunks.push(chunk);const headers=new Headers();for(const [k,v]of Object.entries(req.headers))if(v)headers.set(k,Array.isArray(v)?v.join(','):v);headers.set('oai-authenticated-user-id','local-development');headers.set('oai-authenticated-user-email','local@example.test');const request=new Request('http://127.0.0.1:5173'+req.url,{method:req.method,headers,body:['GET','HEAD'].includes(req.method)?undefined:Buffer.concat(chunks)});const response=await worker.fetch(request,env);res.writeHead(response.status,Object.fromEntries(response.headers));res.end(Buffer.from(await response.arrayBuffer()));}catch{res.writeHead(500);res.end('Development request failed');}});
server.listen(5173,'127.0.0.1',()=>console.log('Local preview: http://127.0.0.1:5173 (development identity only)'));
