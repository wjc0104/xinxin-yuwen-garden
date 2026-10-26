# 有边界的网页 CI

此目录是独立、精确锁定的 **dev-only** Playwright 1.64.1 工具链；不改变网页或托管产品的依赖、身份校验、媒体模块、Swift 或 IPA 工作流。

## 本地与 CI

在仓库根目录执行：

```sh
node web/ci/verify.mjs offline
npm ci --prefix web/ci --ignore-scripts --no-audit --no-fund
cd web/ci
npx --no-install playwright install --with-deps chromium
cd ../..
node web/ci/browser.mjs
node web/ci/verify.mjs hosted
node web/ci/verify.mjs report
```

Windows 安装浏览器不需要 `--with-deps`；若默认缓存目录不可写，可显式设置 `PLAYWRIGHT_BROWSERS_PATH` 和 npm `--cache` 为允许写的临时目录。本轮本地使用 Node 24.22.1。

- `offline` 先再生成公开字段导出，再运行既有网页/部署适配器 45 项测试和新增 CI 信任边界测试。
- `browser` 仅访问随机端口的 `127.0.0.1` fixture server。Chromium 自行用 Canvas + MediaRecorder 生成 8 秒 VP8/WebM 动画；该媒体不下载、不发布、不伪装成原站视频。真实浏览器验证四入口、春/毛泽东搜索、DOM 选字重点与 IndexedDB 重载、原生 video 控件属性、至少 3 帧解码、倍速与 3 秒时间笔记/跳转。禁止任何外站请求。
- 选字使用 DOM Range，播放使用 `video.play()`；这不是 Safari 触摸选字、系统播放按钮点击或全屏手势验收。该浏览器上下文阻止 Service Worker，离线模型检查由既有 Node suite 覆盖，不宣称浏览器离线验收。
- `artifacts/` 不入库。仅输出小 JSON 和含自编笔记的 loopback 截图，不录制页面 trace、cookie、storageState 或远端网页。

## 可选远端探测

工作流显式输入 `target_url` 优先于仓库变量 `WEB_VERIFY_URL`；仓库变量 `WEB_VERIFY_ALLOWED_HOST` 必须由维护者填写一个**精确**的公开域名，不允许通配符。目标只允许无凭据、无查询串/片段、无自定义端口的 HTTPS 根路径。所有 DNS 结果须为公开地址，连接固定到已验证地址；不跟随重定向、不带 Cookie/Authorization，最长 15 秒、HTML 最多 128 KiB。

未指定目标输出 `NOT CHECKED / no_target`。指定目标但缺白名单、连接失败、登录、挑战、超时或重定向都不能通过验收；**显式请求的远端 job 会失败，离线 job 独立继续**。当前尚无官方生产身份适配，即使返回应用 HTML 200，也只能 `NOT CHECKED / production_identity_not_configured`，不能当作私有登录或真实播放成功。本轮不提供自造 token/header 旁路。

## 证据分层

报告分别记录 `code_suite`、`browser_fixture`、`hosted_access`、`hosted_real_playback` 和四个 `network_matrix` 单元：Wi-Fi/移动网络 × 代理开/关。后两类没有实测时一直 `NOT CHECKED`，`complete` 为 `false`。本机成功或 GitHub Actions 绿色都不代表交付完成。

四个 job 相互区分，`evidence_report` 即使其他 job 失败仍生成中文摘要；缺失的文件不会自动转成成功。GitHub 只保存指定 JSON/本地截图 7 天，无自动部署、邮件或关机动作。

官方依据：[Playwright CI](https://playwright.dev/docs/ci)、[1.64.1 发布](https://github.com/microsoft/playwright/releases/tag/v1.64.1)、[浏览器与编解码边界](https://playwright.dev/docs/browsers)。
