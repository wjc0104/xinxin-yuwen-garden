"""Build a lesson-indexed library from checked public video metadata. No search URLs."""
import json, re, hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
catalog = json.loads((ROOT/'App/Resources/catalog.json').read_text(encoding='utf-8'))
lessons = [l for b in catalog['books'] for u in b['units'] for l in u['lessons']]
def norm(s):
    return re.sub(r'[^\u4e00-\u9fffA-Za-z0-9]', '', re.sub(r'（节选）|\(节选\)|——.*', '', s)).lower()
aliases = {'7d-02':['说和做'],'8u-04':['飞天凌空'],'8u-05':['一着惊海天'],
 '9u-05':['你是人间的四月天'],'8u-21':['人民英雄永垂不朽'],'9u-07':['培养德智体美劳全面发展的社会主义建设者和接班人']}
def keys(l):
    ks = [l['title']] + aliases.get(l['id'], []) + [f for f in l['focus'] if f!='课外古诗词诵读']
    # Anthologies have overlapping titles; match their named works, not ambiguous generic headings.
    if l['title'] in ['短文两篇','短文二篇','散文二篇','散文诗二首','古代诗歌四首','古代诗歌五首','唐诗五首','诗词五首','词四首','诗词三首','诗词曲五首','短诗五首','唐诗三首']:
        ks = [f for f in l['focus'] if f!='课外古诗词诵读']
    return [norm(k) for k in ks]
allkeys = {l['id']: keys(l) for l in lessons}
def matches(part, l):
    p=norm(part)
    for k in allkeys[l['id']]:
        if not k or k not in p: continue
        # Avoid 春→春望/晚春; 月夜→月夜忆舍弟; 猫→熊猫; etc.
        if len(k)<=2:
            clean=re.sub(r'^\d+', '', p)
            clean=re.sub(r'^26上更新|^25下更新|^上册|^下册', '', clean)
            if not clean.startswith(k): continue
            if any(k!=other and k in other and other in p for ks in allkeys.values() for other in ks): continue
        return True
    return False

items=[]
explicit = {
 ('BV1rK4y1Y7RD',1):'7u-01',
 ('BV1eUAieoEZd',36):'7u-extra6-1', ('BV1eUAieoEZd',38):'7u-extra6-3',
 ('BV17M9qYrEee',36):'7d-extra6-2', ('BV17M9qYrEee',37):'7d-extra6-3',
 ('BV1YMXPYBEkw',43):'8u-extra6-1', ('BV1YMXPYBEkw',44):'8u-extra6-3',
 ('BV1YMXPYBEkw',45):'8u-extra6-2', ('BV1YMXPYBEkw',46):'8u-extra6-4',
 ('BV1mNdqY8EBG',7):'9u-07', ('BV1mNdqY8EBG',28):'9u-21',
 ('BV1mNdqY8EBG',33):'9u-extra6-3', ('BV137LizrE4S',22):'9d-extra3-2',
 ('BV137LizrE4S',24):'9d-extra3-4',
}
for path in sorted((ROOT/'scripts/resources').glob('BV*.json')):
    d=json.loads(path.read_text(encoding='utf-8'))
    if not d.get('pages') or '已注销' in d['owner']['name']: continue
    interview = d['owner']['name']=='教资小两口' or '试讲' in d['title'] or '面试' in d['title']
    for p in d['pages']:
        if p['duration']<90: continue
        for l in lessons:
            if not matches(p['part'],l) and explicit.get((d['bvid'],p['page']))!=l['id']: continue
            url=f"https://www.bilibili.com/video/{d['bvid']}/?p={p['page']}"
            items.append(dict(id=f"curated-{l['id']}-{d['bvid']}-{p['page']}", lessonID=l['id'],
                title=p['part'], kind='video', videoCID=p['cid'], body='',url=url,localFile='',source=d['owner']['name'],isPaid=False,
                category='面试讲解' if interview else '课堂示范',
                thumbnail=(p.get('first_frame') or d.get('pic','')).replace('http://','https://'),durationSeconds=p['duration'],
                checkedAt='2026-10-21', summary='教资、教招备课参考；按具体题目选取十分钟教学片段。' if interview else '观察讲解顺序、提问与课堂活动，常规课时不等于十分钟试讲。'))

