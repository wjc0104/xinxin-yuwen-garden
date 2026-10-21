"""Shared, conservative rules for public text metadata (never persist article bodies)."""
import html
import re
from html.parser import HTMLParser
from urllib.parse import urlparse

# Exact host + whole direct-article path. No suffix trust, search pages, credentials or queries.
PUBLISHERS = {
    'www.gushiwen.cn': ('古文岛', r'/shiwenv_[0-9a-f]{12}\.aspx'),
    'www.ruiwen.com': ('瑞文网', r'/(?:wenxue/[a-z]+|[a-z]+)/\d+\.html'),
    'bj.huatu.com': ('北京华图教育', r'/\d{4}/\d{4}/\d+\.html'),
    'm.ah.huatu.com': ('安徽华图教育', r'/\d{4}/\d{4}/\d+\.html'),
    'ah.huatu.com': ('安徽华图教育', r'/\d{4}/\d{4}/\d+\.html'),
    'fj.huatu.com': ('福建华图教育', r'/\d{4}/\d{4}/\d+\.html'),
    'sd.huatu.com': ('山东华图教育', r'/\d{4}/\d{4}/\d+\.html'),
    'm.sd.huatu.com': ('山东华图教育', r'/\d{4}/\d{4}/\d+\.html'),
    'm.gd.huatu.com': ('广东华图教育', r'/jsks/\d{4}/\d{4}/\d+\.html'),
    'm.he.huatu.com': ('河北华图教育', r'/\d{4}/\d{4}/\d+\.html'),
    'm.hb.huatu.com': ('湖北华图教育', r'/jiaoshi/\d+\.html'),
    'm.fj.huatu.com': ('福建华图教育', r'/\d{4}/\d{4}/\d+\.html'),
    'www.hqwx.com': ('环球网校', r'/jszg-kaoshi/news/\d+\.html'),
    'm.hqwx.com': ('环球网校', r'/jszg-kaoshi/news/\d+\.html'),
    'www.qiqishangan.com': ('齐岸教育', r'/web/detail/show/\d+\.html'),
    'm.shanxiangjiaoyu.com': ('山香教育', r'/zixun/\d{8}/\d+\.html'),
    'www.shanxiangjiaoyu.com': ('山香教育', r'/zixun/\d{8}/\d+(?:\.html)?'),
    'm.ygteacher.com': ('易公教育', r'/article/[0-9a-f]{32}\.html'),
    'www.86yw.com': ('语文备课大师', r'/html/\d+\.html'),
    'www.yeyulingfeng.com': ('夜雨聆风学习网', r'/(?:a|wendang)/\d+\.html'),
    'www.abcjiaoyu.com': ('ABC教育资源网', r'/ziyuan/\d+\.html'),
    'www.kaoke.com': ('考客网', r'/(?:xuexi/chuzhongyuwen|jiaoxue/jiaoxuesheji)/\d+\.html'),
    'www.yuwenmi.com': ('语文迷', r'/(?:jiaoxuesheji|jiaoan/[a-z]+|kebiao/[a-z0-9]+|yuwenban/[a-z0-9]+)/\d+\.html'),
    'www.chinajiaoan.cn': ('快思教案网', r'/doc/\d+\.html'),
    'm.koolearn.com': ('新东方在线', r'/(?:jiaoshi|zhongkao)/\d{8}/\d+\.html'),
    'zhongkao.koolearn.com': ('新东方在线', r'/\d{8}/\d+\.html'),
    'www.yjbys.com': ('应届毕业生网', r'/(?:wenxue/[a-z]+|kaoshi/jiaoxuesheji)/\d+\.html'),
    'zy.21cnjy.com': ('21世纪教育网', r'/[1-9]\d*'),
    'www.sohu.com': ('搜狐号原文', r'/a/\d+_\d+/?'),
    'm.sohu.com': ('搜狐号原文', r'/a/\d+_\d+/?'),
    'www.233.com': ('233网校', r'/teacher/(?:[a-z]+/){1,2}\d{6,8}/\d+\.html'),
    'www.jiajiaoban.com': ('北京爱智康', r'/e/\d{8}/[a-z0-9]+\.shtml'),
    'www.daowen.com': ('导文网', r'/jiaoan/\d+\.html'),
    'xiaoxue.ruiwen.com': ('瑞文网', r'/(?:jiaoan|jiaoxuesheji)/\d+\.html'),
    'www.shouyihuo.com': ('手艺活教案', r'/jiaoan/\d+\.html'),
    'www.gerenjianli.cn': ('个人简历网教案', r'/jiaoxue/jiaoan/\d+\.html'),
    'www.bilibili.com': ('B站专栏', r'/read/cv[1-9]\d*/?'),
}


