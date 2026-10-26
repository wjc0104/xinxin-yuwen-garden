# Web verification CI — Task 1 本地检查点

状态：**实现已准备评审；不是生产交付完成。`productionComplete = false`。**

## 范围

新增 `.github/workflows/web-tests.yml` 与独立 `web/ci/`；不修改产品、Swift、IPA、既有工作流、托管身份/受众，不 push/deploy/发送邮件/关机。控制器另行确认账号、提交精确 feature head、触发和核验远端 Linux CI；本文不声称 GitHub Actions 已运行。

## 实现和判断

- `code_suite`：Linux Node 24 再生成公开数据，运行既有网页与部署适配器测试及 CI 信任边界测试。
- `browser_fixture`：精确锁定 dev-only Playwright **1.64.1**（含 integrity lock），不进入产品依赖。只用 Chromium、自编 Canvas + MediaRecorder 8 秒动画和 loopback server；没有下载第三方媒体、没有生产 auth bypass。
- 浏览器检查：四入口、春课名精确结果在首位、毛泽东作者匹配、自编正文 DOM Range 选择、笔记与重点 IndexedDB 保存/重载、原生 controls/playsInline、至少 3 个真实 decoded frames、1.5 倍速、取用 3 秒时间/保存/重载/跳转。所有外站请求被阻止。
- 远端：只接显式 dispatch URL 或可信仓库变量。精确主机白名单、HTTPS 根路径、禁凭据/query/fragment/自定义端口、公开 DNS、固定解析地址连接、禁跳转/凭据、15 秒和 128 KiB 上限。结构化输出不含 HTML、Location、Cookie、token 或 upstream locator。
- 没有生产身份配置时不声称已认证。HTTP 200 app shell 也是 `NOT CHECKED`；无目标也是 `NOT CHECKED`。显式远端请求未通过将使 hosted job 非零退出，而不阻止独立离线 job。
- 报告始终分开五类证据和四个真实网络条件；未知值阻止 `complete`。7 天保留指定 JSON/loopback 截图，无远端 trace、自动发布/邮件/关机。
- Ruling：只保留本任务所需的 Chromium 基础浏览器门禁；Windows WebKit 的媒体失败不作产品失败定论，也不作跨引擎通过。后续 Linux/真实 Safari 验证独立处理。

## RED → GREEN 与本地证据

1. 先写 CI 信任边界测试，首次运行因 `verify.mjs` 尚不存在而 RED（`ERR_MODULE_NOT_FOUND`）。
2. 实现后 4 个测试组 GREEN：不可信 URL/私网 DNS、缺目标/缺生产身份、redirect/auth/challenge/HTTP 失败/拒连/超时（含 body timeout）/过大 body、显式请求 exit code 和四网络未知阻止 completion；敏感 sentinel 不进入结果。
3. 既有网页与部署适配器 **45/45 PASS**；公开导出 **198 lessons / 1163 resources**，data version `ac6155aa56c53cdd`。
4. 本机 Windows、Node **24.22.1**、Playwright **1.64.1** Chromium 已通过真实 UI 与解码检查，至少 3 帧；这不是远端 Linux 或 iPhone 结果。
5. YAML 使用已锁定 Playwright 工具链内置 YAML parser 检查：零解析错误/唯一 key；只读权限、四 job、always report、push 精确包含 `wm0104/web-verification-ci` 等结构断言 PASS。`git diff --check` PASS。

### WebKit 尝试失败证据（保留，不算通过）

Windows Playwright WebKit 曾尝试相同自编媒体；VP8/WebM 和随后自编 H.264/MP4 均未完成媒体就绪。最后一次诊断：`stage = webkit_media_ready`、`readyState = 0`、`networkState = 3`、`MediaError.code = 4`（unsupported source）、`finiteDuration = false`、`canPlayMP4 = probably`。此前 Chromium 完整检查 PASS。没有据此宣称跨引擎可用，也未修改产品解决平台编解码问题。原始失败截图曾由本机工具读取；最终 CI 不安装或声称测试 WebKit。

## 当前验收矩阵

| 证据 | 本轮本地状态 | 不能推导的结论 |
|---|---|---|
| code_suite | PASS：45 原有 + 4 CI 测试组 | 不是 Safari/托管验收 |
| browser_fixture | PASS：Chromium，自编 loopback 媒体 | 不是原站 MP4、真实分集或 CDN 播放 |
| hosted_access | NOT CHECKED：尚无本轮已认证可验收目标 | 已知 Sites URL 不可用未获解决 |
| hosted_real_playback | NOT CHECKED | 没有部署后原视频真实帧证据 |
| Wi-Fi，代理关 | NOT CHECKED | 未从该真实路径测量 |
| Wi-Fi，代理开 | NOT CHECKED | 未从该真实路径测量 |
| 移动网络，代理关 | NOT CHECKED | 未从该真实路径测量 |
| 移动网络，代理开 | NOT CHECKED | 未从该真实路径测量 |

仍未验证：真实 iPhone/iPad Safari、触摸选字/系统控件操作/全屏、主屏幕安装、浏览器 SW 离线、生产账号身份/私有受众/托管原视频、四种实际网络。没有配置 token 不等于成功；不能发送成功邮件或执行完成关机。

## 控制器下一步

独立评审 exact diff；只提交/推送获准 feature head，查看该 head 的 Linux 工作流及 artifacts。控制器已告知设置精确主机/目标的非密钥仓库变量；首次推送会实际探测已知尚未验收的私有 Sites，不能把 full workflow 描述为全部绿色。若显式请求远端遇登录、challenge、redirect、timeout 或缺身份，保留失败/未检查状态；继续解决托管与真实网络证据，不覆盖成本地 fixture 成功。

官方参考：[Playwright CI](https://playwright.dev/docs/ci)、[官方 1.64.1 release](https://github.com/microsoft/playwright/releases/tag/v1.64.1)、[浏览器/媒体编解码说明](https://playwright.dev/docs/browsers)。
