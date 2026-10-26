import test from 'node:test';
import assert from 'node:assert/strict';

// A transaction-lifecycle model, not a substitute for Safari/real IndexedDB QA.
test('storage commits only on transaction completion; conflicts and aborts preserve prior records',async()=>{
  let record, abortCommit=false, pending;
  const db={close(){},transaction(_store,mode){
    let aborted=false, staged;
    const tx={abort(){aborted=true;queueMicrotask(()=>tx.onabort());},objectStore(){return {
      get(){const req={};queueMicrotask(()=>{req.result=structuredClone(record);req.onsuccess?.();
        if(aborted)return;
        if(mode==='readonly')queueMicrotask(()=>tx.oncomplete());
        else pending=()=>{if(abortCommit){tx.abort();return;}record=staged;tx.oncomplete();};
      });return req;},
      put(value){staged=structuredClone(value);}
    };}};return tx;
  }};
  globalThis.indexedDB={open(){const req={};queueMicrotask(()=>{req.result=db;req.onsuccess();});return req;}};
  try {
    const {loadState,saveState}=await import(`../dist/storage.js?test=${Date.now()}`);
    assert.deepEqual(await loadState(),{revision:0,state:null});
    let resolved=false;const first=saveState({notes:['one']},0).then(v=>{resolved=true;return v;});
    await new Promise(setImmediate);assert.equal(resolved,false);assert.equal(record,undefined);
    pending();assert.equal(await first,1);assert.deepEqual(await loadState(),{revision:1,state:{notes:['one']}});
    await assert.rejects(saveState({notes:['stale']},0),/另一页面/);assert.deepEqual(record.state,{notes:['one']});
    abortCommit=true;const second=saveState({notes:['two']},1);const rejected=assert.rejects(second,/本机保存失败/);
    await new Promise(setImmediate);pending();await rejected;assert.equal(record.revision,1);assert.deepEqual(record.state,{notes:['one']});
  }finally{delete globalThis.indexedDB;}
});
test('storage denial is explicit, not an empty successful load',async()=>{
  const {loadState}=await import(`../dist/storage.js?denied=${Date.now()}`);
  await assert.rejects(loadState(),/不允许本机存储/);
});