# Prefer the interview teacher and recent lesson-specific videos; cap duplicate choices.
result=[]
for l in lessons:
    rs=[x for x in items if x['lessonID']==l['id']]
    rs.sort(key=lambda x:(x['source']!='教资小两口',x['category']!='面试讲解',x['id']))
    # Up to six useful parts per category, not hundreds of near-identical reposts.
    for category in ['面试讲解','课堂示范']:
        chosen=[]; names=set()
        for r in [x for x in rs if x['category']==category]:
            name=norm(r['title'])
            if name in names:continue
            names.add(name);chosen.append(r)
            if len(chosen)>=6:break
        result.extend(chosen)

notes={}
for line in (ROOT/'scripts/resources/lesson-notes.tsv').read_text(encoding='utf-8').splitlines():
    if not line.strip(): continue
    key,focus,question,board=line.split('|')
    assert key not in notes, key
    notes[key]=(focus,question,board)
for l in lessons:
    focus,question,board=notes.get(l['id'],notes.get(l['title'],(None,None,None)))
    assert focus, 'Missing authored guide: '+l['id']+' '+l['title']
    body=(f"备课切口\n{focus}\n\n学习目标\n能结合两处文本证据，解释本课选段的表达效果；能在交流后修正自己的理解。\n\n"
          f"主问题\n{question}\n\n十分钟练习安排\n"
          "0—1 分钟：用相关画面或生活问题导入，说明本次只解决一个主问题。\n"
          "1—2 分钟：学生朗读相关选段，圈出关键词，简要说出内容。\n"
          f"2—6 分钟：围绕上面的主问题，先独立圈画，再同桌交流；教师追问“哪一个词或细节支持你的理解？”\n"
          "6—8 分钟：比较两份回答，要求从“文本依据—表达方式—作用”三个方面补充，避免只报修辞名称。\n"
          "8—9 分钟：让学生用一句话概括收获，再用另一处文本验证。\n"
          f"9—10 分钟：小结并完成板书；作业为选段批注一处，写清依据和效果。\n\n板书参考\n{board}\n\n"
          "面试使用\n教资练习：按题目要求选择一个片段，准备对应答辩；教招练习：补充本班学情、教材分析与评价方式。不要在十分钟里讲完整篇或整组诗。\n\n"
          "欣语编写的备课提纲，用于设计与练习，不是逐字稿、官方答案或考点频率统计；请结合本校教材与实际面试题调整。")
    result.append(dict(id='curated-guide-'+l['id'],lessonID=l['id'],title='《'+l['title']+'》备课提纲 · 十分钟切口',
        kind='guide',body=body,url='',localFile='',source='欣语备课提纲',isPaid=False,category='备课提纲',checkedAt='2026-10-21',summary=focus))
base=json.loads((ROOT/'App/Resources/seed-resources.json').read_text(encoding='utf-8'))
for r in base:
    # Keep original locally readable drafts. Older link-only entries are superseded by checked parts.
    if r['body']:
        r['source']=r['source'].replace('小花园原创练习','欣语原创练习')
        result.append(r)
(ROOT/'App/Resources/library.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
missing=[l['id']+' '+l['title'] for l in lessons if not any(r['lessonID']==l['id'] and r['kind']=='video' for r in result)]
report={'checkedAt':'2026-10-21','resources':len(result),'lessonCount':len(lessons),'videoCovered':len(lessons)-len(missing),'videoCount':sum(r['kind']=='video' for r in result),'guideCount':sum(r['kind']=='guide' for r in result),'missingVideo':missing,
 'verification':'Public platform metadata (title, page, duration) checked; full videos not watched. Availability/login may change.'}
(ROOT/'docs/revision-002/coverage.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
