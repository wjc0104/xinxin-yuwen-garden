import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
const source = await readFile(new URL('../dist/sw.js',import.meta.url),'utf8');
const base = 'https://example.test/private/';
function worker(bad = '') {
  const handlers={}, stores=new Map(), fetched=[];
  const caches={
    async open(name) { if(!stores.has(name))stores.set(name,new Map()); const map=stores.get(name);return {async put(url,r){map.set(url,r);},async match(url){return map.get(url);}}; },
    async keys(){return [...stores.keys()];},async delete(key){return stores.delete(key);}
  };
  const fetch=async url=>{
    fetched.push(url);
    const type=url.endsWith('.js')?'text/javascript':url.endsWith('.css')?'text/css':url.endsWith('.svg')?'image/svg+xml':url.endsWith('.html')?'text/html':'application/json';
    const body=url.endsWith('.html')?'<meta name="xinyu-app" content="private-web-v1">':JSON.stringify({schemaVersion:1,lessons:Array(198).fill({}),resources:[],dataVersion:'test'});
    const r=new Response(bad==='login'?'login':body,{status:bad==='denied'?401:200,headers:{'content-type':bad==='login'?'text/html':type}});
    Object.defineProperty(r,'url',{value:url});Object.defineProperty(r,'redirected',{value:bad==='redirect'});return r;
  };
  const self={location:{href:base+'sw.js'},XINYU_VERSION:'test',addEventListener:(name,fn)=>handlers[name]=fn};
  vm.runInNewContext(source,{self,URL,caches,fetch,importScripts:()=>{}});
  const lifecycle=name=>{let promise;handlers[name]({waitUntil:p=>{promise=p;}});return promise;};
  const request=(path,options={})=>{let result;handlers.fetch({request:{url:new URL(path,base).href,method:'GET',cache:'default',...options},respondWith:p=>{result=p;}});return result;};
  return {lifecycle,request,stores,fetched};
}
test('SW caches only fixed app assets, serves offline shell, bypasses API/login/third parties and update checks',async()=>{
  const w=worker();await w.lifecycle('install');assert.equal(w.fetched.length,9);
  const before=w.fetched.length;assert.equal((await w.request('./')).status,200);assert.equal(w.fetched.length,before);
  for(const path of ['login','api/media','https://elsewhere.test/video','index.html?login=1'])assert.equal(w.request(path),undefined);
  assert.equal(w.request('data/catalogue.json',{cache:'no-store'}),undefined);
  assert.equal(w.request('app.js',{method:'POST'}),undefined);
  assert.equal(w.request('../index.html'),undefined);
});
test('SW fails installation without caching login, redirects or denied responses',async()=>{
  for(const bad of ['login','redirect','denied']){const w=worker(bad);await assert.rejects(w.lifecycle('install'));assert.equal(w.stores.size,0);}
});
test('SW only removes obsolete caches for its own path; never forces a running page to update',async()=>{
  const w=worker();w.stores.set('xinyu-public:/private/:old',new Map());w.stores.set('xinyu-public:/other/:old',new Map());w.stores.set('unrelated',new Map());
  await w.lifecycle('install');await w.lifecycle('activate');
  assert.ok(!w.stores.has('xinyu-public:/private/:old'));assert.ok(w.stores.has('xinyu-public:/other/:old'));assert.ok(w.stores.has('unrelated'));
  assert.doesNotMatch(source,/self\.skipWaiting\(|clients\.claim\(|indexedDB\./);
});
test('shipped client uses only native video controls and does not embed third-party players',async()=>{
  const app=await readFile(new URL('../dist/app.js',import.meta.url),'utf8');
  const core=await readFile(new URL('../dist/core.js',import.meta.url),'utf8');
  const html=await readFile(new URL('../dist/index.html',import.meta.url),'utf8');
  assert.doesNotMatch(app+core+html,/player\.bilibili\.com|videoEmbedURL|el\('iframe'/);
  assert.match(html,/frame-src 'none'; media-src 'self'/);assert.match(app,/el\('video',\{controls:true,playsInline:true/);
  assert.doesNotMatch(app,/innerHTML|insertAdjacentHTML/);
});
