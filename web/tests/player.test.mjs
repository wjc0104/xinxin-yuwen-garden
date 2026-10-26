import test from 'node:test';
import assert from 'node:assert/strict';
const module=await import('../dist/player.js').catch(()=>({}));
class Video extends EventTarget {
  currentTime=0;duration=300;readyState=0;playbackRate=1;src='';paused=true;loads=0;
  pause(){this.paused=true;}load(){this.loads++;}removeAttribute(name){if(name==='src')this.src='';}
}
const metadata=id=>Response.json({resourceID:id,streamURL:`/api/video/${id}/stream`,height:360});
test('player uses only same-origin metadata, six rates, real time/seek and cleanup',async()=>{
  assert.equal(typeof module.createPlayerSession,'function');const video=new Video(),messages=[];
  const session=module.createPlayerSession({video,resourceID:'one',fetchImpl:async()=>metadata('one'),onStatus:(...m)=>messages.push(m)});
  await session.retry();assert.equal(video.src,'/api/video/one/stream');assert.equal(session.currentTime(),null);
  video.readyState=1;video.dispatchEvent(new Event('loadedmetadata'));video.currentTime=72.8;
  assert.equal(session.currentTime(),72);assert.equal(session.seek(100),true);assert.equal(video.currentTime,100);
  assert.deepEqual(module.PLAYBACK_RATES,[0.5,0.75,1,1.25,1.5,2]);session.setRate(0.5);assert.equal(video.playbackRate,0.5);session.setRate(1.5);assert.equal(video.playbackRate,1.5);
  session.dispose();assert.equal(video.src,'');assert.ok(video.paused);assert.equal(session.currentTime(),null);
  assert.ok(messages.some(m=>m[0].includes('360P')));
});
test('navigation generation fences late responses; retry retains position and rejects remote locators',async()=>{
  const video=new Video();let resolve,signal;
  const session=module.createPlayerSession({video,resourceID:'one',fetchImpl:(_,options)=>{signal=options.signal;return new Promise(r=>{resolve=r;});}});
  const pending=session.retry();session.dispose();resolve(metadata('one'));await pending;
  assert.equal(signal.aborted,true);assert.equal(video.src,'');
  const other=new Video();let bad=false;
  const active=module.createPlayerSession({video:other,resourceID:'two',fetchImpl:async()=>bad?Response.json({resourceID:'two',streamURL:'https://evil.test/movie'}):metadata('two')});
  await active.retry();other.readyState=1;other.dispatchEvent(new Event('loadedmetadata'));other.currentTime=93;
  await active.retry();other.currentTime=0;other.dispatchEvent(new Event('loadedmetadata'));assert.equal(other.currentTime,93);
  bad=true;await active.retry();assert.equal(other.src,'');active.dispose();
});
