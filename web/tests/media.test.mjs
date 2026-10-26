import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { once } from 'node:events';
const module = await import('../server/media.mjs').catch(() => ({}));
const resource = { id:'curated-test-1', kind:'video', videoCID:222, url:'https://www.bilibili.com/video/BV1rK4y1Y7RD/?p=1', isPaid:false };
const parts = [{page:1,cid:111,part:'Other'}, {page:2,cid:222,part:'Exact'}];
const playback = { quality:16, format:'mp4', timelength:10000, is_preview:false, durl:[{url:'https://test.bilivideo.com/video.mp4?fixture=not-secret'}] };
const json = data => new Response(JSON.stringify({code:0,data}),{headers:{'content-type':'application/json'}});
function setup({items=[resource],pages=parts,source=playback,media,authorize=()=>true,timeoutMs=1000}={}) {
  assert.equal(typeof module.createMediaHandler,'function','media handler must exist');
  const calls=[];
  const fetchImpl=async (url,options)=>{
    calls.push({url:String(url),options});
    if(String(url).includes('/pagelist?'))return json(pages);
    if(String(url).includes('/playurl?'))return json(source);
    return media ? media(url,options) : new Response('0123456789',{headers:{'content-type':'video/mp4','content-length':'10'}});
  };
  return {calls,handler:module.createMediaHandler({resources:items,fetchImpl,authorize,timeoutMs})};
}
const req=(path='',options={})=>new Request('https://private.example/api/video/curated-test-1'+path,options);
const mp4=Uint8Array.from([0,0,0,24,102,116,121,112,105,115,111,109,0,0,0,0,105,115,111,109,109,112,52,50]);
test('octet-stream requires bounded MP4 ftyp probe, including nonzero seek requests',async()=>{
  const {handler,calls}=setup({media:(_,options)=>options.headers.Range==='bytes=0-4095'
    ? new Response(mp4,{status:206,headers:{'content-type':'application/octet-stream','content-range':'bytes 0-23/24','content-length':'24'}})
    : new Response('2345',{status:206,headers:{'content-type':'application/octet-stream','content-range':'bytes 2-5/24','content-length':'4'}})});
  const response=await handler(req('/stream',{headers:{range:'bytes=2-5'}}));
  assert.equal(response.status,206);assert.equal(response.headers.get('content-type'),'video/mp4');assert.equal(await response.text(),'2345');
  assert.ok(calls.some(c=>c.options.headers.Range==='bytes=0-4095'));
  for(const payload of [new TextEncoder().encode('<html>login page</html>'),Uint8Array.from(mp4,(_,i)=>i===4?0:mp4[i]),mp4.slice(0,12)]) {
    const invalid=setup({media:()=>new Response(payload,{headers:{'content-type':'application/octet-stream'}})});
    assert.equal((await invalid.handler(req('/stream'))).status,502);
  }
});
test('octet probe closes both streams on invalid type, mismatched total, redirect or timeout',async()=>{
  for(const mode of ['type','total','redirect','stall']) {
    let closed=0;
    const {handler}=setup({timeoutMs:20,media:(_,options)=>{
      if(options.headers.Range!=='bytes=0-4095')return new Response(new ReadableStream({cancel(){closed++;}}),{status:206,headers:{'content-type':'application/octet-stream','content-range':'bytes 2-5/24'}});
      if(mode==='redirect')return new Response(null,{status:302,headers:{location:'https://evil.test/'}});
      if(mode==='stall')return new Response(new ReadableStream({cancel(){closed++;}}),{headers:{'content-type':'application/octet-stream'}});
      return new Response(mp4,{status:206,headers:{'content-type':mode==='type'?'text/html':'application/octet-stream','content-range':'bytes 0-23/25'}});
    }});
    const response=await handler(req('/stream',{headers:{range:'bytes=2-5'}}));assert.ok(response.status>=400,mode);assert.ok(closed>=1,mode);
  }
});
test('truncated or oversized range bodies fail instead of silently completing',async()=>{
  for(const payload of ['23','234567']){
    const {handler}=setup({media:()=>new Response(payload,{status:206,headers:{'content-type':'video/mp4','content-range':'bytes 2-5/10'}})});
    const response=await handler(req('/stream',{headers:{range:'bytes=2-5'}}));assert.equal(response.status,206);await assert.rejects(response.arrayBuffer());
  }
});
test('slow metadata is bounded by discovery deadline even when chunks keep arriving',async()=>{
  let closed=false;
  const handler=module.createMediaHandler({resources:[resource],authorize:()=>true,timeoutMs:20,fetchImpl:()=>{
    let timer;return new Response(new ReadableStream({start(c){timer=setInterval(()=>c.enqueue(new TextEncoder().encode(' ')),5);},cancel(){clearInterval(timer);closed=true;}}),{headers:{'content-type':'application/json'}});
  }});
  assert.equal((await handler(req())).status,504);assert.equal(closed,true);
});
test('identity is mandatory and cannot be supplied by query/header',async()=>{
  for(const authorize of [undefined,()=>false,()=>({user:'untrusted'}),()=>{throw Error('secret');}]) {
    assert.equal(typeof module.createMediaHandler,'function');
    let calls=0;
    const handler=module.createMediaHandler({resources:[resource],authorize,fetchImpl:()=>{calls++;throw Error();}});
    const response=await handler(req('?authorized=true',{headers:{authorization:'fake'}}));
    assert.equal(response.status,401);assert.equal(calls,0);assert.ok(!(await response.text()).includes('secret'));
  }
});
test('only exact resource IDs, same-origin GET routes, and no URL parameters',async()=>{
  const {handler,calls}=setup();
  for(const path of ['/api/video/missing','/api/video/curated-test-1?url=https://evil.test','/api/video/%63urated-test-1','/api/video/curated-test-1/anything'])assert.ok((await handler(new Request('https://private.example'+path))).status>=400);
  assert.equal((await handler(req('',{method:'POST'}))).status,405);
  assert.equal((await handler(req('',{headers:{origin:'https://evil.test'}}))).status,403);
  assert.equal(calls.length,0);
});
test('metadata chooses known CID despite reordered page and exposes no locator',async()=>{
  const {handler,calls}=setup();const response=await handler(req());const data=await response.json();
  assert.equal(response.status,200);assert.deepEqual(data,{resourceID:resource.id,streamURL:'/api/video/curated-test-1/stream',quality:16,height:360,duration:10,page:2});
  assert.ok(calls[1].url.includes('cid=222'));assert.equal(calls[0].options.redirect,'manual');
  assert.equal(calls[1].options.headers.Referer,'https://www.bilibili.com/video/BV1rK4y1Y7RD/?p=2');
  assert.ok(!JSON.stringify(data).includes('bilivideo'));assert.match(response.headers.get('cache-control'),/no-store/);
});
test('missing CID, ambiguous parts, paid and non-video resources fail closed',async()=>{
  for(const options of [{pages:[parts[0]]},{pages:[parts[1],parts[1]]},{items:[{...resource,videoCID:null}]},{items:[{...resource,isPaid:true}]},{items:[{...resource,kind:'article'}]}]) {
    const {handler,calls}=setup(options);assert.ok((await handler(req())).status>=400);assert.ok(!calls.some(c=>c.url.includes('playurl')));
  }
});
test('preview, multiple segments, absent/invalid MP4, and dangerous CDN locators fail',async()=>{
  const invalid=[{is_preview:true},{is_preview:1},{durl:[]},{durl:[...playback.durl,...playback.durl]},{format:'flv'},{format:null},...['http://test.bilivideo.com/x','https://test.bilivideo.com.evil.test/x','https://evilbilivideo.com/x','https://u:p@test.bilivideo.com/x','https://test.bilivideo.com:444/x','https://127.0.0.1/x','https://test.bilivideo.com./x','https://test.bilivideo.com/x#fragment'].map(url=>({durl:[{url}]}))];
  for(const change of invalid){const {handler}=setup({source:{...playback,...change}});assert.equal((await handler(req())).status,502,JSON.stringify(change));}
});
test('strict single byte ranges reject malformed/multiple/oversized forms before upstream',async()=>{
  for(const range of ['bytes=0-1,3-4','bytes=-0','items=0-1','bytes=10-2','bytes=01-3','bytes=9007199254740992-','bytes= -1','bytes=-','bytes=1-2x']) {
    const {handler,calls}=setup();assert.equal((await handler(req('/stream',{headers:{range}}))).status,416,range);assert.equal(calls.length,0);
  }
});
test('206 forwards matching range with only public headers and original source headers',async()=>{
  const {handler,calls}=setup({media:()=>new Response('2345',{status:206,headers:{'content-type':'video/mp4','content-length':'4','content-range':'bytes 2-5/10','accept-ranges':'bytes','set-cookie':'private','location':'https://secret','access-control-allow-origin':'*'}})});
  const response=await handler(req('/stream',{headers:{range:'bytes=2-5',cookie:'never-forward',authorization:'never-forward'}}));
  assert.equal(response.status,206);assert.equal(await response.text(),'2345');assert.equal(response.headers.get('content-range'),'bytes 2-5/10');
  for(const name of ['set-cookie','location','access-control-allow-origin'])assert.equal(response.headers.get(name),null);
  const headers=calls.at(-1).options.headers;assert.equal(headers.Range,'bytes=2-5');assert.equal(headers.Cookie,undefined);assert.equal(headers.Authorization,undefined);assert.ok(headers['User-Agent']);assert.match(headers.Referer,/\?p=2$/);
});
test('suffix/open ranges work, ignored Range remains 200, invalid 206 fails',async()=>{
  for(const [range,contentRange] of [['bytes=-4','bytes 6-9/10'],['bytes=6-','bytes 6-9/10']]) {
    const {handler}=setup({media:()=>new Response('6789',{status:206,headers:{'content-type':'video/mp4','content-range':contentRange,'content-length':'4'}})});
    const response=await handler(req('/stream',{headers:{range}}));assert.equal(response.status,206);await response.body.cancel();
  }
  const ignored=await setup().handler(req('/stream',{headers:{range:'bytes=2-5'}}));assert.equal(ignored.status,200);await ignored.body.cancel();
  for(const range of [null,'bytes 0-3/10','bytes 2-5/*','bytes 5-2/10']) {
    const {handler}=setup({media:()=>new Response('2345',{status:206,headers:{'content-type':'video/mp4',...(range?{'content-range':range}:{})}})});
    assert.equal((await handler(req('/stream',{headers:{range:'bytes=2-5'}}))).status,502);
  }
});
test('redirects stay within public CDN boundary and stop after three hops; bodies close',async()=>{
  let cancelled=0;
  const redirect=url=>new Response(new ReadableStream({cancel(){cancelled++;}}),{status:302,headers:{location:url}});
  for(const url of ['https://localhost/secret','https://test.bilivideo.com.evil.test/x','http://test.bilivideo.com/x']) {
    const {handler,calls}=setup({media:()=>redirect(url)});assert.equal((await handler(req('/stream'))).status,502);assert.equal(calls.length,3);
  }
  const {handler,calls}=setup({media:()=>redirect('https://test.bilivideo.com/next')});assert.equal((await handler(req('/stream'))).status,502);assert.equal(calls.length,6);assert.equal(cancelled,7);
  let n=0;const allowed=setup({media:()=>++n===1?redirect('https://upos-hz-mirrorakam.akamaized.net/next'):new Response('ok',{headers:{'content-type':'video/mp4'}})});
  const response=await allowed.handler(req('/stream'));assert.equal(response.status,200);assert.equal(await response.text(),'ok');
});
test('upstream errors, wrong media type, JSON limits and metadata redirects do not leak',async()=>{
  for(const status of [403,429,500]){const {handler}=setup({media:()=>new Response('sensitive',{status})});const response=await handler(req('/stream'));assert.ok(response.status>=400);assert.ok(!(await response.text()).includes('sensitive'));}
  assert.equal((await setup({media:()=>new Response('<html>login</html>',{headers:{'content-type':'text/html'}})}).handler(req('/stream'))).status,502);
  for(const upstream of [()=>new Response('x'.repeat(1048577),{headers:{'content-type':'application/json'}}),()=>new Response(null,{status:302,headers:{location:'https://evil.test'}})]) {
    const handler=module.createMediaHandler({resources:[resource],authorize:()=>true,fetchImpl:upstream});assert.equal((await handler(req())).status,502);
  }
});
test('client cancellation aborts upstream and cancels streaming body',async()=>{
  let closed=false,signal;
  const {handler}=setup({media:(_,options)=>{signal=options.signal;return new Response(new ReadableStream({cancel(){closed=true;}}),{headers:{'content-type':'video/mp4'}});}});
  const response=await handler(req('/stream'));await response.body.cancel();assert.equal(closed,true);assert.equal(signal.aborted,true);
});
test('downstream backpressure is not counted as an upstream read timeout',async()=>{
  const {handler}=setup({timeoutMs:20,media:()=>new Response(new ReadableStream({start(controller){controller.enqueue(new TextEncoder().encode('abc'));controller.close();}}),{headers:{'content-type':'video/mp4','content-length':'3'}})});
  const response=await handler(req('/stream')),reader=response.body.getReader();
  assert.equal(new TextDecoder().decode((await reader.read()).value),'abc');
  await new Promise(resolve=>setTimeout(resolve,45));
  assert.equal((await reader.read()).done,true);
});
test('request abort and idle timeout close a pending upstream read',async()=>{
  for(const abort of [true,false]) {
    let closed=false;const controller=new AbortController();
    const {handler}=setup({timeoutMs:30,media:()=>new Response(new ReadableStream({cancel(){closed=true;}}),{headers:{'content-type':'video/mp4'}})});
    const response=await handler(req('/stream',{signal:controller.signal}));const reading=response.body.getReader().read();
    if(abort)controller.abort();await assert.rejects(reading);assert.equal(closed,true);
  }
});
test('metadata fetch timeout returns bounded sanitized failure',async()=>{
  const handler=module.createMediaHandler({resources:[resource],authorize:()=>true,timeoutMs:20,fetchImpl:(_,options)=>new Promise((_,reject)=>options.signal.addEventListener('abort',()=>reject(Error('secret'))))});
  const response=await handler(req());assert.equal(response.status,504);assert.ok(!(await response.text()).includes('secret'));
});
test('original library supports all 627 videos without a two-lesson special case',async()=>{
  const library=JSON.parse(await readFile(new URL('../../App/Resources/library.json',import.meta.url),'utf8'));
  const videos=library.filter(r=>r.kind==='video');assert.equal(videos.length,627);
  for(const item of videos){const {handler}=setup({items:[item],pages:[{page:Number(new URL(item.url).searchParams.get('p')||1),cid:item.videoCID,part:'Exact'}]});assert.equal((await handler(new Request('https://private.example/api/video/'+item.id))).status,200,item.id);}
});
test('isolated loopback HTTP exercises authorized metadata and byte stream, never production bypass',async()=>{
  const {handler}=setup({authorize:request=>request.headers.get('x-isolated-test')==='yes'});
  const server=createServer(async (incoming,out)=>{
    const request=new Request('http://127.0.0.1'+incoming.url,{headers:incoming.headers});
    const response=await handler(request);out.writeHead(response.status,Object.fromEntries(response.headers));out.end(Buffer.from(await response.arrayBuffer()));
  });server.listen(0,'127.0.0.1');await once(server,'listening');
  try {const origin=`http://127.0.0.1:${server.address().port}`;assert.equal((await fetch(origin+'/api/video/'+resource.id)).status,401);const response=await fetch(origin+'/api/video/'+resource.id+'/stream',{headers:{'x-isolated-test':'yes'}});assert.equal(response.status,200);assert.equal(await response.text(),'0123456789');}
  finally {await new Promise(resolve=>server.close(resolve));}
});
