import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { safeURL } from '../dist/core.js';
const hash = value => createHash('sha256').update(value).digest('hex').slice(0,16);
const text = value => typeof value === 'string' ? value : '';
export function exportData(catalog, library) {
  const books = catalog.books.map(b => ({id:b.id,title:b.title,edition:text(b.edition),verification:text(b.verification),source:safeURL(b.source)||'',units:b.units.map(u=>({id:u.id,title:u.title}))}));
  const lessons = catalog.books.flatMap(b => b.units.flatMap(u => u.lessons.map(l => ({id:l.id,number:l.number,title:l.title,author:text(l.author),focus:l.focus.filter(x=>typeof x==='string'),bookID:b.id,unitID:u.id}))));
  const ids = new Set(lessons.map(l=>l.id));
  if (lessons.length !== 198 || ids.size !== 198) throw new Error('课程数量或稳定 ID 校验失败');
  const resources = library.filter(r=>ids.has(r.lessonID)).map(r=>({
    id:r.id,lessonID:r.lessonID,title:r.title,kind:r.kind,
    body:['欣语备课提纲','欣语原创练习'].includes(r.source) ? text(r.body) : '',
    url:safeURL(r.url)||'',source:text(r.source),isPaid:r.isPaid===true,category:text(r.category),
    durationSeconds:Number.isFinite(r.durationSeconds)?r.durationSeconds:0,checkedAt:text(r.checkedAt),summary:text(r.summary)
  }));
  if (new Set(resources.map(r=>r.id)).size !== resources.length) throw new Error('资料 ID 重复');
  const payload = {schemaVersion:1,checkedAt:text(catalog.checkedAt),books,lessons,resources};
  return {...payload,dataVersion:hash(JSON.stringify(payload))};
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = new URL('../../',import.meta.url), dist = new URL('../dist/',import.meta.url);
  const catalog = JSON.parse(await readFile(new URL('App/Resources/catalog.json',root),'utf8'));
  const library = JSON.parse(await readFile(new URL('App/Resources/library.json',root),'utf8'));
  const data = exportData(catalog,library);
  await mkdir(new URL('data/',dist),{recursive:true});
  await writeFile(new URL('data/catalogue.json',dist),JSON.stringify(data));
  const assets = ['index.html','app.js','core.js','storage.js','style.css','manifest.webmanifest','sw.js','icon.svg','data/catalogue.json'];
  const bytes = await Promise.all(assets.map(f=>readFile(new URL(f,dist))));
  await writeFile(new URL('version.js',dist),`self.XINYU_VERSION = '${hash(Buffer.concat(bytes))}';\n`);
  console.log(`Exported ${data.lessons.length} lessons / ${data.resources.length} resources; data version ${data.dataVersion}`);
}
