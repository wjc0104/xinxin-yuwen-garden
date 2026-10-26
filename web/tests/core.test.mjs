import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { exportData } from '../scripts/export-data.mjs';
import { searchLessons, safeURL, validateBackup, emptyState, makeNote, scheduleForDate, MAX_BACKUP_BYTES } from '../dist/core.js';
const catalog = JSON.parse(await readFile(new URL('../../App/Resources/catalog.json', import.meta.url)));
const library = JSON.parse(await readFile(new URL('../../App/Resources/library.json', import.meta.url)));
const data = exportData(catalog, library);
const ids = new Set(data.lessons.map(x => x.id));
const valid = () => emptyState();
test('compact exported near-limit backup remains importable',async()=>{
  const s=valid(),r=data.resources.find(r=>r.kind==='video');
  for(let i=0;i<190;i++)s.notes.push(makeNote({lessonID:r.lessonID,resourceID:r.id,text:'x'.repeat(10000),quote:'',start:null,end:null,url:r.url,timestampSeconds:0}));
  while(Buffer.byteLength(JSON.stringify(s))<MAX_BACKUP_BYTES-11000)s.notes.push({...s.notes[0],id:crypto.randomUUID()});
  validateBackup(s,ids,data.resources);
  assert.ok(Buffer.byteLength(JSON.stringify(s,null,2))>MAX_BACKUP_BYTES);
  const app=await readFile(new URL('../dist/app.js',import.meta.url),'utf8');
  assert.match(app,/new Blob\(\[JSON\.stringify\(state\)\]/);
  assert.deepEqual(validateBackup(JSON.stringify(s),ids,data.resources),s);
});
test('all 198 stable lesson IDs and original order, explicit field whitelist only', () => {
  assert.equal(data.lessons.length, 198);
  assert.deepEqual(data.lessons.map(x => x.id), catalog.books.flatMap(b => b.units.flatMap(u => u.lessons.map(l => l.id))));
  assert.deepEqual(Object.keys(data.lessons[0]).sort(), ['id','number','title','author','focus','bookID','unitID'].sort());
  assert.deepEqual(Object.keys(data.resources[0]).sort(), ['id','lessonID','title','kind','body','url','source','isPaid','category','durationSeconds','checkedAt','summary'].sort());
  const tainted = structuredClone(library); tainted[0].privateToken = 'secret'; tainted[0].localFile = '/private';
  assert.equal(JSON.stringify(exportData(catalog, tainted)).includes('secret'), false);
  assert.equal(JSON.stringify(exportData(catalog, tainted)).includes('/private'), false);
  assert.equal(data.resources.length, 1163);
  assert.ok(data.resources.filter(x => x.body).every(x => ['欣语备课提纲','欣语原创练习'].includes(x.source)));
});
test('exact title 春 first; weak matches labelled; author Mao; blank and absent queries', () => {
  const results = searchLessons(' 春 ', data.lessons);
  assert.equal(results[0].lesson.title, '春'); assert.equal(results[0].match, '课名完全匹配');
  assert.ok(results.slice(1).every(x => x.match !== '课名完全匹配'));
  const mao = searchLessons('毛泽东', data.lessons); assert.ok(mao.length); assert.ok(mao.every(x => x.lesson.author.includes('毛泽东')));
  assert.deepEqual(searchLessons(' ', data.lessons).map(x => x.lesson.id), [...ids]);
  assert.deepEqual(searchLessons('不存在的课名xyz', data.lessons), []);
  assert.equal(searchLessons('春', [{id:'1',title:'无关',author:'作者',focus:[],body:'春'}]).length, 0);
});
test('URL protocols and credentials are constrained', () => {
  for (const url of ['javascript:alert(1)','data:text/html,x','file:///a','//evil.com','https://a:b@example.com','not-url']) assert.equal(safeURL(url), null);
  assert.equal(safeURL('https://example.com/a'), 'https://example.com/a');
});
test('note identity survives valid round trip; quote positions and source association validated', () => {
  const resource = data.resources.find(x => x.body); const s = valid();
  const n = makeNote({lessonID:resource.lessonID,resourceID:resource.id,text:'我的笔记',quote:resource.body.slice(0,4),start:0,end:4,url:resource.url,timestampSeconds:null});
  s.notes.push(n); const restored = validateBackup(JSON.stringify(s), ids, data.resources);
  assert.equal(restored.notes[0].id,n.id); assert.deepEqual(restored,s);
  assert.throws(() => validateBackup({...s,notes:[{...n,quote:'不相符'}]},ids,data.resources));
});
test('invalid backups reject without mutating existing state', () => {
  const original = valid(); original.favorites.push('7u-01'); const before = JSON.stringify(original);
  const invalid = [null,[],{}, {...valid(),schemaVersion:2}, {...valid(),favorites:['unknown']}, {...valid(),favorites:['7u-01','7u-01']}, {...valid(),notes:[{}]}, {...valid(),unexpected:true}];
  const r=data.resources[0]; const n=makeNote({lessonID:r.lessonID,resourceID:r.id,text:'x',quote:'',start:null,end:null,url:r.url,timestampSeconds:1});
  invalid.push({...valid(),notes:[n,n]}, {...valid(),notes:[{...n,url:'javascript:alert(1)'}]}, {...valid(),notes:[{...n,resourceID:'unknown'}]}, {...valid(),notes:[{...n,timestampSeconds:-1}]});
  for(const value of invalid) assert.throws(() => validateBackup(value,ids,data.resources));
  assert.throws(() => validateBackup(' '.repeat(MAX_BACKUP_BYTES+1),ids));
  assert.throws(() => validateBackup('{"__proto__":{"polluted":true}}',ids));
  assert.throws(() => validateBackup({...valid(),notes:[{...n,constructor:{}}]},ids));
  assert.equal({}.polluted,undefined); assert.equal(JSON.stringify(original),before);
});
test('Chinese weekly schedule and date-specific replacement/cancellation', () => {
 const s=valid(); s.schedule.push({id:'s1',weekday:1,time:'08:00',className:'七年级一班',lessonID:'7u-01'});
 s.exceptions.push({id:'e1',scheduleID:'s1',date:'2026-10-26',cancelled:false,time:'09:00',className:'临时班级',lessonID:'7u-02'});
 assert.equal(scheduleForDate(s,'2026-10-26')[0].time,'09:00'); assert.equal(scheduleForDate(s,'2026-11-02')[0].time,'08:00');
 s.exceptions[0].cancelled=true; assert.equal(scheduleForDate(s,'2026-10-26').length,0);
 validateBackup(s,ids,data.resources);
 for(const date of ['2026-02-30','bad']) assert.throws(() => validateBackup({...s,exceptions:[{...s.exceptions[0],date}]},ids));
 assert.throws(() => validateBackup({...s,exceptions:[s.exceptions[0],{...s.exceptions[0],id:'e2'}]},ids));
});
