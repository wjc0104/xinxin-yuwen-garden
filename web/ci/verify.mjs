import {lookup as dnsLookup} from 'node:dns/promises';
import {isIP} from 'node:net';
import {request} from 'node:https';
import {Readable} from 'node:stream';
import {mkdir, readFile, writeFile, appendFile} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

const artifacts = fileURLToPath(new URL('./artifacts/', import.meta.url));
const state = (status='NOT CHECKED', reason='not_measured') => ({status,reason});
export function initialReport() {
  return {schemaVersion:1, code_suite:state(), browser_fixture:state(), hosted_access:state(),
    hosted_real_playback:state('NOT CHECKED','no_authenticated_original_video_decode'),
    network_matrix:Object.fromEntries(['wifi_proxy_off','wifi_proxy_on','mobile_proxy_off','mobile_proxy_on']
      .map(key=>[key,state('NOT CHECKED','physical_route_not_measured')]))};
}
export function complete(report) {
  return ['code_suite','browser_fixture','hosted_access','hosted_real_playback'].every(key=>report[key]?.status==='PASS') &&
    Object.values(report.network_matrix).length===4 && Object.values(report.network_matrix).every(cell=>cell.status==='PASS');
}
export const hostedExitCode=(target,result)=>target&&result.status!=='PASS'?1:0;
export function summarize(report) {
  const rows=['code_suite','browser_fixture','hosted_access','hosted_real_playback']
    .map(key=>`| ${key} | ${report[key].status} | ${report[key].reason || ''} |`);
  for (const [key,value] of Object.entries(report.network_matrix)) rows.push(`| ${key} | ${value.status} | physical_route_not_measured |`);
  return `## 网页验证证据\n\n| 范围 | 状态 | 边界 |\n|---|---|---|\n${rows.join('\n')}\n\n`+
    `交付验收：${complete(report)?'完成':'未完成'}。本机合成视频不是原站视频；CI 浏览器不是 iPhone Safari，也不是四种真实网络。\n`;
}
function publicAddress(address) {
  if(isIP(address)===4) {
    const [a,b,c]=address.split('.').map(Number);
    return !(a===0||a===10||a===127||a>=224||(a===100&&b>=64&&b<=127)||
      (a===169&&b===254)||(a===172&&b>=16&&b<=31)||(a===192&&(b===168||b===0))||
      (a===198&&(b===18||b===19||(b===51&&c===100)))||(a===203&&b===0&&c===113));
  }
  // Only globally routable unicast; exclude transition/documentation prefixes.
  return isIP(address)===6 && /^[23][0-9a-f]{3}:/i.test(address) &&
    !/^(2001:(0:|db8:)|2002:)/i.test(address);
}
export async function validateTarget(target, allowedHost, lookup=dnsLookup) {
  if(typeof allowedHost!=='string'||allowedHost.length>253||
    !/^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}$/.test(allowedHost)||
    /\.(local|localhost|internal|test|invalid)$/.test(allowedHost)) throw new Error('invalid_target');
  const url=new URL(target);
  if(url.protocol!=='https:'||url.hostname!==allowedHost||url.username||url.password||url.port||
    url.pathname!=='/'||url.search||url.hash) throw new Error('invalid_target');
  const addresses=await lookup(url.hostname,{all:true,verbatim:true});
  if(!addresses.length||!addresses.every(row=>publicAddress(row.address)))throw new Error('invalid_target');
  return url.href;
}
function pinnedFetch(target,{signal},addresses) {
  return new Promise((resolve,reject)=>{
    const first=addresses[0];
    // Pin the validated resolution; a second DNS lookup must not rebind to a LAN address.
    const req=request(target,{signal,method:'GET',family:first.family || isIP(first.address),autoSelectFamily:false,
      lookup:(_host,_options,callback)=>callback(null,first.address,first.family || isIP(first.address)),
      headers:{Accept:'text/html','User-Agent':'Xinyu-CI-access-probe/1'}},res=>{
      try {
        const empty=[204,205,304].includes(res.statusCode);if(empty)res.resume();
        resolve(new Response(empty?null:Readable.toWeb(res),{status:res.statusCode,headers:res.headers}));
      } catch(error) {res.destroy();reject(error);}
    });
    req.on('error',reject);req.end();
  });
}
export async function probeHosted({target,allowedHost,lookup=dnsLookup,fetchImpl,timeout=15000}={}) {
  if(!target)return state('NOT CHECKED','no_target');
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(new Error('timeout')),timeout);
  let response;
  try {
    const work=(async()=>{
      let addresses;
      let url;
      try {url=await validateTarget(target,allowedHost,async(...args)=>(addresses=await lookup(...args)));}
      catch {return state('FAIL','invalid_target');}
      response=await (fetchImpl || ((url,init)=>pinnedFetch(url,init,addresses)))(url,
        {signal:controller.signal,redirect:'manual',credentials:'omit'});
      const httpStatus=response.status;
      if(response.redirected||httpStatus>=300&&httpStatus<400)return {...state('FAIL','redirect'),httpStatus};
      if(httpStatus===401)return {...state('NOT CHECKED','authentication_required'),httpStatus};
      if(httpStatus===403)return {...state('FAIL','access_denied'),httpStatus};
      if(httpStatus!==200)return {...state('FAIL','http_error'),httpStatus};
      if(!response.headers.get('content-type')?.includes('text/html'))return {...state('FAIL','unexpected_content'),httpStatus};
      const reader=response.body.getReader();let bytes=0,text='';const decoder=new TextDecoder();
      try {
        while(true) {
          const {done,value}=await reader.read();if(done)break;
          bytes+=value.byteLength;if(bytes>131072)return {...state('FAIL','body_limit'),httpStatus};
          text+=decoder.decode(value,{stream:true});
        }
      } finally {await reader.cancel().catch(()=>{});reader.releaseLock();}
      if(/cf-chl-|turnstile|just a moment|checking your browser|verify you are human|captcha/i.test(text))return {...state('FAIL','challenge'),httpStatus};
      if(/sign[ -]?in|log[ -]?in|登录|登陆|oauth/i.test(text)&&!text.includes('id="main"'))return {...state('NOT CHECKED','authentication_required'),httpStatus};
      if(!text.includes('欣语')||!text.includes('id="main"')||!text.includes('./app.js'))return {...state('FAIL','unexpected_content'),httpStatus};
      // A 200 shell alone cannot establish official owner identity or private deployment acceptance.
      return {...state('NOT CHECKED','production_identity_not_configured'),httpStatus};
    })();
    return await Promise.race([work,new Promise((_,reject)=>controller.signal.addEventListener('abort',()=>reject(controller.signal.reason),{once:true}))]);
  } catch {return state('FAIL',controller.signal.aborted?'timeout':'network_error');}
  finally {clearTimeout(timer);controller.abort();await response?.body?.cancel().catch(()=>{});}
}
export async function saveResult(name,result) {
  await mkdir(artifacts,{recursive:true});
  await writeFile(resolve(artifacts,`${name}.json`),JSON.stringify(result,null,2)+'\n');
}
async function main(command) {
  if(command==='offline') {
    let pass=true;
    for(const args of [['web/scripts/export-data.mjs'],['--test','web/tests/*.test.mjs','web/deploy/tests/*.test.mjs'],['--test','web/ci/verify.test.mjs']]) {
      if(spawnSync(process.execPath,args,{stdio:'inherit',cwd:fileURLToPath(new URL('../../',import.meta.url))}).status!==0)pass=false;
    }
    await saveResult('code_suite',state(pass?'PASS':'FAIL','export_and_existing_45_plus_ci_unit_tests'));
    process.exitCode=pass?0:1;
  } else if(command==='hosted') {
    const result=await probeHosted({target:process.env.WEB_VERIFY_URL,allowedHost:process.env.WEB_VERIFY_ALLOWED_HOST});
    await saveResult('hosted_access',result);
    // Explicit dispatch is an acceptance request, not permission to silently skip auth.
    process.exitCode=hostedExitCode(process.env.WEB_VERIFY_URL,result);
  } else if(command==='report') {
    const report=initialReport();
    for(const key of ['code_suite','browser_fixture','hosted_access']) {
      try {report[key]=JSON.parse(await readFile(resolve(artifacts,`${key}.json`),'utf8'));}
      catch { /* Missing evidence stays NOT CHECKED. */ }
    }
    report.complete=complete(report);
    await saveResult('report',report);const summary=summarize(report);
    await writeFile(resolve(artifacts,'summary.md'),summary);
    if(process.env.GITHUB_STEP_SUMMARY)await appendFile(process.env.GITHUB_STEP_SUMMARY,summary);
    console.log(summary);
  } else throw new Error('Use offline, hosted or report');
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  main(process.argv[2]).catch(()=>{console.error('CI verification failed; no remote bodies or locators logged.');process.exitCode=1;});
}
