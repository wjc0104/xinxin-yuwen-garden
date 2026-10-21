"""Offline regressions for source allowlisting, semantic validation and blocked search accounting."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from urllib.error import HTTPError

from text_source_rules import allowed_url, inspect_page, matches


class SourceRulesTests(unittest.TestCase):
    def test_direct_original_allowlist_rejects_unsafe_and_search_urls(self):
        self.assertTrue(allowed_url('https://www.gushiwen.cn/shiwenv_04c121ce6a85.aspx'))
        self.assertTrue(allowed_url('https://www.ruiwen.com/wenxue/zhuziqing/998109.html'))
        for url in ['http://www.gushiwen.cn/shiwenv_04c121ce6a85.aspx',
                    'https://www.gushiwen.cn.evil.test/shiwenv_04c121ce6a85.aspx',
                    'https://user@www.gushiwen.cn/shiwenv_04c121ce6a85.aspx',
                    'https://www.gushiwen.cn:443/shiwenv_04c121ce6a85.aspx',
                    'https://www.gushiwen.cn/search.aspx?value=南安军',
                    'https://www.ruiwen.com/wenxue/zhuziqing/998109.html?redirect=other',
                    'https://www.bilibili.com/read/cv0', 'https://www.bilibili.com/read/cv123/other']:
            with self.subTest(url=url):
                self.assertFalse(allowed_url(url))

    def test_short_titles_and_actual_anthology_constituents(self):
        spring = dict(id='7u-01', title='春', author='朱自清', focus=[])
        self.assertTrue(matches('朱自清《春》教学设计', spring))
        self.assertFalse(matches('《春望》教学设计', spring))
        self.assertFalse(matches('晚春赏析', spring))
        self.assertFalse(matches('青春演讲', spring))
        group = dict(id='7u-04', title='古代诗歌四首', author='曹操等', focus=['观沧海', '次北固山下'])
        self.assertTrue(matches('次北固山下', group, exact_work=True))
        self.assertFalse(matches('古代诗歌四首', group, exact_work=True))
        group = dict(id='8d-21', title='《庄子》二则', focus=['北冥有鱼', '庄子与惠子游于濠梁之上'])
        self.assertTrue(matches('北冥有鱼', group, exact_work=True))
        ci = dict(id='8u-extra6-1', title='浣溪沙（一曲新词酒一杯）', author='晏殊', focus=[])
        self.assertTrue(matches('浣溪沙·一曲新词酒一杯', ci, exact_work=True))
        self.assertFalse(matches('浣溪沙·一上高城万里愁', ci, exact_work=True))
        self.assertFalse(matches('浣溪沙·身向云山那畔行', ci, exact_work=True))

    def test_gb2312_is_decoded_without_losing_lesson_title(self):
        markup = '<meta charset="gb2312"><h1>朱自清《春》教学设计</h1><div class="content">教学目标 教学过程 ' + '课文分析' * 200 + '</div>'
        evidence, _ = inspect_page(markup.encode('gb18030'), 'www.ruiwen.com')
        self.assertEqual(evidence['pageTitle'], '朱自清《春》教学设计')
        self.assertEqual(evidence['encoding'], 'gb18030')
        self.assertTrue(evidence['meaningful'])
        self.assertNotIn('body', evidence)

    def test_http_200_shell_and_navigation_are_not_readable(self):
        markup = '<title>《春》试讲稿</title><nav>' + '教学目标 教学过程 同学们 ' * 100 + '</nav><script>content="copyrighted"</script>'
        evidence, _ = inspect_page(markup.encode(), 'www.bilibili.com')
        self.assertFalse(evidence['meaningful'])
        self.assertEqual(evidence['contentChars'], 0)

    def test_mobile_menu_h1_and_conflicting_charset_do_not_hide_article(self):
        markup = '<meta charset="gb2312"><title>《春》教学设计</title><h1>分享到</h1><h1>全部资讯</h1><div class="mainWords">教学目标 教学过程 ' + '课文分析' * 200 + '</div>'
        evidence, _ = inspect_page(markup.encode('utf-8'), 'ah.huatu.com', 'text/html; charset=UTF-8')
        self.assertEqual(evidence['pageTitle'], '《春》教学设计')
        self.assertEqual(evidence['encoding'], 'utf-8')
        self.assertTrue(evidence['meaningful'])

    def test_title_says_trial_but_outline_is_design(self):
        markup = '<h1>《济南的冬天》试讲稿</h1><div class="artBcon">教学目标 教学过程 导入 板书 ' + '流程参考' * 200 + '</div>'
        evidence, _ = inspect_page(markup.encode(), 'bj.huatu.com')
        self.assertTrue(evidence['meaningful'])
        self.assertEqual(evidence['category'], '教学设计')

    def test_trial_dialogue_and_speaking_plan_are_distinct(self):
        for title, expected in [('《济南的冬天》试讲稿', '试讲稿'), ('《济南的冬天》说课稿', '说课稿')]:
            markup = f'<h1>{title}</h1><div class="artBcon">教学过程 ' + '师：同学们请朗读。生：好的。' * 70 + '板书 小结 作业：练习。</div>'
            evidence, _ = inspect_page(markup.encode(), 'bj.huatu.com')
            self.assertTrue(evidence['meaningful'])
            self.assertEqual(evidence['category'], expected)

    def test_dialogue_preview_is_not_a_complete_script(self):
        start = '<title>《春》试讲稿</title><div class="artBcon">教学过程 '
        dialogue = '师：同学们请朗读。生：好的。' * 70
        evidence, _ = inspect_page((start + dialogue + '</div>').encode(), 'bj.huatu.com')
        self.assertEqual(evidence['category'], '教学设计')
        evidence, _ = inspect_page((start + dialogue + '小结 作业 登录后查看全文</div>').encode(), 'bj.huatu.com')
        self.assertFalse(evidence['meaningful'])
        self.assertTrue(evidence['readingLimited'])

    def test_block_circuit_records_unsearched_and_resume_does_not_wipe(self):
        spec = importlib.util.spec_from_file_location('collector', Path(__file__).with_name('collect-text-sources.py'))
        collector = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(collector)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            collector.ROOT = root
            collector.DATA = root / 'scripts/resources'
            collector.OUTPUT = root / 'docs/revision-005'
            lessons = [dict(id=f'lesson-{i}', title=f'课文{i}', author='', focus=[]) for i in range(5)]
            collector.write(root / 'App/Resources/catalog.json', dict(books=[dict(units=[dict(lessons=lessons)])]))
            calls = []
            def blocked(url, delay):
                calls.append(url)
                raise HTTPError(url, 412, 'blocked', {}, None)
            collector.fetch = blocked
            args = SimpleNamespace(import_hints=[], discover_index=False, offline=False, retry=False, delay=.5, search_limit=198)
            with contextlib.redirect_stdout(io.StringIO()):
                collector.collect(args)
            report = collector.read(collector.OUTPUT / 'text-coverage.json', {})
            self.assertEqual(len(calls), 3)
            self.assertEqual(report['bilibiliSearchCounts']['blocked'], 3)
            self.assertEqual(report['bilibiliSearchCounts']['unsearched'], 2)
            self.assertEqual(report['publicTextCovered'], 0)
            self.assertTrue(all(row['missing'] for row in report['lessons']))
            args.offline = True
            with contextlib.redirect_stdout(io.StringIO()):
                collector.collect(args)
            self.assertEqual(collector.read(collector.OUTPUT / 'text-coverage.json', {}), report)
            self.assertEqual(len(calls), 3)

    def test_same_anthology_heading_requires_real_constituents(self):
        spec = importlib.util.spec_from_file_location('collector', Path(__file__).with_name('collect-text-sources.py'))
        collector = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(collector)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            collector.ROOT = root
            collector.DATA = root / 'scripts/resources'
            collector.OUTPUT = root / 'docs/revision-005'
            lessons = [dict(id='7d-17', title='短文两篇', author='', focus=['陋室铭', '爱莲说']),
                       dict(id='9d-13', title='短文两篇', author='', focus=['谈读书', '不求甚解'])]
            collector.write(root / 'App/Resources/catalog.json', dict(books=[dict(units=[dict(lessons=lessons)])]))
            url = 'https://www.chinajiaoan.cn/doc/12345.html'
            hints = [dict(lessonID=l['id'], title='《短文两篇》教学设计', url=url) for l in lessons]
            collector.write(root / 'hints.json', hints)
            markup = '<title>《短文两篇》教学设计</title><article class="article-content">教学目标 教学过程 陋室铭 爱莲说 ' + '课堂分析' * 200 + '</article>'
            collector.fetch = lambda url, delay: (markup.encode(), url, 'text/html; charset=UTF-8')
            args = SimpleNamespace(import_hints=[str(root / 'hints.json')], discover_index=False, offline=False,
                                   retry=False, delay=.5, search_limit=0)
            with contextlib.redirect_stdout(io.StringIO()):
                collector.collect(args)
            resources = collector.read(collector.DATA / 'text-sources.json', [])
            self.assertEqual([r['lessonID'] for r in resources], ['7d-17'])
            evidence = collector.read(collector.DATA / 'text-source-checks.json', {})[url]
            self.assertEqual(evidence['anthologyMatches'], ['7d-17'])
            self.assertNotIn('body', evidence)


if __name__ == '__main__':
    unittest.main()
