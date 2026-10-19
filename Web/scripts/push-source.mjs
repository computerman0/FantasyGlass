// Fallback for environments without the Sites source helper. Never persists credentials.
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
const manifest=JSON.parse(readFileSync('.openai/hosting.json','utf8'));
if(!manifest.project_id)throw new Error('A registered Site ID is required.');
if(process.stdin.isTTY)process.stdin.setRawMode(true);
process.stdin.setEncoding('utf8');process.stdout.write('Ready for source credential JSON on stdin (input is hidden).\n');
let input='';
process.stdin.on('data',chunk=>{
 input+=chunk;if(!input.includes('\n'))return;
 process.stdin.pause();if(process.stdin.isTTY)process.stdin.setRawMode(false);
 try{
  const credential=JSON.parse(input.trim());input='';
  if(credential.auth_mode!=='http_extra_header'||!credential.remote_url.startsWith('https://')||!credential.remote_url.endsWith('/'+manifest.project_id+'.git'))throw Error('Credential does not match this Site.');
  const env={...process.env,GIT_TERMINAL_PROMPT:'0',GIT_CONFIG_COUNT:'1',GIT_CONFIG_KEY_0:`http.${credential.remote_url}.extraHeader`,GIT_CONFIG_VALUE_0:`Authorization: Bearer ${credential.token}`};
  const run=spawnSync('git',['push',credential.remote_url,`HEAD:refs/heads/${credential.branch}`],{env,encoding:'utf8'});
  if(run.status!==0){process.stderr.write((run.stderr??'Push failed').replaceAll(credential.token,'[redacted]'));process.exit(run.status??1);}
  const sha=spawnSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).stdout.trim();
  console.log(JSON.stringify({project_id:manifest.project_id,commit_sha:sha}));process.exit(0);
 }catch(e){console.error(e.message);process.exit(1);}
});
