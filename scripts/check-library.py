"""Check shipped material coverage and exact part mapping against saved public metadata."""
import json
from pathlib import Path
from urllib.parse import urlparse,parse_qs
ROOT=Path(__file__).resolve().parents[1]
c=json.loads((ROOT/'App/Resources/catalog.json').read_text(encoding='utf-8'))
lessons={l['id']:l for b in c['books'] for u in b['units'] for l in u['lessons']}
rs=json.loads((ROOT/'App/Resources/library.json').read_text(encoding='utf-8'))
assert len({r['id'] for r in rs})==len(rs),'Duplicate resource ID'
metadata={p.stem:json.loads(p.read_text(encoding='utf-8')) for p in (ROOT/'scripts/resources').glob('BV*.json')}
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
    else: assert len(r['body'])>=100,r['id']
    assert 'baidu.com' not in r['url'] and '/search' not in r['url'],r['id']
for lid in lessons:
    own=[r for r in rs if r['lessonID']==lid]
    assert any(r['kind']=='video' for r in own),'Missing video '+lid
    assert any(r['id']=='curated-guide-'+lid and r['body'] for r in own),'Missing guide '+lid
print(f'PASS: {len(lessons)} lesson entries, {len(rs)} resources, direct video parts and offline guides covered.')
