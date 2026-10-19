import {makeAPI,type Env} from './api';
import {assets,html} from '../.sites-runtime/assets';
const api=makeAPI();
const headers={
 'X-Content-Type-Options':'nosniff',
 'Referrer-Policy':'same-origin',
 'Permissions-Policy':'camera=(), microphone=(), geolocation=()',
 'Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data:; connect-src 'self'; worker-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'self' https://chatgpt.com https://*.chatgpt.com"
};
export default {async fetch(request:Request,env:Env):Promise<Response>{
 const url=new URL(request.url);
 if(url.pathname.startsWith('/api/'))return api(request,env);
 if(!['GET','HEAD'].includes(request.method))return new Response('Method not allowed',{status:405,headers});
 const asset=assets[url.pathname];
 if(asset)return new Response(request.method==='HEAD'?null:asset.body,{headers:{...headers,'Content-Type':asset.type,'Cache-Control':url.pathname==='/sw.js'?'no-cache':url.pathname.startsWith('/assets/')?'public, max-age=31536000, immutable':'public, max-age=3600'}});
 if(url.pathname!=='/'&&url.pathname!=='/index.html')return new Response('Not found',{status:404,headers});
 return new Response(request.method==='HEAD'?null:html,{headers:{...headers,'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store'}});
}};
