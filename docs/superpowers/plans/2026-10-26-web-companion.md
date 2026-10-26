# 欣语私有网页版 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提供所有者可登录测试、可添加主屏幕的学习网页，不替换原生 IPA。

**Architecture:** 独立 web/ 静态站点读取现有课程数据白名单导出；浏览器 IndexedDB 仅保存本机数据，Sites 提供私有 HTTPS 托管。

**Tech Stack:** HTML/CSS/ES modules, Node built-in test runner, IndexedDB, service worker, Sites static hosting.

**Spec:** docs/superpowers/specs/2026-10-26-web-companion-design.md

## Global Constraints
- 保留现有 Swift 代码和 198 课文稳定 ID，不改原生验收。
- 新网页仅自己测试、不公开；不发布真实课表、笔记、设备信息、密钥。
- iOS26/iPadOS18.7.8 Safari 为目标，桌面验证不冒充真机。
- 只展示真实资料，受限视频/文章不得显示已支持；不做开放代理或解除认证。
- 不关机；primary 五小时剩余不超过5%保存暂停。

## Review Focus
- 中文输入和短词搜索不混淆课名、作者与全文的弱匹配。
- 备份导入遇到超大文件、重复 ID、非法 URL 或坏结构必须保留现有数据。
- 存储被拒、离线首次启动、数据加载失败不得静默丢笔记或白屏。
- 第三方 iframe 跨站限制不能冒充有自动进度/时间、高清或原文展开功能。
- Service worker 更新不能删除本机数据、缓存私有登录页面或自动打断编辑。

## Task 1: 可测试的独立网页产品

**Files:** Create web/package.json, web/scripts/export-data.mjs, web/tests/core.test.mjs, web/dist/{index.html,app.js,core.js,storage.js,style.css,manifest.webmanifest,sw.js,icon.svg}, web/README.md. Data generated only in web/dist/data/.

**Interfaces:** exportData reads App/Resources/{catalog,library}.json without mutation; core exports searchLessons(query, lessons), safeURL(value), validateBackup(input, knownLessonIDs); persistence exposes async loadState/saveState (atomic IndexedDB transaction); UI renders text safely, never injects resource body HTML.

- [ ] Write failing node:test cases: all198 lesson IDs unchanged, exported data contains only whitelisted fields, exact 春 precedes related titles, 毛泽东 uses author, blank query returns catalogue; invalid backup rejected without replacement; note IDs stable; URLs reject javascript/data/file; imported prototype keys not interpreted.
- [ ] Run `node --test web/tests/core.test.mjs`, observe module/function failure.
- [ ] Implement export/core/storage/UI. UI has 主页/课程/课表/我的, lesson filters, self-authored text selection marks, per-resource notes, favorites, safe export/import with size cap, empty Chinese schedule and temporary exception dates. Preserve data on reload. Do not promise native backup compatibility. Use stable unique IDs.
- [ ] Provide actual specific video embeds where usable with source fallback clearly labelled. Iframe manual timestamp notes; HTML video only for known usable public media, do not invent direct endpoints. User-clicked playback only. Externally blocked articles show exact original link; internal text works without network after initial cache.
- [ ] Provide manifest/start_url/scope relative paths, install instructions, offline app/data caching only same-origin known static allowlist; exclude login, unknown responses and private user records. Version refresh checks actual published data version, never pretends new search.
- [ ] Run tests, Node syntax checks and data export. Run local HTTP browser QA for navigation, exact search, mark/note save/reload, backup invalid import, responsive and no uncaught exceptions. If browser unavailable record limit rather than fake pass.
- [ ] Write web/README.md usage, feature limits, private audience, privacy/storage/backup and test commands. Commit only web/ plus approved plan/spec; never push or publish as implementer.

## Task 2: Review and private deployment (controller)

**Files:** Create web/.openai/hosting.json through Sites helper; staging checkout outside parent repository if source helper requires independent Git. Never push native repo to Sites.

- [ ] Read full Task1 diff/report and dispatch fresh scoped/final reviewer; fix important findings via original implementer; rerun affected tests.
- [ ] Browser test real curated source and plain-text paths. Record embeds unavailable separately; do not declare all third-party capabilities completed.
- [ ] Register one private Site only; persist exact project ID atomically, source credential stays memory/stdin. Copy only audited public web files into isolated publishing checkout if required, preserving manifest and data.
- [ ] Use Sites source helper push/package exact source, private deploy, wait terminal success. No public access updates.
- [ ] Return exact deployed URL and Safari添加到主屏幕步骤, current login requirement, real capability limits and request device feedback. Do not call unfinished native CI accepted.

## Rulings and baseline
Native base 32b1ed8; design e8b50bf. User latest explicitly grants private publication for own testing. Native review/macOS preflight work remains pending separately; no concurrent native writer.
