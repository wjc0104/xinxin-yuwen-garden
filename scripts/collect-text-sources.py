"""Bounded, resumable public metadata collection. Article bodies exist only in memory.

python3 scripts/collect-text-sources.py --import-hints path/to/discovery.json
python3 scripts/collect-text-sources.py --discover-index
python3 scripts/collect-text-sources.py             # resume search + original-page checks
python3 scripts/collect-text-sources.py --offline   # rebuild metadata/report from saved evidence
Use --retry to explicitly retry cached failed searches/pages on a later date.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import html
import json
from pathlib import Path
import re
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urljoin, urlparse
from urllib.request import Request, urlopen

from text_source_rules import PUBLISHERS, ANTHOLOGIES, allowed_url, inspect_page, matches, keys, norm, Page, decode_page

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'scripts/resources'
OUTPUT = ROOT / 'docs/revision-005'
HEADERS = {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://www.bilibili.com/'}
DATE = datetime.now().astimezone().strftime('%Y-%m-%d')


def read(path, default):
    return json.loads(path.read_text(encoding='utf-8')) if path.exists() else default


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temporary.replace(path)


def fetch(url, delay):
    time.sleep(delay)
    # No credentials, cookies, proxy/reader bypass or secret request diagnostics.
    with urlopen(Request(url, headers=HEADERS), timeout=18) as response:
        data = response.read(3_000_001)
        if len(data) > 3_000_000:
            raise ValueError('page-too-large')
        return data, response.url, response.headers.get('Content-Type', '')


def add_candidate(candidates, title, url, lessons, origin, explicit=None, author=''):
    if not allowed_url(url):
        return
    classical = urlparse(url).hostname == 'www.gushiwen.cn'
    ids = [l['id'] for l in lessons if (not explicit or l['id'] == explicit)
           and (matches(title, l, exact_work=classical) or
                (classical and any(norm(title) == norm(re.split(r'[（(·]', k)[0]) for k in keys(l))) or
                (explicit and matches(title, l, exact_work=True)) or
                (explicit and l['title'] in ANTHOLOGIES and norm(l['title']) in norm(title)))]
    for lid in ids:
        if not any(c['url'] == url and c['lessonID'] == lid for c in candidates):
            candidates.append(dict(lessonID=lid, title=title, url=url, discoveredBy=origin, author=author))


def collect(args):
    lessons = [l for b in read(ROOT / 'App/Resources/catalog.json', {})['books'] for u in b['units'] for l in u['lessons']]
    by_id = {l['id']: l for l in lessons}
    candidates_path = DATA / 'text-source-candidates.json'
    evidence_path = DATA / 'text-source-checks.json'
    searches_path = DATA / 'text-source-searches.json'
    candidates = read(candidates_path, [])
    evidence = read(evidence_path, {})
    searches = read(searches_path, {})
    for hint in args.import_hints:
        rows = read(Path(hint), [])
        if isinstance(rows, dict):
            rows = rows['results']
        for row in rows:
            add_candidate(candidates, row.get('title', ''), row.get('url', ''), lessons,
                          'publisher-discovery', row.get('lessonID'))
    if args.discover_index and not args.offline:
        raw, final, ct = fetch('https://www.gushiwen.cn/gushi/chuzhong.aspx', args.delay)
        markup, _ = decode_page(raw, ct)
        page = Page(markup)
        for anchor in page.elements('a'):
            url = urljoin(final, anchor.attrs.get('href', ''))
            add_candidate(candidates, anchor.text().strip(), url, lessons, 'publisher-index')
        write(OUTPUT / 'index-check.json', dict(url='https://www.gushiwen.cn/gushi/chuzhong.aspx',
              finalURL=final, checkedAt=DATE, status='http-200', candidateCount=len(candidates)))
    write(candidates_path, candidates)

    # One genuine query per catalog entry, at most one page. Three consecutive blocks trip a circuit.
    blocked = 0
    attempted = 0
    if not args.offline:
        for lesson in lessons:
            lid = lesson['id']
            previous = searches.get(lid)
            if previous and (not args.retry or previous['status'] in {'searched', 'no-match'}):
                continue
            if attempted >= args.search_limit or blocked >= 3:
                break
            query = lesson['title'] + ' 语文 试讲 教学设计'
            url = 'https://api.bilibili.com/x/web-interface/search/type?' + urlencode(dict(search_type='article', keyword=query, page=1))
            attempted += 1
            state = dict(query=query, checkedAt=DATE, status='error', resultCount=0, matchingCount=0)
            try:
                data, _, _ = fetch(url, max(1.0, args.delay))
                payload = json.loads(data)
                if payload.get('code') != 0:
                    state.update(status='blocked', apiCode=payload.get('code'))
                    blocked += 1
                else:
                    rows = payload.get('data', {}).get('result') or []
                    if not isinstance(rows, list):
                        raise ValueError('invalid-search-result')
                    state['resultCount'] = len(rows)
                    for row in rows:
                        title = html.unescape(re.sub(r'<[^>]*>', '', row.get('title', '')))[:500].strip()
                        author = html.unescape(re.sub(r'<[^>]*>', '', row.get('author', '')))[:200].strip()
                        cv = row.get('id')
                        if type(cv) is int and cv > 0 and author and matches(title, lesson, author):
                            add_candidate(candidates, title, f'https://www.bilibili.com/read/cv{cv}',
                                          lessons, 'bilibili-article-search', explicit=lid, author=author)
                            state['matchingCount'] += 1
                    state['status'] = 'searched' if state['matchingCount'] else 'no-match'
                    blocked = 0
            except HTTPError as error:
                state.update(status='blocked' if error.code in {403, 412, 429} else 'error', http=error.code)
                blocked += 1
            except (URLError, TimeoutError, ValueError, OSError):
                state['status'] = 'error'
                blocked += 1
            searches[lid] = state
            write(searches_path, searches)
            write(candidates_path, candidates)
            print('search', lid, state['status'], flush=True)

        # Validate each unique URL once; cache metadata, never article markup or body.
        bili_original_blocks = 0
        for url in dict.fromkeys(c['url'] for c in candidates):
            if urlparse(url).hostname == 'www.bilibili.com' and bili_original_blocks >= 3:
                continue
            previous = evidence.get(url)
            recheck = (getattr(args, 'recheck_unreadable_publishers', False) and
                       urlparse(url).hostname != 'www.bilibili.com' and
                       previous and (previous['status'] == 'no-readable-body' or
                       previous.get('pageTitle') in {'分享到', '分享', '华图教育', '全部资讯'}))
            if previous and not recheck and (not args.retry or previous['status'] == 'readable'):
                continue
            state = dict(checkedAt=DATE, status='error')
            try:
                data, final, ct = fetch(url, args.delay)
                host = urlparse(url).hostname
                # Bili's own cv→opus redirect is accepted as transport only; shipped identity remains cv.
                safe_final = allowed_url(final) or (host == 'www.bilibili.com' and
                    re.fullmatch(r'https://www\.bilibili\.com/opus/[1-9]\d*', final) is not None)
                state.update(http=200, finalURL=final)
                if not safe_final:
                    state['status'] = 'unapproved-redirect'
                else:
                    details, page = inspect_page(data, host, ct)
                    body = norm(page.content(host))
                    # A generic anthology heading is safe only when its real named works are in
                    # the article body. The evidence saves IDs, never the copyrighted paragraphs.
                    details['anthologyMatches'] = [l['id'] for l in lessons if l['title'] in ANTHOLOGIES
                        and norm(l['title']) in norm(details['pageTitle'])
                        and keys(l) and all(norm(key) in body for key in keys(l))]
                    # This original page omits the selection number in its heading. Verify
                    # the exact fifth poem by its author and first line, never by dropping 其五.
                    if (url == 'https://www.gushiwen.cn/shiwenv_9b06cd24ed3a.aspx' and
                        '莫言下岭便无难' in body and '杨万里' in page.root.text()):
                        details['workMatches'] = ['7d-extra6-3']
                    state.update(details)
                    state['status'] = 'readable' if details['meaningful'] else 'no-readable-body'
            except HTTPError as error:
                state.update(status='blocked' if error.code in {403, 412, 429} else 'http-error', http=error.code)
            except (URLError, TimeoutError, ValueError, OSError, UnicodeError, LookupError):
                state['status'] = 'fetch-or-decode-error'
            evidence[url] = state
            if urlparse(url).hostname == 'www.bilibili.com':
                bili_original_blocks = bili_original_blocks + 1 if state['status'] == 'blocked' else 0
            write(evidence_path, evidence)
            print('original', len(evidence), state['status'], url, flush=True)

    resources = []
    for candidate in candidates:
        state = evidence.get(candidate['url'], {})
        lid = candidate['lessonID']
        classical = urlparse(candidate['url']).hostname == 'www.gushiwen.cn'
        if state.get('status') != 'readable' or not (matches(state['pageTitle'], by_id[lid],
                context=candidate.get('author', ''), exact_work=classical) or
                lid in state.get('anthologyMatches', []) or lid in state.get('workMatches', [])):
            continue
        host = urlparse(candidate['url']).hostname
        digest = hashlib.sha256(candidate['url'].encode()).hexdigest()[:16]
        category = '课文解读' if classical else state['category']
        summary = '原站公开正文已抽查；未逐篇审定教学质量，阅读与选区以原站为准。'
        if classical:
            summary = '原文、译注或赏析；供理解作品，不是试讲稿。'
        elif category == '教学设计' and '试讲' in state['pageTitle']:
            summary = '原题标为试讲；正文为教学流程参考，不计为逐字试讲稿。'
        paid_download = host == 'zy.21cnjy.com'
        if paid_download:
            summary += ' 原站文件下载可能付费；仅计已核实可读的网页正文。'
        resources.append(dict(id=f'curated-text-{lid}-{digest}', lessonID=lid, title=state['pageTitle'],
            kind='script' if category == '试讲稿' else 'link', body='', url=candidate['url'], localFile='',
            source=(candidate.get('author') + ' · ' if candidate.get('author') else '') + PUBLISHERS[host][0] + ' · 原文署名见页面' + (' · 文件下载可能付费' if paid_download else ''), isPaid=paid_download, category=category,
            checkedAt=state['checkedAt'], summary=summary))
    resources.sort(key=lambda r: (r['lessonID'], r['category'], r['url']))
    write(DATA / 'text-sources.json', resources)
    rows = []
    for lesson in lessons:
        own = [r for r in resources if r['lessonID'] == lesson['id']]
        categories = sorted(set(r['category'] for r in own))
        rows.append(dict(lessonID=lesson['id'], title=lesson['title'], publicTextCount=len(own),
            categories=categories, trialScriptCount=sum(r['kind'] == 'script' for r in own),
            bilibiliSearch=searches.get(lesson['id'], {'status': 'unsearched'}),
            originalChecks=[dict(url=c['url'], status=evidence.get(c['url'], {}).get('status', 'unchecked'))
                            for c in candidates if c['lessonID'] == lesson['id']],
            missing='未找到已核实可读的外部文字' if not own else ('未找到已核实的试讲稿' if '试讲稿' not in categories else '')))
    report = dict(checkedAt=DATE, lessonCount=len(lessons), publicTextCount=len(resources),
        publicTextCovered=sum(bool(r['publicTextCount']) for r in rows),
        trialScriptCovered=sum(bool(r['trialScriptCount']) for r in rows),
        categoryCounts={k: sum(r['category'] == k for r in resources) for k in sorted(set(r['category'] for r in resources))},
        bilibiliSearchCounts={s: sum(r['bilibiliSearch']['status'] == s for r in rows)
                              for s in ['searched', 'no-match', 'blocked', 'error', 'unsearched']},
        missingPublicText=[dict(lessonID=r['lessonID'],title=r['title']) for r in rows if not r['publicTextCount']],
        missingTrialScripts=[dict(lessonID=r['lessonID'],title=r['title']) for r in rows if not r['trialScriptCount']],
        verification='Original public HTTP/content/title checks, not full pedagogical review. Metadata only; no copyrighted bodies shipped. Search blocks and unsearched lessons are not no-match.',
        lessons=rows)
    write(OUTPUT / 'text-coverage.json', report)
    lines = ['# 外部文字覆盖', '', f'核对日期：{DATE}。{len(lessons)} 个目录条目中，{report["publicTextCovered"]} 个含已核实可读的外部文字，{report["trialScriptCovered"]} 个含试讲稿。',
             '仅保存标题、来源和原文链接；不分发全文，未逐篇审定教学质量。未找到不等于不存在。', '',
             '| 课文 | 可读文字数 | 分类 | 缺项 | B站搜索 |', '| --- | ---: | --- | --- | --- |']
    lines += [f'| {r["lessonID"]} {r["title"]} | {r["publicTextCount"]} | {"、".join(r["categories"]) or "—"} | {r["missing"] or "—"} | {r["bilibiliSearch"]["status"]} |' for r in rows]
    (OUTPUT / 'text-coverage.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k not in {'lessons','missingPublicText','missingTrialScripts'}}, ensure_ascii=True))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--import-hints', action='append', default=[])
    parser.add_argument('--discover-index', action='store_true')
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--retry', action='store_true')
    parser.add_argument('--recheck-unreadable-publishers', action='store_true',
                        help='recheck non-Bili pages after article-container rule updates')
    parser.add_argument('--delay', type=float, default=0.5)
    parser.add_argument('--search-limit', type=int, default=198)
    args = parser.parse_args()
    if args.delay < 0.25 or not 0 <= args.search_limit <= 198:
        parser.error('delay >= 0.25 seconds; search-limit 0...198')
    collect(args)
