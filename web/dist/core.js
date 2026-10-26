export const MAX_BACKUP_BYTES = 2 * 1024 * 1024;
export const emptyState = () => ({ format: 'xinyu-web', schemaVersion: 1, favorites: [], notes: [], schedule: [], exceptions: [] });
export function safeURL(value) {
  if (typeof value !== 'string' || value.length > 4096) return null;
  try {
    const u = new URL(value);
    return ['https:', 'http:'].includes(u.protocol) && !u.username && !u.password ? u.href : null;
  } catch { return null; }
}
export function searchLessons(query, lessons) {
  const q = query.trim().normalize('NFKC').toLocaleLowerCase('zh');
  const norm = v => v.normalize('NFKC').toLocaleLowerCase('zh');
  return lessons.map((lesson, index) => {
    const title = norm(lesson.title), author = norm(lesson.author), focus = lesson.focus.map(norm);
    let rank = 9, match = '';
    if (!q) { rank = 0; match = ''; }
    else if (title === q) { rank = 0; match = '课名完全匹配'; }
    else if (author === q || author.split(/[、，,等\s]+/).includes(q)) { rank = 1; match = '作者匹配'; }
    else if (focus.includes(q)) { rank = 2; match = '篇目完全匹配'; }
    else if (title.includes(q) || focus.some(x => x.includes(q))) { rank = 3; match = '相关课名 / 篇目'; }
    else if (q.length > 1 && author.includes(q)) { rank = 4; match = '相关作者'; }
    return { lesson, match, rank, index };
  }).filter(x => x.rank < 9).sort((a,b) => a.rank-b.rank || a.index-b.index).map(({lesson,match}) => ({lesson,match}));
}
export const makeNote = fields => ({ id: crypto.randomUUID(), ...fields, createdAt: new Date().toISOString() });
function check(condition, message = '备份结构或内容不正确') { if (!condition) throw new Error(message); }
function object(value, keys) {
  check(value && typeof value === 'object' && !Array.isArray(value));
  check(Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
  check(Object.keys(value).length === keys.length && keys.every(k => Object.hasOwn(value,k)));
  check(Object.keys(value).every(k => keys.includes(k)));
}
function str(v, max = 500, allowEmpty = false) { check(typeof v === 'string' && v.length <= max && (allowEmpty || v.trim().length > 0)); }
function unique(items, key = x => x.id) { check(new Set(items.map(key)).size === items.length, '备份中有重复记录'); }
function list(v, max) { check(Array.isArray(v) && v.length <= max); }
function id(v) { str(v,160); check(/^[\w-]+$/.test(v)); }
function dateValid(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const d = new Date(`${value}T12:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0,10) === value;
}
function time(v) { check(typeof v === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(v)); }
export function validateBackup(input, knownLessonIDs, resources) {
  let value;
  try {
    const raw = typeof input === 'string' ? input : JSON.stringify(input);
    check(typeof raw === 'string' && new TextEncoder().encode(raw).length <= MAX_BACKUP_BYTES, '备份不可超过 2 MB');
    value = JSON.parse(raw, (key,v) => {
      check(!['__proto__','constructor','prototype'].includes(key), '备份包含不允许的字段'); return v;
    });
  } catch (error) { throw new Error(error instanceof SyntaxError ? '备份不是有效的 JSON 文件' : error.message); }
  object(value, ['format','schemaVersion','favorites','notes','schedule','exceptions']);
  check(value.format === 'xinyu-web' && value.schemaVersion === 1, '仅支持欣语网页版第 1 版备份，不兼容原生备份');
  const lesson = v => check(typeof v === 'string' && knownLessonIDs.has(v), '备份引用了不存在的课文');
  list(value.favorites,198); value.favorites.forEach(lesson); unique(value.favorites, x => x);
  const resourceMap = resources && new Map(resources.map(r => [r.id,r]));
  list(value.notes,5000); unique(value.notes);
  for (const n of value.notes) {
    object(n,['id','lessonID','resourceID','text','quote','start','end','url','timestampSeconds','createdAt']);
    id(n.id); lesson(n.lessonID); id(n.resourceID); str(n.text,10000,true); str(n.quote,10000,true);
    check(n.text.trim() || n.quote, '空笔记不可导入');
    str(n.url,4096,true); check(n.url === '' || safeURL(n.url) !== null, '备份包含不安全的链接');
    check(n.timestampSeconds === null || (Number.isInteger(n.timestampSeconds) && n.timestampSeconds >= 0 && n.timestampSeconds <= 604800));
    check(n.quote ? Number.isInteger(n.start) && n.start >= 0 && Number.isInteger(n.end) && n.end > n.start && n.end-n.start === n.quote.length : n.start === null && n.end === null);
    check(typeof n.createdAt === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(n.createdAt) && !Number.isNaN(Date.parse(n.createdAt)));
    if (resourceMap) {
      const r = resourceMap.get(n.resourceID);
      check(r && r.lessonID === n.lessonID && r.url === n.url, '笔记资料或来源与当前目录不符');
      check(!n.quote || r.body.slice(n.start,n.end) === n.quote, '重点位置与当前正文不符');
      check(n.timestampSeconds === null || r.kind === 'video');
    }
  }
  list(value.schedule,500); unique(value.schedule);
  for (const s of value.schedule) {
    object(s,['id','weekday','time','className','lessonID']); id(s.id); lesson(s.lessonID); time(s.time); str(s.className,100);
    check(Number.isInteger(s.weekday) && s.weekday >= 1 && s.weekday <= 7);
  }
  list(value.exceptions,2000); unique(value.exceptions); unique(value.exceptions,x => `${x.scheduleID}:${x.date}`);
  const schedules = new Map(value.schedule.map(s => [s.id,s]));
  for (const e of value.exceptions) {
    object(e,['id','scheduleID','date','cancelled','time','className','lessonID']); id(e.id); id(e.scheduleID); lesson(e.lessonID); time(e.time); str(e.className,100);
    check(schedules.has(e.scheduleID) && dateValid(e.date) && typeof e.cancelled === 'boolean');
    const weekday = new Date(`${e.date}T12:00:00`).getDay() || 7;
    check(schedules.get(e.scheduleID).weekday === weekday, '临时调整日期必须对应原课表星期');
  }
  return value;
}
export function scheduleForDate(state, date) {
  if (!dateValid(date)) return [];
  const weekday = new Date(`${date}T12:00:00`).getDay() || 7;
  return state.schedule.filter(s => s.weekday === weekday).map(s => {
    const e = state.exceptions.find(e => e.scheduleID === s.id && e.date === date);
    return e ? (e.cancelled ? null : {...s, ...e, adjusted:true}) : s;
  }).filter(Boolean).sort((a,b) => a.time.localeCompare(b.time));
}
