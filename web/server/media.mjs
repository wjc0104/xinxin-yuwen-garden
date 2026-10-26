// Fetch-only adapter. Production must inject a verified platform identity check;
// resources must come from the repository's original library, never a request.
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
const heights = {16:360,32:480,64:720,74:720,80:1080,112:1080,116:1080,120:2160};
const privateHeaders = {'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'};
class MediaError extends Error { constructor(status,message){super(message);this.status=status;} }
const fail = (message='原站没有返回可播放的完整视频，请稍后重试。',status=502) => {throw new MediaError(status,message);};
const positive = n => Number.isSafeInteger(n) && n>0;
function sourceURL(raw) {
  if(typeof raw!=='string'||raw.length>8192||/[\s\\#]/.test(raw))fail();
  let url;try{url=new URL(raw);}catch{fail();}
  if(url.protocol!=='https:'||url.username||url.password||url.port||!((url.hostname==='bilivideo.com'||url.hostname.endsWith('.bilivideo.com'))||url.hostname==='upos-hz-mirrorakam.akamaized.net'))fail();
  return url;
}
function reference(item) {
  if(item.kind!=='video'||item.isPaid===true||!positive(item.videoCID))fail('此资料没有可验证的公开视频分集。',404);
  let url;try{url=new URL(item.url);}catch{fail();}
  const match=url.pathname.match(/^\/video\/(BV[A-Za-z0-9]{10})\/?$/),p=url.searchParams.getAll('p');
  if(url.protocol!=='https:'||!['www.bilibili.com','bilibili.com'].includes(url.hostname)||url.port||url.username||url.password||!match||p.length>1)fail();
  const page=Number(p[0]||1);if(!positive(page)||page>5000)fail();
  return {bvid:match[1],page,cid:item.videoCID};
}
function byteRange(raw) {
  if(raw===null)return null;
  const m=/^bytes=(0|[1-9]\d*)?-(0|[1-9]\d*)?$/.exec(raw);
  if(!m||(!m[1]&&!m[2]))fail('仅支持单段有效的字节范围。',416);
  const start=m[1]===undefined?null:Number(m[1]),end=m[2]===undefined?null:Number(m[2]);
  if([start,end].some(v=>v!==null&&!Number.isSafeInteger(v))||(start===null&&end===0)||(start!==null&&end!==null&&start>end))fail('字节范围无效。',416);
  return {raw,start,end};
}
function contentRange(raw,range) {
  const m=/^bytes (0|[1-9]\d*)-(0|[1-9]\d*)\/([1-9]\d*)$/.exec(raw||'');
  if(!m||!range)fail();
  const [start,end,total]=m.slice(1).map(Number);
  if(![start,end,total].every(Number.isSafeInteger)||end<start||end>=total)fail();
  const wantStart=range.start===null?Math.max(0,total-range.end):range.start;
  const wantEnd=range.start===null||range.end===null?total-1:Math.min(range.end,total-1);
  if(start!==wantStart||end!==wantEnd)fail();
  return {length:end-start+1};
}
export function createMediaHandler({resources=[],fetchImpl=globalThis.fetch,authorize,timeoutMs=20000}={}) {
  // Copy only the fields needed for discovery; do not retain user-owned state.
  const whitelist=new Map();
  for(const item of resources) {
    if(typeof item.id!=='string'||!/^[\w-]{1,160}$/.test(item.id)||whitelist.has(item.id))throw new Error('Invalid media whitelist');
    whitelist.set(item.id,{id:item.id,kind:item.kind,url:item.url,videoCID:item.videoCID,isPaid:item.isPaid});
  }
  if(!positive(timeoutMs))throw new Error('Invalid timeout');
  return async request=>{
    let authorized=false;try{authorized=typeof authorize==='function'&&(await authorize(request))===true;}catch{}
    const errorResponse=(status,message)=>Response.json({error:message},{status,headers:privateHeaders});
    if(!authorized)return errorResponse(401,'请先登录已授权的所有者账号。');
    const url=new URL(request.url);
    if(request.method!=='GET')return errorResponse(405,'仅支持读取视频。');
    if((request.headers.has('origin')&&request.headers.get('origin')!==url.origin)||request.headers.get('sec-fetch-site')==='cross-site')return errorResponse(403,'仅允许同源访问。');
    const match=/^\/api\/video\/([\w-]{1,160})(\/stream)?$/.exec(url.pathname);
    if(!match||url.search||!whitelist.has(match[1]))return errorResponse(404,'未收录这份视频。');
    const aborter=new AbortController();let timer,discoveryTimer,reader,probeReader,streamController,finished=false,timedOut=false;
    const cleanup=()=>{clearTimeout(timer);clearTimeout(discoveryTimer);request.signal.removeEventListener('abort',onAbort);};
    const stop=(error)=>{
      if(finished)return;finished=true;cleanup();aborter.abort();
      if(reader)void reader.cancel().catch(()=>{});
      if(probeReader)void probeReader.cancel().catch(()=>{});
      if(streamController)try{streamController.error(error);}catch{}
    };
    const onAbort=()=>stop(new MediaError(499,'播放请求已取消。'));
    const arm=()=>{clearTimeout(timer);timer=setTimeout(()=>{timedOut=true;stop(new MediaError(504,'原站响应超时，请重试。'));},timeoutMs);};
    discoveryTimer=setTimeout(()=>{timedOut=true;stop(new MediaError(504,'原站响应超时，请重试。'));},timeoutMs*3);
    request.signal.addEventListener('abort',onAbort,{once:true});
    if(request.signal.aborted)onAbort();
    const headers=referer=>({'User-Agent':UA,Referer:referer,'Accept-Encoding':'identity'});
    async function fetchChecked(target,extraHeaders) {
      if(aborter.signal.aborted)fail('播放请求已取消。',499);
      arm();
      try{return await fetchImpl(String(target),{method:'GET',headers:extraHeaders,redirect:'manual',credentials:'omit',cache:'no-store',signal:aborter.signal});}
      finally{clearTimeout(timer);}
    }
    async function jsonRequest(target,referer) {
      const response=await fetchChecked(target,headers(referer));
      try {
        if(response.status!==200||!/^application\/json(?:;|$)/i.test(response.headers.get('content-type')||'')||!response.body)fail();
        if(Number(response.headers.get('content-length'))>1048576)fail();
        reader=response.body.getReader();const chunks=[];let length=0;
        while(true){arm();const {done,value}=await reader.read();clearTimeout(timer);if(done)break;length+=value.byteLength;if(length>1048576)fail();chunks.push(value);}
        if(aborter.signal.aborted)fail();
        const joined=new Uint8Array(length);let offset=0;for(const chunk of chunks){joined.set(chunk,offset);offset+=chunk.byteLength;}
        const envelope=JSON.parse(new TextDecoder().decode(joined));
        if(envelope.code!==0)fail('原站视频服务暂不可用或限流，请稍后重试。');
        return envelope.data;
      } finally {if(reader){await reader.cancel().catch(()=>{});reader=null;}else await response.body?.cancel().catch(()=>{});}
    }
    async function cdnRequest(locator,referer,rangeHeader) {
      for(let hop=0;hop<=3;hop++) {
        const response=await fetchChecked(locator,{...headers(referer),...(rangeHeader?{Range:rangeHeader}:{})});
        if(![301,302,303,307,308].includes(response.status))return {response,locator};
        await response.body?.cancel().catch(()=>{});
        if(hop===3||!response.headers.get('location'))fail();
        locator=sourceURL(new URL(response.headers.get('location'),locator).href);
      }
    }
    async function verifyMP4(locator,referer,total) {
      // Some public CDN responses use octet-stream. Verify a bounded ISO-BMFF
      // ftyp box at byte zero, never reinterpret arbitrary binary as a movie.
      const {response}=await cdnRequest(locator,referer,'bytes=0-4095');
      try {
        if(response.body)probeReader=response.body.getReader();
        if(!probeReader||![200,206].includes(response.status)||! /^(?:video\/mp4|application\/octet-stream)(?:;|$)/i.test(response.headers.get('content-type')||'')||!['identity',null].includes(response.headers.get('content-encoding')))fail();
        if(response.status===206){
          contentRange(response.headers.get('content-range'),{start:0,end:4095});
          if(total&&response.headers.get('content-range').split('/')[1]!==total)fail();
        } else if(response.headers.has('content-range'))fail();
        const prefix=new Uint8Array(4096);let length=0,boxSize;
        while(length<4096) {
          arm();const {done,value}=await probeReader.read();clearTimeout(timer);if(aborter.signal.aborted)fail();if(done)break;
          const take=Math.min(value.byteLength,4096-length);prefix.set(value.subarray(0,take),length);length+=take;
          if(length>=8){boxSize=new DataView(prefix.buffer).getUint32(0);if(boxSize<16||boxSize>4096||boxSize%4||new TextDecoder().decode(prefix.subarray(4,8))!=='ftyp')fail();if(length>=boxSize)break;}
        }
        if(!boxSize||length<boxSize)fail();
        const brands=[];for(let i=8;i<boxSize;i+=4)if(i!==12)brands.push(new TextDecoder().decode(prefix.subarray(i,i+4)));
        if(!brands.some(b=>['isom','iso2','iso3','iso4','iso5','iso6','mp41','mp42','avc1','M4V '].includes(b)))fail();
      } finally {await probeReader?.cancel().catch(()=>{});probeReader=null;}
    }
    try {
      const range=byteRange(request.headers.get('range')),ref=reference(whitelist.get(match[1]));
      let referer=`https://www.bilibili.com/video/${ref.bvid}/?p=${ref.page}`;
      const pages=await jsonRequest(`https://api.bilibili.com/x/player/pagelist?bvid=${ref.bvid}`,referer);
      if(!Array.isArray(pages)||!pages.length||pages.length>5000||pages.some(p=>!positive(p.cid)||!positive(p.page)||p.page>5000)||new Set(pages.map(p=>p.cid)).size!==pages.length||new Set(pages.map(p=>p.page)).size!==pages.length)fail();
      const part=pages.find(p=>p.cid===ref.cid);if(!part)fail('原分集已变更，未改播其他视频。请稍后刷新资料。');
      referer=`https://www.bilibili.com/video/${ref.bvid}/?p=${part.page}`;
      const source=await jsonRequest(`https://api.bilibili.com/x/player/playurl?bvid=${ref.bvid}&cid=${ref.cid}&qn=80&fnval=1&fnver=0&fourk=0`,referer);
      if(!source||![undefined,false,0].includes(source.is_preview)||typeof source.format!=='string'||!/^mp4(?:$|\b)/.test(source.format)||!Array.isArray(source.durl)||source.durl.length!==1)fail();
      if(source.durl[0].length!==undefined&&(!Number.isFinite(source.durl[0].length)||source.durl[0].length<=0||!Number.isFinite(source.timelength)||Math.abs(source.durl[0].length-source.timelength)>1000))fail();
      let locator=sourceURL(source.durl[0].url);
      if(!match[2]) {
        cleanup();finished=true;
        return Response.json({resourceID:match[1],streamURL:`/api/video/${match[1]}/stream`,quality:Number.isSafeInteger(source.quality)?source.quality:null,height:heights[source.quality]||null,duration:typeof source.timelength==='number'&&Number.isFinite(source.timelength)&&source.timelength>0?source.timelength/1000:null,page:part.page},{headers:privateHeaders});
      }
      const media=await cdnRequest(locator,referer,range?.raw),upstream=media.response;
      // Take ownership before validation so every rejected response is closed.
      if(upstream.body)reader=upstream.body.getReader();
      if(upstream.status===429)fail('原站请求较多，请稍后重试。',503);
      const mime=upstream.headers.get('content-type')||'';
      if(![200,206].includes(upstream.status)||!reader||!/^(?:video\/mp4|application\/octet-stream)(?:;|$)/i.test(mime)||!['identity',null].includes(upstream.headers.get('content-encoding')))fail();
      const outgoing=new Headers({...privateHeaders,'Content-Type':'video/mp4'});
      const length=upstream.headers.get('content-length');
      let expectedLength=length===null?null:Number(length),transferred=0;
      if(length!==null&&(!/^(0|[1-9]\d*)$/.test(length)||!Number.isSafeInteger(Number(length))))fail();
      if(upstream.status===206) {
        const validated=contentRange(upstream.headers.get('content-range'),range);
        expectedLength=validated.length;
        if(length!==null&&Number(length)!==validated.length)fail();
        outgoing.set('Content-Range',upstream.headers.get('content-range'));
      } else if(upstream.headers.has('content-range'))fail();
      if(/^application\/octet-stream(?:;|$)/i.test(mime))await verifyMP4(media.locator,referer,upstream.status===206?upstream.headers.get('content-range').split('/')[1]:length);
      if(aborter.signal.aborted)fail('播放请求已取消。',499);
      clearTimeout(discoveryTimer);
      if(length!==null)outgoing.set('Content-Length',length);
      if(upstream.headers.get('accept-ranges')==='bytes')outgoing.set('Accept-Ranges','bytes');
      const body=new ReadableStream({
        start(controller){streamController=controller;},
        async pull(controller){
          // Only a pending upstream read is timed. With highWaterMark:0 there
          // may be no next pull while the downstream player is paused/backpressured.
          try{arm();const result=await reader.read();clearTimeout(timer);if(finished)return;if(result.done){if(expectedLength!==null&&transferred!==expectedLength)fail();finished=true;cleanup();controller.close();}else{transferred+=result.value.byteLength;if(expectedLength!==null&&transferred>expectedLength)fail();controller.enqueue(result.value);}}
          catch{stop(new MediaError(502,'视频传输中断，请重试。'));}
        },
        async cancel(){finished=true;cleanup();aborter.abort();await reader.cancel().catch(()=>{});}
      },{highWaterMark:0});
      return new Response(body,{status:upstream.status,headers:outgoing});
    } catch(error) {
      stop(error);cleanup();
      return errorResponse(timedOut?504:error instanceof MediaError?error.status:502,timedOut?'原站响应超时，请重试。':error instanceof MediaError?error.message:'视频暂不可用，请稍后重试。');
    }
  };
}
