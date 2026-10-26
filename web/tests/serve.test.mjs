import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
test('loopback HTTP serves generated app assets with expected MIME and excludes parent files',{timeout:15000},async()=>{
  const child=spawn(process.execPath,[fileURLToPath(new URL('../scripts/serve.mjs',import.meta.url))],{env:{...process.env,PORT:'0'},stdio:['ignore','pipe','pipe']});
  try{
    const output=await Promise.race([once(child.stdout,'data').then(([chunk])=>chunk.toString()),once(child,'exit').then(()=>{throw new Error('Local server exited early');})]);
    const origin=output.match(/http:\/\/127\.0\.0\.1:\d+/)?.[0];assert.ok(origin);
    const assets={'/':'text/html','/app.js':'text/javascript','/core.js':'text/javascript','/storage.js':'text/javascript','/sw.js':'text/javascript','/version.js':'text/javascript','/style.css':'text/css','/icon.svg':'image/svg+xml','/manifest.webmanifest':'application/manifest+json','/data/catalogue.json':'application/json'};
    for(const [path,type] of Object.entries(assets)){const r=await fetch(origin+path);assert.equal(r.status,200,path);assert.ok(r.headers.get('content-type').startsWith(type),path);assert.ok((await r.text()).length>0,path);}
    const data=await (await fetch(origin+'/data/catalogue.json')).json();assert.equal(data.lessons.length,198);assert.equal(data.resources.length,1163);
    assert.equal((await fetch(origin+'/..%2F..%2FApp%2FResources%2Fcatalog.json')).status,403);
    assert.equal((await fetch(origin+'/.openai/hosting.json')).status,404);
    assert.equal((await fetch(origin+'/app.js',{method:'POST'})).status,405);
  }finally{if(child.exitCode===null&&child.signalCode===null){const closed=once(child,'exit');child.kill();await closed;}}
});
