import json
from pathlib import Path
items=[]
def add(id,lesson,title,kind,body='',url='',source='小花园原创练习',paid=False):
    items.append(dict(id=id,lessonID=lesson,title=title,kind=kind,body=body,url=url,localFile='',source=source,isPaid=paid))
add('spring-script','7u-01','《春》十分钟试讲小练习','script','''练习用途：教资与教招通用演练，自编示例，不是官方范稿或真题。具体题目与时长以当地公告为准。

0:00—1:00 导入与目标
同学们，用一个词说说你眼里的春天。今天读朱自清的《春》，我们试着从细节中看见春意，并说清楚语言为什么动人。

1:00—2:00 初读感知
请自由朗读，圈出描写的景物。给文章分成盼春、绘春、赞春三个部分，并找出自己最想停留的一幅画面。

2:00—6:30 聚焦春风图
先读相关段落，找出视觉、触觉、嗅觉、听觉的线索。小组各选一个细节，用“我读到……，仿佛……，所以……”交流。教师追问：看不见的风怎样被写得可感？引导学生联系花香、泥土气息和声响，解释多感官描写。不要只报修辞名称，要说出表达效果。

6:30—8:30 迁移与反馈
任选校园的一处春景，写两句话，至少调动两种感官。请一位同学朗读，其他同学依据“具体景物、感官细节、表达效果”给一句建议。

8:30—9:30 小结
从景物中找细节，再由细节理解情感。回扣开头：你的那个词，现在有没有更具体的画面？

9:30—10:00 作业与板书
作业：把课堂两句话扩写为一段春景描写，标出你最满意的感官细节。
板书：春 → 盼春／绘春／赞春；春风图 → 触觉、嗅觉、听觉 → 热爱与希望。

复盘：有没有学生活动？问题是否由浅入深？是否用学生的实际表达判断达成，而不只问“懂了吗”？''')
add('spring-video','7u-01','《春》试讲示范 · 一起考教师','video',url='https://www.bilibili.com/video/BV1rK4y1Y7RD/',source='B站原作者页面 · 2020 · 约9分19秒；付费情况以平台为准')
add('spring-plan','7u-01','《春》教学设计 · 2026 资料预览','link',url='https://zy.21cnjy.com/26331720',source='21世纪教育网 · 常规课时教案，非十分钟稿；可能需积分/付费',paid=True)
add('pear-video','7d-14','《驿路梨花》十分钟试讲选段','video',url='https://www.bilibili.com/video/BV1MGAJzoEJD/',source='B站小红帽 · 2026 · 页面视频约7分29秒，不等于完整10分钟')
add('yueyang-video','9u-11','《岳阳楼记》等试讲合集','video',url='https://www.bilibili.com/video/BV16g4y1g7L1/',source='B站一起考教师 · 2023合集；岳阳楼记分集约9分16秒，旧版示范需对照新教材')
add('yueyang-guide','9u-11','《岳阳楼记》备课重点卡','guide','''自编备课提示，不是官方考点统计。
1. 情景关系：区分两种览物之情和“古仁人之心”。依据具体语句解释，不把全文简化成一句名言。
2. 语言支架：结合上下文解释实词、虚词与句式，再回到篇章结构。
3. 十分钟切口：围绕“作者如何从写景转向议论”设置一个主问题；选取两处有代表性的文本证据。
4. 课堂评价：让学生比较、概括并引用依据，避免连续教师独白。
5. 教招拓展：按公告要求补充教材分析、学情、目标、重难点和教学反思；教资练习补充结构化与答辩。''')
Path('App/Resources/seed-resources.json').write_text(json.dumps(items,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
