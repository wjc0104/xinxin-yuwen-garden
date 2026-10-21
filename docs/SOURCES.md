# 资料来源

核对日期：2026-10-21。应用内搜索具体收录条目，不生成百度或 B 站搜索页。

## 教材目录

依据 [人教社电子教材](https://jc.pep.com.cn/)，六册原始教材链接与版本状态写在 `App/Resources/catalog.json`。共 150 个阅读课目与 48 个课外诵读条目；合篇保留子篇关键词。九下当前仍为过渡目录，不声称覆盖尚未确认的新修订教材；学校实物用书为准。

安徽教材参考来自 [芜湖市教育局公开目录](https://jyj.wuhu.gov.cn/xwzx/tzgg/8953250.html)，不作为萧县某所学校用书的证明。当前第一版资料面向统编六三学制，多版本扩展尚未完成。

## 视频

内置 627 个课文关联的视频分集条目（同名课文出现在不同册时分别索引，不代表 627 个独立作品）。每条保存原作者、具体分集、时长、公开封面和核对日期。完整公开元数据在 `scripts/resources/BV*.json`，可由 `scripts/build-library.py` 重建。

主要选集：

| 来源 | 具体内容 |
| --- | --- |
| 教资小两口 | [七上](https://www.bilibili.com/video/BV1eUAieoEZd/?p=1) · [七下](https://www.bilibili.com/video/BV17M9qYrEee/?p=1) · [八上](https://www.bilibili.com/video/BV1YMXPYBEkw/?p=1) · [八下](https://www.bilibili.com/video/BV1hdZxYCEAV/?p=1) · [九上](https://www.bilibili.com/video/BV1mNdqY8EBG/?p=1) · [九下](https://www.bilibili.com/video/BV137LizrE4S/?p=1)，教材与面试切口讲解 |
| 一起考教师官方 | [《春》试讲示范](https://www.bilibili.com/video/BV1rK4y1Y7RD/?p=1) · [《岳阳楼记》试讲分集](https://www.bilibili.com/video/BV16g4y1g7L1/?p=13) |
| 苏老西的初中学习站 | [七下课堂](https://www.bilibili.com/video/BV1w8zDBVESD/?p=1) · [八下课堂](https://www.bilibili.com/video/BV1a7waeBEBb/?p=1) · [九下课堂](https://www.bilibili.com/video/BV1efweeEEHS/?p=1) |

已核对公开视频元数据（标题、作者、时长和分集），未逐一完整观看、转录或审定教学质量。面试讲解不等于十分钟完整示范；课堂示范也不等于面试稿，界面分类予以区分。原作者标题中的“真题”不构成本应用的真题核验结论。

播放器和原链接均指向具体内容；没有下载、搬运视频或绕过登录、收费。播放、清晰度、下架与收费状态由原平台决定。优先使用分集首帧为封面，已去除已注销账号的条目。

## 文字

198 份逐课提纲：每篇给出备课切口、主问题、板书方向与十分钟练习安排；另保留《春》试讲练习和《岳阳楼记》重点卡。文字由欣语编写，不是转录稿、官方答案或教招频率统计。部分练习流程共用教学框架，需按具体题目、学情和教材调整。

正式面试信息以 [中国教育考试网](https://ntce.neea.edu.cn/) 及当地当次招聘公告为准。

## 技术来源

[Bark](https://github.com/Finb/Bark) · [TrollStore](https://github.com/opa334/TrollStore) · [Cloudflare Alarm](https://developers.cloudflare.com/durable-objects/api/alarms/) · [Apple EventKit 权限](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui)
