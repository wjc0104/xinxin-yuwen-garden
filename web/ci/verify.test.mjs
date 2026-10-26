import test from 'node:test';
import assert from 'node:assert/strict';
import {validateTarget, probeHosted, initialReport, complete, summarize, hostedExitCode} from './verify.mjs';

const host = 'garden.example.com';
const publicDNS = async () => [{address:'93.184.216.34', family:4}];
test('target requires an exact trusted public HTTPS host, root path and public DNS', async () => {
  assert.equal(await validateTarget(`https://${host}/`, host, publicDNS), `https://${host}/`);
  for (const url of ['http://garden.example.com/', 'https://u:p@garden.example.com/',
    'https://garden.example.com:444/', 'https://garden.example.com/?token=secret',
    'https://garden.example.com/#x', 'https://garden.example.com/proxy',
    'https://garden.example.com.evil.test/', 'https://127.0.0.1/', 'https://[::1]/']) {
    await assert.rejects(validateTarget(url, host, publicDNS));
  }
  for (const name of ['', 'localhost', '127.0.0.1', 'internal.local', '*.example.com']) {
    await assert.rejects(validateTarget(`https://${host}/`, name, publicDNS));
  }
  for (const address of ['127.0.0.1', '10.0.0.1', '172.16.0.1', '192.168.0.1',
    '169.254.169.254', '100.64.0.1', '0.0.0.0', '::1', 'fc00::1', 'fe80::1', '::ffff:127.0.0.1']) {
    await assert.rejects(validateTarget(`https://${host}/`, host, async () => [{address}]));
  }
});
test('missing target and production identity are not checked, never pass', async () => {
  assert.deepEqual(await probeHosted({}), {status:'NOT CHECKED', reason:'no_target'});
  const result = await probeHosted({target:`https://${host}/`, allowedHost:host, lookup:publicDNS,
    fetchImpl:async () => new Response('<html>欣语<div id="main"></div><script src="./app.js"></script></html>', {headers:{'content-type':'text/html'}})});
  assert.equal(result.status,'NOT CHECKED');
  assert.equal(result.reason,'production_identity_not_configured');
  assert.equal(hostedExitCode('',{status:'NOT CHECKED'}),0);
  assert.equal(hostedExitCode(`https://${host}/`,{status:'NOT CHECKED'}),1);
  assert.equal(hostedExitCode(`https://${host}/`,{status:'FAIL'}),1);
});
test('redirect, auth, challenge, invalid content and timeout cannot count as hosted success', async () => {
  const options = {target:`https://${host}/`, allowedHost:host, lookup:publicDNS};
  const cases = [
    [new Response(null,{status:302,headers:{location:'https://secret.test/?token=SECRET'}}),'redirect'],
    [new Response('SECRET',{status:401}),'authentication_required'],
    [new Response('SECRET',{status:403}),'access_denied'],
    [new Response('<html>Just a moment... cf-chl-turnstile SECRET</html>',{headers:{'content-type':'text/html'}}),'challenge'],
    [new Response('<html><form>Sign in with ChatGPT SECRET</form></html>',{headers:{'content-type':'text/html'}}),'authentication_required'],
    [new Response('not app SECRET',{headers:{'content-type':'text/html'}}),'unexpected_content'],
    [new Response('SECRET',{status:500}),'http_error']
  ];
  for (const [response, reason] of cases) {
    const result=await probeHosted({...options,fetchImpl:async (_url,init)=>{
      assert.equal(init.redirect,'manual');assert.equal(init.credentials,'omit');return response;
    }});
    assert.notEqual(result.status,'PASS');assert.equal(result.reason,reason);
    assert.doesNotMatch(JSON.stringify(result),/SECRET|secret\.test|<html>/);
  }
  const timeout = await probeHosted({...options,timeout:15,fetchImpl:async (_url,{signal})=>new Promise((_,reject)=>signal.addEventListener('abort',()=>reject(signal.reason),{once:true}))});
  assert.deepEqual(timeout,{status:'FAIL',reason:'timeout'});
  const slowBody=await probeHosted({...options,timeout:15,fetchImpl:async()=>new Response(new ReadableStream({start(){}}),{headers:{'content-type':'text/html'}})});
  assert.deepEqual(slowBody,{status:'FAIL',reason:'timeout'});
  const denied=await probeHosted({...options,target:'https://evil.example/'});
  assert.deepEqual(denied,{status:'FAIL',reason:'invalid_target'});
  const oversized=await probeHosted({...options,fetchImpl:async()=>new Response('x'.repeat(131073),{headers:{'content-type':'text/html'}})});
  assert.equal(oversized.reason,'body_limit');assert.equal(oversized.status,'FAIL');
  const refused=await probeHosted({...options,fetchImpl:async()=>{throw new Error('SECRET upstream URL');}});
  assert.deepEqual(refused,{status:'FAIL',reason:'network_error'});
});
test('five evidence classes and four independent UNKNOWN routes block completion', () => {
  const report=initialReport();
  assert.deepEqual(Object.keys(report.network_matrix),['wifi_proxy_off','wifi_proxy_on','mobile_proxy_off','mobile_proxy_on']);
  assert.ok(Object.values(report.network_matrix).every(cell=>cell.status==='NOT CHECKED'));
  report.code_suite={status:'PASS'};report.browser_fixture={status:'PASS'};report.hosted_access={status:'PASS'};
  assert.equal(complete(report),false);
  report.hosted_real_playback={status:'PASS'};
  assert.equal(complete(report),false);
  assert.match(summarize(report),/NOT CHECKED/);
  assert.match(summarize(report),/未完成/);
});
