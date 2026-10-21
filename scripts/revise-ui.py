from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
replacements={
'小花园暂时无法读取资料':'暂时无法读取资料', '欣欣的小花园-备份.json':'欣语-备份.json',
'已合并资料和小重点；相同编号保留本机内容。学期与日历绑定保持本机设置。':'已合并资料和笔记。',
'这不是受支持的小花园备份。':'这不是受支持的欣语备份。',
'摘下这一句':'摘录', '我的理解与课堂灵感':'我的笔记', '记一朵小重点':'写笔记', '整理小重点':'编辑笔记',
'删除这条小重点？':'删除这条笔记？', '灵感很小，也值得收好 🌼':'学习笔记', '小重点':'笔记',
'收藏还在等你':'还没有收藏', '打开一篇课文，点“种进收藏”就能在这里找到。':'在课文右上角点收藏，就能在这里找到。',
'这一页留给小灵感':'还没有笔记', '种下一份资料':'资料信息',
}
for path in [root/'App/NotesViews.swift',root/'App/AppStore.swift',root/'Sources/GardenCore/DiskStore.swift',root/'App/SearchViews.swift']:
 s=path.read_text(encoding='utf-8')
 for a,b in replacements.items():s=s.replace(a,b)
 path.write_text(s,encoding='utf-8')
p=root/'App/Theme.swift';s=p.read_text(encoding='utf-8').replace('systemName: "leaf"','systemName: "doc.text.magnifyingglass"');p.write_text(s,encoding='utf-8')
p=root/'project.yml';s=p.read_text(encoding='utf-8').replace("CFBundleShortVersionString: '0.0.1'","CFBundleShortVersionString: '0.0.2'").replace("CFBundleVersion: '1'","CFBundleVersion: '2'")
s=s.replace('只有你点按同步时，才把上课提醒写入小花园专用日历。使用 iCloud 日历可在同账号 iPhone 16 提醒。','仅在你主动清除旧版课程提醒时访问日历，避免旧版和 Bark 重复提醒。').replace('用于创建和更新小花园专用课表日历，并核对你在日历中改过的课程。不会编辑其他日历。','仅用于移除旧版由欣语创建的课程提醒，不编辑其他日历。')
s=s.replace('CFBundleDisplayName: 欣语','CFBundleDisplayName: 欣语\n        CFBundleDevelopmentRegion: zh_CN\n        CFBundleLocalizations: [zh_CN]')
p.write_text(s,encoding='utf-8')
p=root/'scripts/package-ipa.sh';p.write_text(p.read_text(encoding='utf-8').replace('v0.0.1','v0.0.2'),encoding='utf-8')
for name in ['App/Resources/catalog.json','scripts/generate-catalog.py']:
 p=root/name;p.write_text(p.read_text(encoding='utf-8').replace('有所为有所不为','有为有不为'),encoding='utf-8')
