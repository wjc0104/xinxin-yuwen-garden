import json
from pathlib import Path
data=json.loads(Path('App/Resources/catalog.json').read_text(encoding='utf-8'))
assert [b['id'] for b in data['books']]==['7u','7d','8u','8d','9u','9d']
ids=[]
for b,count in zip(data['books'],[24,25,26,24,27,24]):
    lessons=[l for u in b['units'] for l in u['lessons']]
    assert [l['number'] for l in lessons if l['number']>0]==list(range(1,count+1)),b['id']
    assert b['source'].startswith('https://book.pep.com.cn/')
    ids.extend(l['id'] for l in lessons)
assert len(ids)==len(set(ids))
assert '待更新' in data['books'][-1]['verification']
assert any(l['title']=='谈骨气' for u in data['books'][4]['units'] for l in u['lessons'])
print(f'Catalog verified: 6 books, {len(ids)} lesson and recitation entries; sequential main lessons, unique IDs, official sources.')