def allowed_url(raw):
    try:
        u = urlparse(raw)
        return (u.scheme == 'https' and u.hostname in PUBLISHERS and not u.username
                and not u.password and u.port is None and not u.query and not u.fragment
                and re.fullmatch(PUBLISHERS[u.hostname][1], u.path) is not None)
    except ValueError:
        return False


def norm(value):
    return re.sub(r'[^\u4e00-\u9fffA-Za-z0-9]', '', value).lower()


def work_name(value):
    # A ci tune is not a unique work: retain its parenthesized first line/number.
    return norm(value.replace('（节选）', '').replace('(节选)', '').split('——')[0])


ALIASES = {'7d-02': ['说和做'], '8u-04': ['飞天凌空'], '8u-05': ['一着惊海天'],
           '9u-05': ['你是人间的四月天'], '8u-21': ['人民英雄永垂不朽'],
           '7d-extra3-4': ['晚春二首·其一'], '7d-extra6-3': ['过松源晨炊漆公店六首·其五'],
           '9u-extra6-2': ['无题·相见时难别亦难']}
ANTHOLOGIES = {'短文两篇', '短文二篇', '散文二篇', '散文诗二首', '古代诗歌四首', '古代诗歌五首',
               '唐诗五首', '诗词五首', '词四首', '诗词三首', '诗词曲五首', '短诗五首', '唐诗三首',
               '《世说新语》二则', '《孟子》三章', '《诗经》二首', '《庄子》二则', '《礼记》二则',
               '消息二则', '阿西莫夫短文两篇', '寓言四则'}


def keys(lesson):
    titles = lesson['focus'] if lesson['title'] in ANTHOLOGIES else [lesson['title']] + ALIASES.get(lesson['id'], [])
    return [t.replace('（节选）', '').replace('(节选)', '').split('——')[0]
            for t in titles if t != '课外古诗词诵读']


def matches(title, lesson, context='', exact_work=False):
    for key in keys(lesson):
        if exact_work:
            if work_name(title) == work_name(key):
                return True
        elif len(norm(key)) > 2:
            if norm(key) in norm(title):
                return True
        else:
            whole = re.search(r'(^|[^\u4e00-\u9fffA-Za-z])' + re.escape(key) + r'($|[^\u4e00-\u9fffA-Za-z])', title)
            teaching = any(t in title + context for t in ['语文', '教学', '教案', '试讲', '说课', '课文', '课堂', '初中'])
            author = bool(lesson.get('author')) and lesson['author'] in title + context
            if whole and (teaching or author):
                return True
    return False


