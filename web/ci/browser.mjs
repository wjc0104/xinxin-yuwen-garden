import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile, mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';
import {ASSETS} from '../deploy/prepare-sites.mjs';
import {saveResult} from './verify.mjs';

const output=fileURLToPath(new URL('./artifacts/',import.meta.url));
const data=JSON.parse(await readFile(new URL('../dist/data/catalogue.json',import.meta.url)));
const reading=data.resources.find(row=>row.lessonID==='7u-01'&&row.body);
const videoResource=data.resources.find(row=>row.lessonID==='7u-01'&&row.kind==='video');
let stage='generate_authored_media', server, currentPage;
const browsers=[];const checks=[];
try {
  await mkdir(output,{recursive:true});
  const author=await chromium.launch();browsers.push(author);
  const authorPage=await author.newPage();
  // Author an eight-second animation from scratch; no downloaded third-party media.
  const videoBytes=Buffer.from(await authorPage.evaluate(async()=>{
    const canvas=document.createElement('canvas');canvas.width=320;canvas.height=180;
    const context=canvas.getContext('2d'),stream=canvas.captureStream(12),chunks=[];
    const recorder=new MediaRecorder(stream,{mimeType:'video/webm;codecs=vp8'});
    const finished=new Promise(resolve=>{recorder.onstop=resolve;});
    recorder.ondataavailable=event=>chunks.push(event.data);
    let frame=0;const draw=()=>{
      context.fillStyle='#f7e3b2';context.fillRect(0,0,320,180);
      context.fillStyle='#7f3047';context.fillRect((frame++*8)%280,70,40,40);
      context.font='14px sans-serif';context.fillText('SYNTHETIC LOCAL FIXTURE',12,30);
      context.fillText(String(frame),12,150);
    };
    draw();const interval=setInterval(draw,80);recorder.start();
    await new Promise(resolve=>setTimeout(resolve,8000));recorder.stop();await finished;
    clearInterval(interval);stream.getTracks().forEach(track=>track.stop());
    return Array.from(new Uint8Array(await new Blob(chunks,{type:'video/webm'}).arrayBuffer()));
  }));
  await author.close();assert.ok(videoBytes.length>1000);
  const assets=new Map(await Promise.all(Object.keys(ASSETS).map(async path=>[
    '/'+path,{body:await readFile(new URL('../dist/'+path,import.meta.url)),type:ASSETS[path]}])));
  server=createServer((req,res)=>{
    if(!['GET','HEAD'].includes(req.method)){res.writeHead(405).end();return;}
    const path=req.url;
    if(path===`/api/video/${videoResource.id}`) {
      res.writeHead(200,{'content-type':'application/json','cache-control':'no-store'});
      res.end(JSON.stringify({resourceID:videoResource.id,streamURL:path+'/stream',height:180}));return;
    }
    if(path===`/api/video/${videoResource.id}/stream`) {
      let start=0,end=videoBytes.length-1;
      if(req.headers.range) {
        const match=/^bytes=(\d+)-(\d*)$/.exec(req.headers.range);
        if(!match){res.writeHead(416).end();return;}
        start=Number(match[1]);end=match[2]?Math.min(Number(match[2]),end):end;
        if(start>end){res.writeHead(416).end();return;}
      }
      res.writeHead(req.headers.range?206:200,{'content-type':'video/webm','accept-ranges':'bytes',
        'content-length':end-start+1,...(req.headers.range?{'content-range':`bytes ${start}-${end}/${videoBytes.length}`}:{})});
      res.end(req.method==='HEAD'?undefined:videoBytes.subarray(start,end+1));return;
    }
    const asset=assets.get(path==='/'?'/index.html':path);
    if(!asset){res.writeHead(404).end();return;}
    res.writeHead(200,{'content-type':asset.type,'cache-control':'no-store'});
    res.end(req.method==='HEAD'?undefined:asset.body);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const origin=`http://127.0.0.1:${server.address().port}`;
  for(const [name,engine] of [['chromium',chromium]]) {
    stage=name+'_navigation';
    const browser=await engine.launch();browsers.push(browser);
    const context=await browser.newContext({viewport:{width:390,height:844},serviceWorkers:'block'});
    let externalRequests=0;
    await context.route('**/*',route=>{
      if(new URL(route.request().url()).origin===origin)return route.continue();
      externalRequests++;return route.abort();
    });
    const page=await context.newPage();currentPage=page;page.setDefaultTimeout(15000);
    await page.goto(origin);await page.getByRole('link',{name:'开始选课 →',exact:true}).click();
    await page.getByRole('heading',{name:'课程',exact:true}).waitFor();
    const search=page.getByRole('searchbox');await search.fill('春');
    assert.equal(await page.locator('.results .list-row strong').first().innerText(),'春');
    assert.equal(await page.locator('.results .match').first().innerText(),'课名完全匹配');
    await search.fill('毛泽东');await page.locator('.results .list-row').first().waitFor();
    const authors=await page.locator('.results .list-row small').allTextContents();
    assert.ok(authors.length&&authors.every(text=>text.includes('毛泽东')));
    await page.locator('[data-tab="schedule"]').click();await page.getByRole('heading',{name:'我的课表',exact:true}).waitFor();
    await page.locator('[data-tab="me"]').click();await page.getByRole('heading',{name:'我的',exact:true}).waitFor();
    stage=name+'_selection_and_indexeddb';
    await page.goto(`${origin}/#resource/${reading.id}`);
    const article=page.locator('article.reading-body');await article.waitFor();
    const quote=await article.evaluate(article=>{
      const node=article.firstChild,range=document.createRange();range.setStart(node,0);range.setEnd(node,8);
      const selection=getSelection();selection.removeAllRanges();selection.addRange(range);return selection.toString();
    });
    assert.equal(quote.length,8);
    await page.getByRole('button',{name:'取用所选文字',exact:true}).click();
    await page.getByRole('textbox',{name:'笔记内容',exact:true}).fill('CI authored local note');
    await page.getByRole('button',{name:'保存到本机',exact:true}).click();
    await page.locator('.note-card').filter({hasText:'CI authored local note'}).waitFor();
    await page.reload();
    await page.locator('article mark').filter({hasText:quote}).waitFor();
    assert.equal(await page.locator('.note-card .note-text').innerText(),'CI authored local note');
    stage=name+'_decoded_video_and_time_note';
    await page.goto(`${origin}/#resource/${videoResource.id}`);
    stage=name+'_media_ready';
    await page.waitForFunction(()=>document.querySelector('video')?.readyState>=2);
    const video=page.locator('video');
    assert.deepEqual(await video.evaluate(v=>[v.controls,v.playsInline]),[true,true]);
    stage=name+'_frame_decode';
    const frames=await video.evaluate(async v=>{
      let frames=0;const observed=new Promise(resolve=>{
        const next=()=>{frames++;if(frames>=3)resolve(frames);else v.requestVideoFrameCallback(next);};
        v.requestVideoFrameCallback(next);
      });
      await v.play();return Promise.race([observed,new Promise((_,reject)=>setTimeout(()=>reject(new Error('no decoded frames')),5000))]);
    });
    assert.ok(frames>=3);
    stage=name+'_speed_and_time_note';
    await page.getByRole('combobox',{name:'播放速度',exact:true}).selectOption('1.5');
    assert.equal(await video.evaluate(v=>v.playbackRate),1.5);
    await video.evaluate(v=>{v.pause();v.currentTime=3;});
    await page.waitForFunction(()=>{const v=document.querySelector('video');return !v.seeking&&v.currentTime>=3;});
    await page.getByRole('button',{name:'取用当前播放时间',exact:true}).click();
    assert.equal(await page.getByRole('textbox',{name:'时间点（可取用当前时间，也可手动填写）',exact:true}).inputValue(),'0:03');
    await page.getByRole('textbox',{name:'笔记内容',exact:true}).fill('CI synthetic video time note');
    await page.getByRole('button',{name:'保存到本机',exact:true}).click();
    await page.getByRole('button',{name:'跳转到 0:03',exact:true}).waitFor();
    await page.waitForFunction(()=>document.querySelector('video')?.readyState>=2);
    await page.getByRole('button',{name:'跳转到 0:03',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('video')?.currentTime>=3);
    await page.reload();await page.locator('.note-card').filter({hasText:'CI synthetic video time note'}).waitFor();
    assert.equal(externalRequests,0);
    await page.screenshot({path:output+`/${name}-local-fixture.png`,fullPage:true});
    checks.push({browser:name,status:'PASS',decodedFrames:frames,navigation:true,exactSearch:true,
      selectionAndReload:true,nativeControlsPresent:true,speedAndTimeNote:true});
    await context.close();await browser.close();currentPage=null;
  }
  await saveResult('browser_fixture',{status:'PASS',reason:'synthetic_loopback_only',checks,
    notMeasured:['production_auth','original_video','webkit','physical_safari','native_touch_controls','service_worker_browser_offline']});
} catch {
  const media=currentPage&&!currentPage.isClosed()?await currentPage.locator('video').evaluateAll(nodes=>nodes.map(v=>({
    readyState:v.readyState,networkState:v.networkState,errorCode:v.error?.code || null,
    finiteDuration:Number.isFinite(v.duration),canPlayMP4:v.canPlayType('video/mp4;codecs="avc1.42001E"')
  }))).catch(()=>[]):[];
  if(currentPage&&!currentPage.isClosed()&&/^http:\/\/127\.0\.0\.1:/.test(currentPage.url())) {
    await currentPage.screenshot({path:output+'/failed-local-fixture.png',fullPage:true}).catch(()=>{});
  }
  await saveResult('browser_fixture',{status:'FAIL',reason:'local_fixture_check_failed',stage,checks,media});
  console.error(`Local synthetic fixture failed at ${stage}; see sanitized evidence.`);process.exitCode=1;
} finally {
  for(const browser of browsers)await browser.close().catch(()=>{});
  if(server)await new Promise(resolve=>{server.close(resolve);server.closeAllConnections();});
}
