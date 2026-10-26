const DB_NAME = `xinyu-web:${new URL('.',import.meta.url).pathname}`;
let dbPromise;
function database() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve,reject) => {
    if (!globalThis.indexedDB) { reject(new Error('浏览器不允许本机存储')); return; }
    const request = indexedDB.open(DB_NAME,1);
    let blocked = false;
    request.onupgradeneeded = () => request.result.createObjectStore('records');
    request.onerror = () => reject(request.error);
    request.onblocked = () => { blocked = true; reject(new Error('存储被其他页面占用，请关闭旧页面后重试')); };
    request.onsuccess = () => {
      const db = request.result;
      if (blocked) { db.close(); return; }
      db.onversionchange = () => { db.close(); dbPromise = null; };
      resolve(db);
    };
  }).catch(error => { dbPromise = null; throw error; });
  return dbPromise;
}
export async function loadState() {
  const db = await database();
  return new Promise((resolve,reject) => {
    const tx = db.transaction('records','readonly');
    const req = tx.objectStore('records').get('state');
    tx.oncomplete = () => resolve(req.result || {revision:0,state:null});
    tx.onabort = tx.onerror = () => reject(tx.error || new Error('读取本机数据失败'));
  });
}
export async function saveState(state, expectedRevision) {
  const db = await database();
  return new Promise((resolve,reject) => {
    const tx = db.transaction('records','readwrite'), store = tx.objectStore('records');
    let conflict = false;
    const req = store.get('state');
    req.onsuccess = () => {
      if ((req.result?.revision || 0) !== expectedRevision) { conflict = true; tx.abort(); return; }
      store.put({revision:expectedRevision+1,state},'state');
    };
    // Only transaction completion confirms durable success; request success alone does not.
    tx.oncomplete = () => resolve(expectedRevision+1);
    tx.onabort = tx.onerror = () => reject(new Error(conflict ? '另一页面已修改记录。本次未保存，请先复制正在编辑的文字，再刷新页面。' : '本机保存失败，可能空间不足或存储被禁用。本次未保存，请复制文字后重试。'));
  });
}