class Node:
    def __init__(self, tag='', attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []

    def text(self):
        if self.tag in {'script', 'style', 'noscript', 'nav', 'footer'}:
            return ''
        return ' '.join(c if isinstance(c, str) else c.text() for c in self.children)

    def find(self, predicate):
        return ([self] if predicate(self) else []) + [n for c in self.children if isinstance(c, Node) for n in c.find(predicate)]


class Page(HTMLParser):
    def __init__(self, markup):
        super().__init__(convert_charrefs=True)
        self.root = Node()
        self.stack = [self.root]
        self.feed(markup)

    def handle_starttag(self, tag, attrs):
        n = Node(tag, attrs)
        self.stack[-1].children.append(n)
        if tag not in {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'}:
            self.stack.append(n)

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                self.stack = self.stack[:i]
                break

    def handle_data(self, data):
        self.stack[-1].children.append(data)

    def elements(self, tag):
        return self.root.find(lambda n: n.tag == tag)

    def content(self, host):
        # Known article containers only. Never count navigation/related-link text as readable content.
        selectors = (['contson', 'contyishang'] if host == 'www.gushiwen.cn' else
                     ['content'] if host == 'www.ruiwen.com' else
                     ['opus-module-content', 'article-holder'] if host == 'www.bilibili.com' else
                     ['artBcon', 'article-content', 'article_content', 'articleCon', 'news-content',
                      'news_content', 'detail-content', 'detail_content', 'TRS_Editor', 'con', 'content', 'Article', 'nr'])
        if host.endswith('.huatu.com'):
            selectors += ['mainWords', 'detail-cnt']
        if host in {'www.hqwx.com', 'm.hqwx.com'}:
            selectors = ['block-content', 'news_content']
        if host == 'www.yeyulingfeng.com':
            selectors = ['article-rich-content', 'document-text-scroll']
        if host == 'www.abcjiaoyu.com':
            selectors = ['PnContentDes']
        if host == 'zy.21cnjy.com':
            selectors = ['entry-content']
        if host in {'www.sohu.com', 'm.sohu.com'}:
            selectors = ['mp-editor', 'article']
        if host in {'www.shanxiangjiaoyu.com', 'm.shanxiangjiaoyu.com'}:
            selectors = ['nc_con']
        if host == 'www.jiajiaoban.com':
            selectors = ['centLt']
        if host == 'www.daowen.com':
            selectors = ['content_reload']
        nodes = self.root.find(lambda n: n.tag in {'div', 'article', 'section'} and
                               any(s in n.attrs.get('class', '').split() or s == n.attrs.get('id') for s in selectors))
        if host in {'www.gushiwen.cn', 'www.daowen.com'}:
            return '\n'.join(n.text() for n in nodes)
        return max((n.text() for n in nodes), key=len, default='')


def decode_page(data, content_type=''):
    # Some publishers include a stale GB2312 meta in otherwise UTF-8 pages. Strict
    # UTF-8 first, then declared encodings; never silently replace Chinese characters.
    declared = re.findall(br'charset\s*=\s*["\x27]?([\w-]+)', data[:8192], re.I)
    header = re.search(r'charset=([\w-]+)', content_type, re.I)
    choices = ['utf-8'] + ([header.group(1)] if header else []) + [s.decode('ascii') for s in declared]
    for charset in dict.fromkeys(choices):
        if charset.lower() in {'gbk', 'gb2312'}:
            charset = 'gb18030'
        try:
            return data.decode(charset), charset
        except (UnicodeError, LookupError):
            continue
    raise ValueError('unsupported-page-encoding')


def inspect_page(data, host, content_type=''):
    markup, charset = decode_page(data, content_type)
    page = Page(markup)
    # Several mobile publishers use h1 for menus ("分享到", "全部资讯"). The document title
    # is authoritative there; GuShiWen's work heading excludes its author/site title suffix.
    titles = ((page.elements('h1') or page.elements('title')) if host == 'www.gushiwen.cn'
              else (page.elements('title') or page.elements('h1')))
    title = html.unescape(titles[0].text()).strip() if titles else ''
    body = page.content(host)
    markers = [m for m in ['译文', '注释', '赏析', '简析', '教学目标', '教学过程', '教学重难点', '教学重点',
                          '教学难点', '导入', '板书', '作业', '同学们', '师：', '生：', '师:', '生:', '答：',
                          '答辩', '参考答案', '回答'] if m in body]
    # Longest alternative first: 请同学们 is one speech cue, not two.
    dialogue = len(re.findall(r'请同学们|请同学|同学们|师[：:]|生[：:]', body))
    ending = any(m in body[len(body) * 2 // 3:] for m in ['下课', '再见', '作业', '小结', '总结', '板书'])
    # Store only counts/flags/title, never body or descriptions.
    evidence = dict(pageTitle=title[:500], encoding=charset, contentChars=len(re.sub(r'\s+', '', body)),
                    markers=markers, dialogueCount=dialogue, dialogueRule="nonoverlapping-v2", scriptEnding=ending)
    if host == 'www.gushiwen.cn':
        category = '课文解读'
        meaningful = evidence['contentChars'] >= 200 and any(m in markers for m in ['译文', '注释', '赏析', '简析'])
    elif '说课' in title:
        category = '说课稿'
        meaningful = evidence['contentChars'] >= 600 and len(markers) >= 2
    elif '答辩' in title:
        category = '面试答辩'
        meaningful = evidence['contentChars'] >= 300 and any(m in markers for m in ['答：', '答辩', '参考答案', '回答'])
    elif '试讲' in title or '逐字稿' in title:
        category = '试讲稿' if dialogue >= 3 and ending else '教学设计'
        meaningful = evidence['contentChars'] >= 600 and len(markers) >= 2
    else:
        category = '教学设计' if any(m in title for m in ['教学设计', '教案', '教学实录']) else '课文解读'
        meaningful = evidence['contentChars'] >= 600 and len(markers) >= 2
    limited = any(phrase in body for phrase in ['以上为部分内容', '此为部分内容', '预览结束', '剩余内容需',
                   '完整内容请下载', '下载后查看完整', '登录后查看全文', '展开剩余内容'])
    if host == 'zy.21cnjy.com':
        # A download purchase button is independent of an actually readable design;
        # require a teaching ending as well as the ordinary body/section checks.
        meaningful = meaningful and any(m in body for m in ['板书', '作业', '反思', '总结', '小结'])
    evidence.update(category=category, meaningful=meaningful and not limited, readingLimited=limited)
    return evidence, page
