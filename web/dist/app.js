import { emptyState, searchLessons, safeURL, validateBackup, makeNote, scheduleForDate, MAX_BACKUP_BYTES } from './core.js';
import { loadState, saveState } from './storage.js';
import { createPlayerSession, PLAYBACK_RATES } from './player.js';
const main = document.querySelector('#main'), status = document.querySelector('#status');
let data, state = emptyState(), revision = 0, storageReady = false, saving = false, draftDirty = false;
let query = '', bookFilter = '', selectedDate = localDate(), swRegistration;
const drafts = new Map();
const playbackPositions = new Map();
let activePlayer;
function releasePlayer(){if(activePlayer){playbackPositions.set(activePlayer.resourceID,activePlayer.dispose());activePlayer=null;}}
const clockTime=seconds=>`${Math.floor(seconds/60)}:${String(seconds%60).padStart(2,'0')}`;
const weekdays = ['星期一','星期二','星期三','星期四','星期五','星期六','星期日'];
const lessonMap = new Map(), resourceMap = new Map();
function el(tag, props = {}, ...children) {
  const n = document.createElement(tag);
  for (const [key,value] of Object.entries(props)) {
    if (key.startsWith('on')) n.addEventListener(key.slice(2), value);
    else if (key === 'class') n.className = value;
    else if (key === 'text') n.textContent = value;
    else if (key in n && !key.startsWith('aria')) n[key] = value;
    else n.setAttribute(key,value);
  }
  n.append(...children.filter(x => x != null)); return n;
}
const p = (text, cls = 'muted') => el('p',{class:cls,text});
const button = (text, onclick, cls = '') => el('button',{type:'button',class:cls,text,onclick});
const link = (text, href, cls = '') => el('a',{href,text,class:cls});
const heading = (title, subtitle) => el('div',{class:'page-heading'},el('h1',{text:title}),subtitle ? p(subtitle) : null);
const field = (label, input) => el('label',{class:'field'},el('span',{text:label}),input);
function externalLink(url, title = '查看具体原文 ↗') {
  const safe = safeURL(url); return safe ? el('a',{href:safe,target:'_blank',rel:'noopener noreferrer',class:'text-link',text:title}) : p('此资料暂无可用原文链接');
}
function localDate(date = new Date()) { return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`; }
function notify(text, error = false) { status.textContent = text; status.className = error ? 'error visible' : 'visible'; }
function setWarning(text) { const n=document.querySelector('#storage-warning'); n.hidden=false; n.textContent=text; }
async function persist(next) {
  if (!storageReady) { notify('本机存储尚不可用，未保存。请先排查“我的”中的存储提示。',true); return false; }
  if (saving) { notify('上一项记录仍在保存，请稍候。'); return false; }
  saving = true;
  try {
    const checked = validateBackup(next,new Set(lessonMap.keys()),data.resources);
    revision = await saveState(checked,revision); state = checked; return true;
  } catch (error) { notify(error.message,true); return false; }
  finally { saving = false; }
}
async function change(mutator, message) {
  const next=structuredClone(state); mutator(next);
  if (await persist(next)) { notify(message); render(); return true; } return false;
}
function lessonCard(lesson, match = '') {
  return linkNode(`#lesson/${lesson.id}`,el('span',{class:'lesson-number',text:String(lesson.number).padStart(2,'0')}),el('span',{class:'lesson-info'},el('strong',{text:lesson.title}),el('small',{text:`${lesson.author || '佚名'} · ${data.books.find(b=>b.id===lesson.bookID).title}`}),match?el('span',{class:'match',text:match}):null),el('span',{class:'chevron',text:'›','aria-hidden':'true'}));
}
function linkNode(href,...children) { return el('a',{href,class:'list-row'},...children); }
function home() {
  const today=scheduleForDate(state,localDate());
  main.append(el('section',{class:'hero'},el('span',{class:'eyebrow',text:'欣语 · 我的语文学习册'}),el('h1',{text:'读一篇好文章，\n准备一堂好课。'}),p('从课文出发，把阅读、备课和想法放在一起。'),link('开始选课 →','#courses','primary button-link')));
  main.append(el('section',{class:'stats'},...[[data.lessons.length,'篇课文'],[6,'册教材'],[state.notes.length,'条本机笔记']].map(([n,t])=>el('div',{},el('strong',{text:String(n)}),el('span',{text:t})))));
  main.append(el('section',{class:'panel'},el('div',{class:'section-title'},el('h2',{text:'今天的安排'}),link('查看课表','#schedule')),today.length ? el('div',{},...today.map(s=>p(`${s.time} · ${s.className} · ${lessonMap.get(s.lessonID).title}${s.adjusted?'（临时调整）':''}`,''))) : p('今天没有安排。可以为自己添加一节课。'),p('提醒未启用；关闭网页后不会发送通知。','caption')));
  main.append(el('section',{class:'panel'},el('h2',{text:'按册开始'}),el('div',{class:'book-grid'},...data.books.map((b,i)=>el('a',{href:'#courses',class:'book-card',onclick:()=>{bookFilter=b.id;query='';}},el('span',{text:`0${i+1}`,class:'eyebrow'}),el('strong',{text:b.title}),el('span',{text:`${data.lessons.filter(l=>l.bookID===b.id).length} 篇课文 →`,class:'caption'}))))));
  main.append(el('section',{class:'panel soft'},el('h2',{text:'只保存在这台设备'}),p('收藏、笔记和课表不会自动跨设备同步。建议定期导出备份，尤其在清理 Safari 数据之前。'),link('备份与主屏幕使用指南','#me','text-link')));
}
function courses() {
  main.append(heading('课程','先找课名或作者，再挑选适合自己的资料。'));
  const results=el('div',{class:'results'}), count=p('','caption');
  const input=el('input',{type:'search',placeholder:'搜索课名、篇目或作者',value:query,'aria-label':'搜索课名或作者',maxLength:100});
  let composing=false;
  const update=()=>{
    const matches=searchLessons(query,data.lessons.filter(l=>!bookFilter || l.bookID===bookFilter));
    count.textContent=`找到 ${matches.length} 篇课文${query.trim()?' · 精确结果在前，相关结果有单独标记':''}`;
    results.replaceChildren();
    if(!matches.length) results.append(el('section',{class:'panel'},el('h2',{text:'暂时没有匹配的课文'}),p('试试完整课名、作者，或切换到全部教材。')));
    else if(query.trim()) results.append(el('section',{class:'group'},...matches.map(x=>lessonCard(x.lesson,x.match))));
    else for(const book of data.books.filter(b=>!bookFilter || b.id===bookFilter)) {
      results.append(el('h2',{text:book.title}),p(book.verification,'caption'));
      for(const unit of book.units) {
        const lessons=matches.filter(x=>x.lesson.unitID===unit.id);
        if(lessons.length) results.append(el('h3',{text:unit.title}),el('section',{class:'group'},...lessons.map(x=>lessonCard(x.lesson))));
      }
    }
  };
  input.addEventListener('compositionstart',()=>{composing=true;});
  input.addEventListener('compositionend',()=>{composing=false;query=input.value;update();});
  input.addEventListener('input',()=>{if(!composing){query=input.value;update();}});
  const select=el('select',{'aria-label':'教材册次',onchange:e=>{bookFilter=e.target.value;update();}},el('option',{value:'',text:'全部教材'}),...data.books.map(b=>el('option',{value:b.id,text:b.title})));
  select.value=bookFilter; main.append(el('div',{class:'search-tools'},input,select),count,results); update();
}
function lessonDetail(id) {
  const lesson=lessonMap.get(id); if(!lesson) return missing();
  main.append(link('‹ 返回课程','#courses','back'),heading(lesson.title,`${lesson.author || '佚名'} · ${data.books.find(b=>b.id===lesson.bookID).title}`));
  main.append(button(state.favorites.includes(id)?'★ 已收藏 · 取消收藏':'☆ 收藏这篇课文',()=>change(s=>{s.favorites=s.favorites.includes(id)?s.favorites.filter(x=>x!==id):[...s.favorites,id];},'收藏已更新'),'secondary'));
  if(lesson.focus.length) main.append(p(`包含篇目：${lesson.focus.join('、')}`));
  const resources=data.resources.filter(r=>r.lessonID===id);
  for(const [title,predicate] of [['自编阅读与备课',r=>!!r.body],['具体视频资料',r=>r.kind==='video'],['外部文字与资料',r=>!r.body&&r.kind!=='video']]) {
    const entries=resources.filter(predicate);
    main.append(el('h2',{text:`${title} · ${entries.length}`}));
    if(!entries.length) main.append(p('暂未收录，不以其他资料代替。'));
    else main.append(el('section',{class:'group'},...entries.map(r=>linkNode(`#resource/${r.id}`,el('span',{class:'resource-symbol','aria-hidden':'true',text:r.kind==='video'?'▷':'文'}),el('span',{class:'lesson-info'},el('strong',{text:r.title}),el('small',{text:`${r.source} · ${r.category}${r.isPaid?' · 原站可能收费':''}`}),p(r.summary,'caption')),el('span',{class:'chevron',text:'›'})))));
  }
  main.append(p('视频使用系统控件播放公开完整分集，清晰度以原站实际返回为准；外部全文尚未接入。没有收录的试讲稿不会用提纲冒充。','caption'));
}
function highlightedBody(resource) {
  const article=el('article',{class:'reading-body',tabIndex:0,'aria-label':'可选中文字的自编正文'});
  const ranges=state.notes.filter(n=>n.resourceID===resource.id && n.quote && resource.body.slice(n.start,n.end)===n.quote).map(n=>[n.start,n.end]).sort((a,b)=>a[0]-b[0]);
  const merged=[];
  for(const range of ranges) { const last=merged.at(-1); if(last&&range[0]<=last[1]) last[1]=Math.max(last[1],range[1]); else merged.push([...range]); }
  let offset=0;
  for(const [start,end] of merged) { article.append(document.createTextNode(resource.body.slice(offset,start)),el('mark',{text:resource.body.slice(start,end)}));offset=end; }
  article.append(document.createTextNode(resource.body.slice(offset))); return article;
}
function resourceDetail(id) {
  const resource=resourceMap.get(id); if(!resource) return missing();
  main.append(link(`‹ ${lessonMap.get(resource.lessonID).title}`,`#lesson/${resource.lessonID}`,'back'),heading(resource.title,`${resource.source} · ${resource.category}`));
  let article,player;
  if(resource.body) {
    main.append(p('欣语自编资料，不是教材全文或官方答案。选中文字后点击“取用所选文字”，再保存重点或笔记。','notice'));
    article=highlightedBody(resource);main.append(article);
  } else if(resource.kind==='video') {
    const video=el('video',{controls:true,playsInline:true,preload:'metadata',class:'study-video','aria-label':resource.title});
    const message=p('正在连接视频…','caption');message.setAttribute('role','status');
    player=createPlayerSession({video,resourceID:id,...playbackPositions.get(id),onStatus:(text,error)=>{message.textContent=text;message.className=error?'notice':'caption';}});activePlayer=player;
    const rate=el('select',{'aria-label':'播放速度',onchange:e=>player.setRate(Number(e.target.value))},...PLAYBACK_RATES.map(value=>el('option',{value:String(value),text:`${value} 倍速`})));
    rate.value=String(playbackPositions.get(id)?.rate||1);
    main.append(el('section',{class:'panel video-panel'},video,message,el('div',{class:'player-actions'},field('播放速度',rate),button('全屏',()=>player.fullscreen(),'secondary'),button('重试视频',()=>player.retry(),'secondary')),p('仅播放原站公开的完整视频，不解锁登录或付费内容。','caption'),externalLink(resource.url,'视频来源与署名 ↗')));
    void player.retry();
  } else {
    main.append(el('section',{class:'panel'},el('h2',{text:'此文请在原站阅读'}),p('此来源尚未验证允许网页内全文阅读。当前不嵌入、不自动展开，也不抓取受限正文。'),externalLink(resource.url)));
  }
  if(resource.body && resource.url) main.append(externalLink(resource.url));
  const draft=drafts.get(id)||{text:'',quote:'',start:null,end:null,timestamp:''}; drafts.set(id,draft);
  const quoteView=p(draft.quote?`已选：${draft.quote}`:'尚未选择文字','quote-preview');
  const text=el('textarea',{rows:4,maxLength:10000,placeholder:'记下理解、课堂想法或待查的问题…',value:draft.text,oninput:e=>{draft.text=e.target.value;draftDirty=true;}});
  const timestamp=el('input',{type:'text',inputMode:'numeric',placeholder:'例如 03:25',value:draft.timestamp,pattern:'(?:[0-9]{1,4}:)?[0-5]?[0-9]:[0-5][0-9]|[0-9]{1,6}',oninput:e=>{draft.timestamp=e.target.value;draftDirty=true;}});
  const form=el('form',{class:'panel note-editor',onsubmit:async event=>{
    event.preventDefault(); let seconds=null;
    if(resource.kind==='video' && timestamp.value.trim()) {
      const value=timestamp.value.trim();
      if(!/^(?:\d{1,4}:)?[0-5]?\d:[0-5]\d$|^\d{1,6}$/.test(value)){notify('时间请填写秒数、分:秒或时:分:秒。',true);return;}
      seconds=value.split(':').reduce((n,v)=>n*60+Number(v),0);
    }
    if(!text.value.trim() && !draft.quote){notify('先写一条笔记，或选择一段重点。',true);return;}
    const note=makeNote({lessonID:resource.lessonID,resourceID:id,text:text.value.trim(),quote:draft.quote,start:draft.start,end:draft.end,url:resource.url,timestampSeconds:seconds});
    const submitted=JSON.stringify(draft), next=structuredClone(state);next.notes.push(note);
    if(await persist(next)){if(JSON.stringify(draft)===submitted)drafts.delete(id);draftDirty=[...drafts.values()].some(d=>d.text||d.quote||d.timestamp);notify('已保存到本机');render();}
  }},el('h2',{text:resource.kind==='video'?'视频时间点笔记':'重点与笔记'}));
  if(article) form.append(button('取用所选文字',()=>{
    const selection=getSelection();
    if(!selection.rangeCount||selection.isCollapsed){notify('请先在上面的正文中选择文字。');return;}
    const range=selection.getRangeAt(0);
    if(!article.contains(range.startContainer)||!article.contains(range.endContainer)){notify('只能选择这篇自编正文中的文字。',true);return;}
    const before=document.createRange();before.selectNodeContents(article);before.setEnd(range.startContainer,range.startOffset);
    draft.start=before.toString().length;draft.quote=range.toString();draft.end=draft.start+draft.quote.length;
    quoteView.textContent=`已选：${draft.quote}`;draftDirty=true;
  },'secondary'),quoteView,button('清除所选文字',()=>{draft.quote='';draft.start=null;draft.end=null;quoteView.textContent='尚未选择文字';},'text-button'));
  if(resource.kind==='video') form.append(button('取用当前播放时间',()=>{
    const seconds=player?.currentTime();if(seconds===null||seconds===undefined){notify('视频尚未就绪，不能读取播放时间。',true);return;}
    timestamp.value=clockTime(seconds);draft.timestamp=timestamp.value;draftDirty=true;
  },'secondary'),field('时间点（可取用当前时间，也可手动填写）',timestamp),p('保存前点击“取用当前播放时间”；已保存的时间点可跳转回本视频。','caption'));
  form.append(field('笔记内容',text),el('button',{type:'submit',class:'primary',text:'保存到本机',disabled:!storageReady}));main.append(form);
  const notes=state.notes.filter(n=>n.resourceID===id);
  main.append(el('h2',{text:`这份资料的笔记 · ${notes.length}`}),...notes.map(noteCard));
}
function noteCard(n) {
  const resource=resourceMap.get(n.resourceID);
  return el('section',{class:'panel note-card'},el('div',{class:'section-title'},link(resource?.title||'资料',`#resource/${n.resourceID}`),button('删除',async()=>{if(confirm('删除这条笔记及对应重点？')) await change(s=>{s.notes=s.notes.filter(x=>x.id!==n.id);},'笔记已删除');},'text-button')),n.quote?el('blockquote',{text:n.quote}):null,n.text?p(n.text,'note-text'):null,p(new Date(n.createdAt).toLocaleString('zh-CN'),'caption'),n.timestampSeconds!==null?button(`跳转到 ${clockTime(n.timestampSeconds)}`,()=>{
    if(activePlayer?.resourceID===n.resourceID){if(!activePlayer.seek(n.timestampSeconds))notify('视频尚未就绪或时间超出长度，请待视频加载后重试。',true);}
    else{playbackPositions.set(n.resourceID,{position:n.timestampSeconds,rate:1});location.hash=`#resource/${n.resourceID}`;}
  },'text-button'):null);
}
function lessonSelect(value='7u-01') { const s=el('select',{},...data.lessons.map(l=>el('option',{value:l.id,text:`${data.books.find(b=>b.id===l.bookID).title} · ${l.title}`})));s.value=value;return s; }
function schedule() {
  main.append(heading('我的课表','只存在本机，从空课表开始。提醒未启用。'));
  const date=el('input',{type:'date',value:selectedDate,onchange:e=>{if(e.target.value){selectedDate=e.target.value;render();}}});
  const today=scheduleForDate(state,selectedDate);
  main.append(el('section',{class:'panel'},field('查看某一天',date),today.length?el('div',{},...today.map(s=>el('p',{text:`${s.time} · ${s.className} · ${lessonMap.get(s.lessonID).title}${s.adjusted?'（临时调整）':''}`}))):p('这一天没有课程。')));
  const weekday=el('select',{},...weekdays.map((w,i)=>el('option',{value:String(i+1),text:w}))),time=el('input',{type:'time',value:'08:00',required:true}),className=el('input',{type:'text',maxLength:100,required:true,placeholder:'例如：七年级一班'}),lesson=lessonSelect();
  main.append(el('details',{class:'panel'},el('summary',{text:'＋ 添加每周课程'}),el('form',{class:'form-grid',onsubmit:async e=>{e.preventDefault();await change(s=>{s.schedule.push({id:crypto.randomUUID(),weekday:Number(weekday.value),time:time.value,className:className.value.trim(),lessonID:lesson.value});},'每周课程已保存');}},field('星期',weekday),field('上课时间',time),field('班级',className),field('课文',lesson),el('button',{type:'submit',class:'primary',text:'保存课程',disabled:!storageReady}))));
  main.append(el('h2',{text:'每周安排'}));
  if(!state.schedule.length) main.append(p('还没有课程，点击上方添加。'));
  for(const s of [...state.schedule].sort((a,b)=>a.weekday-b.weekday||a.time.localeCompare(b.time))) {
    const section=el('section',{class:'panel'},el('div',{class:'section-title'},el('h3',{text:`${weekdays[s.weekday-1]} ${s.time}`}),button('删除',async()=>{if(confirm('删除这节每周课程及它的临时调整？'))await change(n=>{n.schedule=n.schedule.filter(x=>x.id!==s.id);n.exceptions=n.exceptions.filter(x=>x.scheduleID!==s.id);},'课程已删除');},'text-button')),p(`${s.className} · ${lessonMap.get(s.lessonID).title}`,''));
    const nextDate=new Date();nextDate.setDate(nextDate.getDate()+((s.weekday-(nextDate.getDay()||7)+7)%7));
    const d=el('input',{type:'date',required:true,value:localDate(nextDate)}),t=el('input',{type:'time',value:s.time,required:true}),c=el('input',{value:s.className,maxLength:100,required:true}),l=lessonSelect(s.lessonID),cancel=el('input',{type:'checkbox'});
    section.append(el('details',{},el('summary',{text:'临时调整某一天'}),el('form',{class:'form-grid',onsubmit:async e=>{e.preventDefault();await change(n=>{n.exceptions=n.exceptions.filter(x=>!(x.scheduleID===s.id&&x.date===d.value));n.exceptions.push({id:crypto.randomUUID(),scheduleID:s.id,date:d.value,cancelled:cancel.checked,time:t.value,className:c.value.trim(),lessonID:l.value});},'临时调整已保存');}},field('日期（与原星期一致）',d),field('调整后时间',t),field('调整后班级',c),field('调整后课文',l),field('这一天停课',cancel),el('button',{type:'submit',class:'primary',text:'保存临时调整',disabled:!storageReady}))));
    for(const e of state.exceptions.filter(e=>e.scheduleID===s.id).sort((a,b)=>a.date.localeCompare(b.date))) section.append(el('div',{class:'exception'},p(`${e.date} · ${e.cancelled?'停课':`${e.time} ${e.className} · ${lessonMap.get(e.lessonID).title}`}`,''),button('撤销调整',()=>change(n=>{n.exceptions=n.exceptions.filter(x=>x.id!==e.id);},'已恢复每周安排'),'text-button')));
    main.append(section);
  }
}
function exportBackup() {
  if(!storageReady){notify('尚未成功读取本机数据，不能导出空备份覆盖旧文件。',true);return;}
  const blob=new Blob([JSON.stringify(state)],{type:'application/json'}),url=URL.createObjectURL(blob),a=el('a',{href:url,download:`欣语网页备份-${localDate()}.json`});
  document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);notify('已请求下载备份，请在“文件”或下载列表确认保存。');
}
async function importBackup(file) {
  if(!file)return;
  try {
    if(file.size>MAX_BACKUP_BYTES)throw new Error('备份不可超过 2 MB；本机记录没有改变');
    const next=validateBackup(await file.text(),new Set(lessonMap.keys()),data.resources);
    if(!confirm(`将用备份中的 ${next.notes.length} 条笔记、${next.favorites.length} 个收藏、${next.schedule.length} 节课程替换本机记录。请先导出当前备份。继续？`))return;
    if(await persist(next)){notify('备份已完整导入');render();}
  } catch(error){notify(`导入未完成：${error.message}。原有记录未替换。`,true);}
}
async function checkUpdate() {
  notify('正在检查已发布的课程数据版本…');
  try {
    const response=await fetch('./data/catalogue.json',{cache:'no-store'});
    if(!response.ok||response.redirected||!response.headers.get('content-type')?.includes('application/json'))throw new Error('当前无法读取已发布的数据');
    const latest=await response.json(); if(!latest.dataVersion)throw new Error('返回的不是课程数据');
    await swRegistration?.update();
    notify(latest.dataVersion===data.dataVersion?'课程数据仍是当前版本；本次没有搜索新资料。':'发现网站已发布新数据。请先保存编辑内容，再关闭所有欣语页面后重新打开。不会自动刷新当前编辑。');
  }catch{notify('暂时无法联网检查；仍可使用已加载的课程。本次没有确认新版本。',true);}
}
function me() {
  main.append(heading('我的','想法留在本机，记得为它们做一份备份。'));
  main.append(el('section',{class:'panel'},el('h2',{text:'本机数据与备份'}),p(storageReady?'本机存储已连接。不会上传笔记、收藏或课表；不同浏览器、主屏幕应用及设备可能各自独立。':'本机存储读取失败：当前仅可浏览。未启用临时保存，也不会用空记录覆盖旧数据。'),p('Safari 清理、系统回收网站数据或换设备都会影响记录。导出文件包含你的私人内容，请自行保管。'),el('div',{class:'actions'},button('导出网页备份',exportBackup,'primary'),el('label',{class:'button-link secondary',text:'导入网页备份'},el('input',{type:'file',accept:'.json,application/json',class:'file-input','aria-label':'选择网页备份文件',disabled:!storageReady,onchange:e=>importBackup(e.target.files[0])}))),p('独立网页版备份（第 1 版），最大 2 MB。不兼容原生 App 备份；导入会先检查完整内容，再一次性替换。','caption')));
  main.append(el('section',{class:'panel'},el('h2',{text:'添加到 iPhone / iPad 主屏幕'}),p('先在 Safari 打开此私有链接，完成所有者账号登录。主屏幕模式也可能要求重新登录。'),el('ol',{class:'install-steps'},...[['1','打开分享','在 Safari 点击分享按钮（方框向上箭头）。'],['2','添加到主屏幕','在分享菜单中找到“添加到主屏幕”；可向下滚动。'],['3','确认添加','名称保留“欣语”，按系统提示添加后，从主屏幕打开。']].map(([n,title,body])=>el('li',{},el('span',{class:'step-number',text:n}),el('div',{},el('strong',{text:title}),p(body))))),p('无需证书、描述文件或付费签名。这是网页，不是原生 IPA。首次打开需联网；仅在离线缓存成功后，目录与自编文字可离线。第三方全文尚未接入；视频与来源链接仍需网络及有效登录。','caption')));
  main.append(el('section',{class:'panel'},el('h2',{text:'资料与版本'}),p(`整理日期：${data.checkedAt} · 数据版本：${data.dataVersion}`,'caption'),button('检查网站资料更新',checkUpdate,'secondary'),p('只比较网站已经发布的数据版本，不会自动搜索第三方资料。提醒未启用。私有测试链接仅授权所有者访问。','caption')));
  main.append(el('h2',{text:`我的收藏 · ${state.favorites.length}`}),state.favorites.length?el('section',{class:'group'},...state.favorites.map(id=>lessonCard(lessonMap.get(id)))):p('还没有收藏，可在课文详情中添加。'));
  main.append(el('h2',{text:`我的笔记 · ${state.notes.length}`}),...(state.notes.length?[...state.notes].reverse().map(noteCard):[p('阅读自编资料或观看视频时，可以记下第一条笔记。')]));
}
function missing() {main.append(heading('没有找到这份资料','链接可能已变更，请返回课程重新选择。'),link('返回课程','#courses','button-link primary'));}
function render() {
  if(!data)return;
  releasePlayer();
  main.replaceChildren(); const [route='home',id]=location.hash.slice(1).split('/');
  const tab=['lesson','resource'].includes(route)?'courses':route;
  document.querySelectorAll('[data-tab]').forEach(a=>{if(a.dataset.tab===tab)a.setAttribute('aria-current','page');else a.removeAttribute('aria-current');});
  if(route==='courses')courses();else if(route==='lesson')lessonDetail(id);else if(route==='resource')resourceDetail(id);else if(route==='schedule')schedule();else if(route==='me')me();else home();
  document.title=`欣语 · ${main.querySelector('h1')?.textContent || '语文学习'}`;
}
async function start() {
  try {
    const response=await fetch('./data/catalogue.json');if(!response.ok)throw new Error('课程数据请求失败');
    const loaded=await response.json();
    if(loaded.schemaVersion!==1||!Array.isArray(loaded.lessons)||loaded.lessons.length!==198||!Array.isArray(loaded.resources))throw new Error('课程数据不完整');
    data=loaded;data.lessons.forEach(l=>lessonMap.set(l.id,l));data.resources.forEach(r=>resourceMap.set(r.id,r));
    try {
      const stored=await loadState();state=stored.state?validateBackup(stored.state,new Set(lessonMap.keys()),data.resources):emptyState();revision=stored.revision;storageReady=true;
    }catch(error){setWarning(`本机记录暂不可读，保存与导入已暂停，旧数据未覆盖。${error.message} 请检查 Safari 存储权限后刷新；不要清理网站数据。`);}
    render();
    if('serviceWorker' in navigator) {
      navigator.serviceWorker.register('./sw.js',{scope:'./',updateViaCache:'none'}).then(reg=>{
        swRegistration=reg;
        const updateNotice=()=>{if(reg.waiting)notify('新版本已准备好。保存内容后关闭所有欣语页面再打开；当前页面不会自动刷新。');};
        updateNotice();reg.addEventListener('updatefound',()=>reg.installing?.addEventListener('statechange',updateNotice));
      }).catch(()=>notify('离线缓存暂不可用；联网阅读和已连接的本机笔记仍可使用。'));
    }
  }catch{
    main.replaceChildren(el('section',{class:'panel'},el('h1',{text:'暂时无法加载课程'}),p('首次打开需要联网并完成私有站点登录。若已缓存仍打不开，请恢复网络重试；不要清理本机数据。'),button('重试',()=>location.reload(),'primary')));
  }
}
addEventListener('hashchange',()=>{render();scrollTo(0,0);main.focus({preventScroll:true});});
addEventListener('pagehide',releasePlayer);
addEventListener('pageshow',event=>{if(event.persisted)render();});
addEventListener('beforeunload',event=>{if(draftDirty||saving){event.preventDefault();event.returnValue='';}});
addEventListener('offline',()=>notify('当前离线：仅已成功缓存的目录与自编文字可用；本机记录仍取决于存储权限，外部来源需联网。'));
start();
