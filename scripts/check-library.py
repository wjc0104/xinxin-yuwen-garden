"""Check shipped material coverage and exact part mapping against saved public metadata."""
import json
from pathlib import Path
from urllib.parse import urlparse,parse_qs
from text_source_rules import allowed_url,matches
ROOT=Path(__file__).resolve().parents[1]
c=json.loads((ROOT/'App/Resources/catalog.json').read_text(encoding='utf-8'))
lessons={l['id']:l for b in c['books'] for u in b['units'] for l in u['lessons']}
rs=json.loads((ROOT/'App/Resources/library.json').read_text(encoding='utf-8'))
assert len({r['id'] for r in rs})==len(rs),'Duplicate resource ID'
metadata={p.stem:json.loads(p.read_text(encoding='utf-8')) for p in (ROOT/'scripts/resources').glob('BV*.json')}
texts=json.loads((ROOT/'scripts/resources/text-sources.json').read_text(encoding='utf-8'))
text_by_id={r['id']:r for r in texts}
checks=json.loads((ROOT/'scripts/resources/text-source-checks.json').read_text(encoding='utf-8'))
assert len(text_by_id)==len(texts),'Duplicate text metadata ID'
assert {r['id'] for r in rs if r['id'].startswith('curated-text-')}==set(text_by_id),'Text metadata/library drift'
for r in rs:
    assert r['lessonID'] in lessons,r['id']
    assert r['title'] and r['source'],r['id']
    if r['kind']=='video':
        u=urlparse(r['url']);assert u.scheme=='https' and u.hostname=='www.bilibili.com',r['url']
        bv=u.path.split('/')[2];page=int(parse_qs(u.query)['p'][0])
        part=next(p for p in metadata[bv]['pages'] if p['page']==page)
        assert r['title']==part['part'] and r['durationSeconds']==part['duration'],r['id']
        assert r.get('videoCID') == part['cid'] and r['videoCID'] > 0,r['id']
        assert r['durationSeconds']>=90 and r['checkedAt'],r['id']
    elif r['id'] in text_by_id:
        assert r==text_by_id[r['id']],r['id']
        assert allowed_url(r['url']),r['url']
        assert r['kind'] in {'link','script'} and r['body']=='' and r['localFile']=='',r['id']
        assert r['isPaid']==(urlparse(r['url']).hostname=='zy.21cnjy.com'),r['id']
        assert set(r)<=set('id lessonID title kind body url localFile source isPaid category checkedAt summary'.split()),r['id']
        state=checks[r['url']]
        assert state['status']=='readable' and state['http']==200 and state['meaningful'],r['id']
        assert state['contentChars']>=200 and state['pageTitle']==r['title'] and state['checkedAt']==r['checkedAt'],r['id']
        expected_category='课文解读' if urlparse(r['url']).hostname=='www.gushiwen.cn' else state['category']
        assert r['category']==expected_category,r['id']
        assert (matches(r['title'],lessons[r['lessonID']],context=r['source'],
                       exact_work=urlparse(r['url']).hostname=='www.gushiwen.cn') or
                r['lessonID'] in state.get('anthologyMatches',[]) or
                r['lessonID'] in state.get('workMatches',[])),r['id']
        if r['kind']=='script':
            assert r['category']=='试讲稿' and state['dialogueCount']>=3 and state.get('dialogueRule')=='nonoverlapping-v2' and state.get('scriptEnding'),r['id']
        else:assert r['category']!='试讲稿',r['id']
    else: assert len(r['body'])>=100,r['id']
    assert 'baidu.com' not in r['url'] and '/search' not in r['url'],r['id']
for lid in lessons:
    own=[r for r in rs if r['lessonID']==lid]
    assert any(r['kind']=='video' for r in own),'Missing video '+lid
    assert any(r['id']=='curated-guide-'+lid and r['body'] for r in own),'Missing guide '+lid
coverage=json.loads((ROOT/'docs/revision-005/text-coverage.json').read_text(encoding='utf-8'))
assert {r['lessonID'] for r in coverage['lessons']}==set(lessons),'Incomplete text coverage audit'
for row in coverage['lessons']:
    own=[r for r in texts if r['lessonID']==row['lessonID']]
    assert row['publicTextCount']==len(own) and row['categories']==sorted({r['category'] for r in own}),row['lessonID']
    assert row['trialScriptCount']==sum(r['kind']=='script' for r in own),row['lessonID']
    assert bool(row['missing'])==(not own or not any(r['kind']=='script' for r in own)),row['lessonID']
assert coverage['publicTextCount']==len(texts)
assert coverage['publicTextCovered']==len({r['lessonID'] for r in texts})
assert {r['lessonID'] for r in texts}==set(lessons),'Missing externally readable text (offline outlines do not count)'
assert coverage['trialScriptCovered']==len({r['lessonID'] for r in texts if r['kind']=='script'})
assert len([r for r in rs if not r['id'].startswith('curated-text-')])==827,'Existing resource IDs/count changed'
print(f'PASS: {len(lessons)} lesson entries, {len(rs)} resources; video parts, 198 offline outlines and {len(texts)} validated direct public texts ({coverage["publicTextCovered"]} lesson entries).')
