# 欣语网页版 Task 1 基础代码检查点

日期：2026-10-27（承接 2026-10-26 任务）。工作目录：`C:\Users\wm14\Desktop\xinxin-yuwen-garden`。

## 结论与范围

**基础代码已补齐并通过本机测试；网页版产品尚未最终完成。627 条视频资料全部仍未接通。** 不交付伪装完成的目录壳，不提供未经部署验证的在线地址。全部修改仅限 `web/` 与本报告；不改原生 Swift、控制器计划/设计或旧 scratch，不推送、不部署、不创建 Site、不操作浏览器、不关机。

复用中断任务已有 app/core/storage/CSS/index/manifest/export/core tests，没有重写 UI。控制器另行提交的设计/计划基线为 `5fd01db`。早期计划的第三方 iframe 方案已被最新用户要求覆盖，不能继续据此实施。

## 本次完成

1. 删除旧实现的 Bilibili iframe、`videoEmbedURL`、第三方播放器域名/CSS。CSP 变为 `frame-src 'none'; media-src 'self'`。视频明确显示“视频尚未接通”；来源链接仅作署名/参考，不计播放成功。没有同源 API，也没有伪造 `<video src>`。后续只能在验证媒体后使用 HTML video 系统控件。
2. 补齐 `sw.js`：固定同源静态白名单；安装前校验响应状态、重定向、精确 URL、MIME、应用标识及课程数据结构；拒绝登录页、错误和不匹配响应，不缓存第三方媒体、API、查询串或私人记录。等待旧页面关闭才激活，不 `skipWaiting`、不 `clients.claim`、不碰 IndexedDB，只删除自己 scope 的旧缓存。
3. 补齐 loopback-only 本机静态服务 `scripts/serve.mjs`，只提供 `dist/`，拒绝越界路径和写请求；非生产身份验证服务器。
4. 修复存储被阻塞后迟到打开的数据库句柄泄漏；保存中的笔记若又被编辑，不再一律删除其草稿。
5. 完成源数据白名单导出、构建版本文件与 README。保留原有本机持久化、备份校验/事务、目录搜索、选字笔记与课表代码。

## 数据审计

来源仅 `App/Resources/catalog.json` 和 `library.json`；没有读取/导出个人课表、笔记、备份、凭据、设备信息。

| 数据 | 实际导出 |
| --- | ---: |
| 教材 | 6 册 |
| 课文（原顺序、原稳定 ID） | 198 |
| 资料元数据 | 1163 |
| 自编正文 | 200 |
| 视频元数据 | 627 |
| 其他外部资料（无抓取正文） | 336 |

`dataVersion = ac6155aa56c53cdd`。资源仅输出 id、lessonID、title、kind、body、url、source、isPaid、category、durationSeconds、checkedAt、summary。只有来源为“欣语备课提纲”或“欣语原创练习”的 body 保留，其他 body 为空；正文和笔记通过 textContent/text node 呈现，不执行 HTML。

`web/.openai/hosting.json` 原样保留；SHA256：`8AA4ADFCF4539BE93ECD63BCA210601B5F1596B501FBEB010B3B3F3F6BFD4106`。它不是部署成功证据，更不是访问权限证明。当前只允许 owner-private，不共享匿名或其他查看者。

## 实际测试与结果

运行环境：Windows PowerShell、Node.js v24.22.1；无 npm 第三方依赖安装。

```powershell
& 'C:\Program Files\node.exe' --test web/tests/*.test.mjs
& 'C:\Program Files\node.exe' web/scripts/export-data.mjs
Get-ChildItem web/dist/*.js,web/scripts/*.mjs,web/tests/*.mjs |
  ForEach-Object { & 'C:\Program Files\node.exe' --check $_.FullName }
```

