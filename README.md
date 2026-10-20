# 欣语

给欣欣的语文备课手记。

按课文找资料，随手记重点。XR 备课，iPhone 16 提醒上课。

## 能做什么

- **课文目录**：七到九年级六册，按教材顺序整理。
- **找资料**：搜索教案、十分钟试讲和原作者视频，保存自己的资料。
- **记重点**：文字与 PDF 高亮、视频时间书签、个人笔记。
- **管课表**：支持临时调课、停课、长期调整和日历提醒。
- **留备份**：资料与笔记存本机，可导出备份。

首版内置 198 个课文与诵读条目，以及少量精选资料。九下新修订目录待更新，尚未收齐每课教案。

## 安装

从 [Releases](../../releases) 下载 **Xinyu-v0.0.1.ipa**，通过 TrollStore 安装。

适配目标：**iPhone XR / iOS 15+ / arm64**。真实设备安装及两台手机的日历提醒仍需实测。

## 使用说明

[安装与提醒](docs/INSTALL.md) · [资料来源](docs/SOURCES.md) · [隐私与权限](docs/PRIVACY.md) · [测试记录](docs/TESTING.md)

日历权限只在主动连接时申请。无登录、广告或统计 SDK，不申请通讯录、定位、相机、麦克风及照片权限。

## 开发

SwiftUI · PDFKit · AVKit · EventKit

```sh
swift test
python3 scripts/check-catalog.py
xcodegen generate
```

[设计说明](docs/superpowers/specs/2026-10-21-garden-design.md) · [独立审查](docs/REVIEW.md)