- 恢复时已有 6 个 core tests 通过，但导出因 `web/dist/sw.js` 缺失实测报 ENOENT；已补齐后重跑成功。
- 最终 **13 tests / 13 pass / 0 fail / 0 skipped**。覆盖：198 稳定 ID/顺序与字段白名单、防私有字段混入；精确“春”、作者、空/无结果搜索；危险 URL；笔记 ID/重点/来源关联；超大、重复、坏结构、原型字段备份拒绝且不修改现有对象；周课表与临时调整；事务完成/冲突/失败不替换旧记录；存储拒绝；SW 静态白名单、拒绝登录/重定向/401、按 scope 清缓存；无第三方播放器或 HTML 注入代码。
- 本机 HTTP 集成测试实际启动临时 loopback 服务，请求 `/`、app/core/storage/sw/version JS、CSS、icon、manifest、catalogue 共 10 项，均 200 且 MIME 正确；数据读取为 198/1163。越界访问 403，`/.openai/hosting.json` 404，POST 静态文件 405。测试结束停止该服务。
- 数据导出成功：`Exported 198 lessons / 1163 resources; data version ac6155aa56c53cdd`。
- JavaScript 语法检查通过；提交前另做 `git diff --cached --check`。
- IndexedDB 测试是最小事务生命周期模型；SW 测试在 Node vm 中模拟 response/cache/event。它们不是浏览器实际存储、配额、离线或登录验收。

## 控制器同步的外部证据（非本子任务复测）

控制器对同一“春”视频做受限探测：公开 playurl 在原生 Referer/UA 下返回 200、code 0、MP4、quality 16（360，不是高清）；CDN HEAD 使用网站 Referer 或无 Referer 均 403，原始 Referer 为 200。没有渲染视频帧证据，不能认定网页可播放；需后续受限服务端方案，不能实现匿名开放代理或绕过权限。

控制器同步既有 Sites 项目查询返回 `project_not_found`，疑账号状态变化，已向用户确认。此次没有创建替代站点、变更 `.openai/hosting.json` 或发布。

## 未完成与验证边界

- **视频是最终交付阻塞项**：实际媒体播放、准确分集、横屏/全屏、倍速、自动时间点笔记/跳转、真实音画皆未实现/未验证。当前只保留手动时间注记。不把来源页链接、HEAD 成功或可选画质当播放成功。
- 外站文章仅具体链接；未实现古文岛原文展开，不能把自编提纲叫作教材全文/试讲稿。联网资料搜索、服务端 API、Bark 提醒均无；刷新只检查已发布数据版本，提醒明确未启用。
- 没有启动浏览器自动化，未验证实际 DOM 导航、选择文字、中文 IME、保存刷新恢复、导入文件控件、无未捕获异常、响应式视觉、屏幕阅读器或触控。代码检查/HTTP/模型测试不替代这些验证。
- 未验证 iPhone 16 Pro Max/iOS 26.0 与 iPad Pro/iPadOS 18.7.8 Safari 的竖横屏、安装、图标（当前 SVG）、真实 IndexedDB、容量、私有模式、SW 安装/更新/断网、主屏幕身份状态。系统清理本机数据可能丢失笔记；需定期导出。
- 缓存仅公开数据，但不是账号访问控制；缓存后的资料与本机记录可在离线时保留。生产私有访问由托管配置承担，当前未验证。没有跨设备同步、加密或原生备份兼容。
- 数据更新后若原资料/位置失配，现有校验会停止写入并保留原数据库，尚无自动迁移流程；不能建议清除数据来恢复。
- 尚无 HTTPS 部署、真实可用链接、所有者登录证明或非所有者拒绝访问证明。不得宣布“网页版已完成”或“最终可用”。原生项目的 CI/设备验收仍独立，不受这次网页测试影响。

## 后续控制器检查顺序

先审查本次限定 diff，再解决账号/既有私有站身份、同源受限媒体接入及实际视频验收。只有用户授权范围明确且核心功能实测通过后，才隔离审计 `web/dist/` 发布；不能将父仓库上传，也不能以全体视频未接通作为最终交付标准。
