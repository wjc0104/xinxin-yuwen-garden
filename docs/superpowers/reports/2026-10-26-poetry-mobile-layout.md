# 诗词阅读手机布局修复报告

日期：2026-10-26
基线：`8e6bc354d1a21d8d38c7f4a0c5daa82913c69b03`
权威工作区：`C:/Users/wm14/Desktop/xinxin-yuwen-garden`

## 状态与范围

实现及针对性测试已完成，Windows 本地检查通过；**尚未完成 Swift 编译、WKWebView/XCUITest 原生执行及 iOS 15 真机验收**。本报告不把 Chromium 结果当作 iPhone 结果。原生验收、后续工作流与交付由主任务继续执行。

本次只涉及 `App/EmbeddedResource.swift`、`App/ReadingViews.swift`、`AppTests/WebStudyControllerTests.swift`、`UITests/GardenUITests.swift` 和本报告。未改播放器、工作流、脚本、课程/资源数据、版本、签名或最低系统要求；未推送、未启动 CI、未执行关机。仓库迁移前的证据只读复用，没有写入旧仓库。

## 现象与根因

用户视频 `IMG_2650.MP4` 显示正文缩小成窄栏、右侧空白及横屏原生说明占高。此前公开无认证响应和 DOM/CSS 检查发现：

- 桌面响应无 viewport，`.main3` 为 1200px，左栏 870px，右栏 300px；`.main4` 为 1000px。
- 顶部另有 `.main3`，内部元素宽 300px、左外边距 720px。旧规则未覆盖此头部和 `.main4`，页面仍可能按桌面宽度缩小。
- 原文与译赏字号不一致；旧规则仅调整 `.contson`，译赏 `.contyishang` 仍沿用站点样式。
- iPhone UA 对 www 返回移动站跳转；当时移动站响应的全文占位容器没有文字，而桌面响应包含已公开交付的完整段落。因此保留桌面 UA，修正文档呈现，不通过切换 UA 丢失公开正文。

上述响应为此前同任务的时间点证据，并非对站点未来响应的保证；本次收尾未重新抓取网络或文章。

## 最小完整改动

### 文章布局

- 保留精确域名/子域边界：仅 `gushiwen.cn`、`guwendao.net` 及其子域执行原有诗词脚本，拒绝相似拼写或后缀伪装域名。
- 仅检测到 `.sons .contson` 或 `.sons .contyishang` 后标记文章；所有新增布局规则均限定到 `html.garden-poetry-reader`。账号表单等非文章页面不设置 viewport、不启用文章布局。
- 使用 `width=device-width, initial-scale=1`，不设置禁止缩放或最大缩放比例。原文和译赏为 18px、1.8 倍行高，正文左右 16px；布局祖先、卡片和页脚随可用宽度重排。
- 隐藏文章页桌面头部与右侧栏，保留原文、作者署名、来源链接和页脚；不靠全页 `overflow:hidden` 掩盖溢出。
- 复用原有最长 15 秒、pagehide 断开的 MutationObserver 检测迟到文章子树；文章识别后立即短路，不新建轮询或逐次全页扫描。重复注入不叠加样式/观察器。
- 已公开全文展开的原有判断、空占位保留、迟到段落处理不变，只在已存在的 added 子树处理入口增加布局识别。没有私有 API、自动登录、受限内容请求或捆绑外部文章。

### 原生阅读操作

- 来源与“浏览器打开”保持可见；诗词页“阅读选项”菜单集中“原站登录”“返回原文”“阅读说明”。说明改为按需弹窗。
- 登录导航待返回时保留简短“返回原文”按钮；加载失败与选区提示仍可见。
- 横屏紧凑高度只缩小网页摘录/笔记操作的垂直内边距，保留非网页资料原来的按钮内边距。
- 摘录继续使用现有 selectedText 与 NoteEditor，未改变草稿、笔记持久化或导航控制器。

### 测试与夹具

- DEBUG 专用、离线 `study-fixture` HTML 只含自写短句，复现固定宽度头部、左/右栏、页脚及隐藏译文。仅明确传入 UI 测试参数才启用；与离线读取参数组合阻断外部导航。
- 新增真实 WKWebView 几何测试：390×844 → 844×390 → 844×390 → 390×844，检查文档溢出、原文/译文字号、正文边距和填满宽度、viewport 比例、选区矩形、文字保留、现有控制器摘录、作者/来源、公开译文显示及单一样式。这里左右横屏是等宽几何阶段；真实旋转另由 UI 测试覆盖。
- 新增账号页不变和迟到文章测试；原有 7 项公开全文/域名/控制器测试保留，共 9 项 WebStudyControllerTests。
- 新增 UI 竖屏、左横屏、右横屏、返回竖屏测试，断言阅读区域最低可用空间、原生操作可点击，并保存屏幕图与 frame 附件。
- 原登录/返回/笔记草稿 UI 测试更新为菜单与弹窗路径。收尾修正两处 `staticTexts.containing(NSPredicate)` 为 `staticTexts.matching(NSPredicate)`，因为应匹配文本元素自身而不是其子孙。

## 已执行验证

### Windows 当前工作区

| 检查 | 结果 |
| --- | --- |
| `python scripts/check-catalog.py` | PASS：6 册，198 条课程/诵读条目，序号、唯一 ID、来源有效 |
| `python scripts/check-library.py` | PASS：198 条课程，1163 资源；视频分集、198 离线提纲、336 条已验证公开文本映射保持一致 |
| `git diff --check` | PASS；仅现有 Git LF/CRLF 转换提示 |
| 当前 Swift 中提取的 production JavaScript | 语法可解析，与已留存几何证据所用 `poetry-production.js` 逐字一致（仅统一 CRLF） |
| 已留存 `chromium-layout-results.json` | 8 行全部重新校验通过，未重跑几何测试或覆盖旧证据 |
| 当前离线 Chromium 边界检查 | PASS：账号表单尺寸/值/viewport 不变；迟到文章重排及公开正文显示；重复注入只有一份布局样式；无关域及两个相似域均不生效；所有外部请求均中止 |
| 静态范围核对 | 仅指定 4 个 Swift 文件和本报告；原有公开全文实现除 added 入口布局调用外不变；原有 7 个测试未删改 |

当前收尾边界检查脚本位于忽略目录：`C:/Users/wm14/Desktop/xinxin-yuwen-garden/.superpowers/sdd/2026-10-23-review-integration/handoff/check-poetry-boundaries.cjs`。没有新增生产依赖或测试脚本到提交。

### 复用的 Chromium 几何与视觉证据

证据目录：`C:/Users/wm14/Documents/Codex/2026-10-20/diao/outputs/review-integration/guwendao-user-2650`。

- `chromium-layout-results.json`：合成夹具及已保存公开 DOM，各自完成竖屏 → 横屏左标签 → 横屏右标签 → 竖屏返回四阶段。
- `poetry-production.js`、`check-poetry-layout.cjs`：当时提取的实际生产脚本与检查代码；当前脚本已比对一致。旧检查脚本含旧仓库路径，仅作为历史记录，不直接从新工作区运行。
- `synthetic-{portrait,landscape-left,landscape-right,portrait-return}.png` 与对应 `saved-public-dom-*.png`：已留存截图。收尾复看合成竖屏/横屏图，正文铺满内容宽度、选区仍在、无桌面右栏；这不是原生 chrome 截图。

| 两种文档均得到的几何 | 390px 竖屏/返回 | 844px 横屏两阶段 |
| --- | --- | --- |
| document.scrollWidth | 390 | 844 |
| 原文/译文宽度 | 358 | 812 |
| 正文左/右边距 | 16 / 16 | 16 / 16 |
| 原文/译文字号 | 18px / 18px | 18px / 18px |
| visualViewport.scale | 1 | 1 |
| 已记录越界元素 | 无 | 无 |

此前合成夹具检查还断言旋转尺寸变化后选中文字不变。公开 DOM/CSS/截图保持在仓库外，不将全文复制进报告、测试或提交。

## 必须继续的原生验收

1. 对最终整合后的确切 commit 运行原生构建及既有完整门禁；不能用本次 Windows 结果替代 Swift/Xcode 编译。
2. 执行全部 WebStudyControllerTests，重点检查真实 WKWebView 的视口变化、字体、选区矩形及 quote 回调；保留 XCTAttachment。
3. 执行更新的登录/返回/笔记草稿 UI 测试和新四方向阅读测试，审看四阶段截图、原生 frame 附件、菜单和弹窗可达性。
4. 确认现有播放器、图片、资源和其它严格测试未被弱化，仍随最终整合 head 通过。
5. iPhone XR / iOS 15 真机仍需检查安全区、左右横屏、长按选区、双指缩放、实际站点公开正文以及可选登录返回。模拟器通过也不等于 iOS 15 真机证明。

## 剩余边界与风险

- Windows 没有 Swift/Xcode；本次未宣称原生测试、工作流或 IPA 成功。UI 元素树、窗口/设备实际旋转及安全区需由原生运行确认。
- 站点 DOM/CSS 与 UA 响应可能变化。布局识别依赖支持站点现有文章结构，未知结构不强行套用文章布局；不会保证未来或任意文章结构均有效。
- 复用既有 15 秒观察窗口；超时后才首次插入的文章结构不额外启用无限轮询。
- CSS 保留用户缩放能力，但真实 WebKit/iOS 的缩放、选区与系统辅助功能交互尚待设备验收。
## 2026-10-27 exact native CI and menu target candidate

Exact source 459c94ae5897bb43332f40c2f6f827c049507a54; run https://github.com/wjc0104/xinxin-yuwen-garden/actions/runs/40448845789 (macos-15, explicit same-item diagnostics).

- Actual macOS policy preflight, FFmpeg pair preparation and required real synthetic H264+AAC regression passed. Native project compiled.
- All 31 app-hosted tests passed, including all 9 real WK controller tests (public expansion, account isolation, responsive desktop fixture and selection).
- UI tests: 5 passed, 2 failed. Both poetry flows failed at the actual reading options button: native AX target was 19.7 by 19 points, identified outer/nested buttons provided no hittable point. Other browser/quote/note controls passed their hit checks.
- Actual native playback and selected-media triage were correctly skipped by deterministic failure. This run does not accept native video, reader orientation UI or complete delivery.
- Logs and 18.6MB simulator evidence were downloaded to the controller's allowed local evidence directory; no secrets or user data were added to source.

Candidate 1 hypothesis: the existing bare-image Menu label needs an explicit 44 by 44 layout and rectangular hit region. This is a minimal target fix, not a proven explanation of all SwiftUI AX internals. Only ReadingViews.swift label layout and the existing UI regression assertions change. Actions, identifier, accessibility label, login/return conditions, controller, reader, player and data are unchanged. Native replay must confirm it.

Regression retains real tap/isHittable and all four original orientation phases, adds unique menu Button, 44pt size and actual expanded login action hittability. Geometry is retained before the menu assertions. No coordinate tap, query downgrade, retries, hidden AX or acceptance threshold weakening.

Windows static invariants passed (15 checks); existing failure AX fixture fails the new size assertion. These checks are not Swift/native GREEN. Independent scoped review reader_menu_hit_review found no concrete P1/P2. Actual simulator UI/landscape, iOS15 device, VoiceOver and large Dynamic Type remain unverified. Candidate must run on its exact committed head before acceptance.
## Candidate 1 falsified; candidate 2 awaiting exact native validation

Run https://github.com/wjc0104/xinxin-yuwen-garden/actions/runs/40451011756 used exact 3708b979a15689da16780fc46cf4d28eec50b1d2. Preflight/real FFmpeg/native compile/31 app tests including 9 WK all passed again, but the same two poetry UI cases still failed isHittable. Measured options geometry was 44 by 43.999999999999986 points, web began at y153.666 without overlap. Thus expanding the Menu label alone did not fix activation. Actual video and selected-media triage again stayed skipped, not a player result.

Candidate 2 changes the existing Menu trigger to an ordinary SwiftUI Button presenting the native iOS15 confirmationDialog. Its 3 action bodies, Chinese labels, identifiers, return disabled condition and trigger accessibility label/44pt layout remain. No reader controller, player, Web, workflow or data changes. This addresses the confirmed non-actionable Menu boundary without claiming a proven internal SwiftUI mechanism.

The only UI-test change is 0.001pt arithmetic tolerance on four minimum-size assertions because actual AX CGRect subtraction returned 43.999999999999986. 43.99pt and the old19.7pt still fail; actual query, uniqueness, hittability, taps, all four orientations and readable-space gates are unchanged. Windows static checks19 passed; independent scoped rereview found no concrete P1/P2. This is not native GREEN. Dialog action IDs/disabled behavior/guidance alert transitions must pass actual replay. Physical iOS15, VoiceOver and large Dynamic Type remain unverified. Prior candidate and failing evidence are preserved.
## Candidate2 native four-orientation PASS; unavailable-action test contract

Exact run https://github.com/wjc0104/xinxin-yuwen-garden/actions/runs/40452668709 on 2b386d730b717f6a75475ea1e326b57c98ef5992 completed with one UI failure. All31 app tests including9WK and actual native compilation/FFmpeg regression passed. UI6/7 passed: the full portrait/landscape-left/landscape-right/portrait-return reader test now passes actual options taps, expanded login action hittability, geometry and guidance presentation. Four44pt targets report optionsHittable=true. An independent visual reviewer inspected all4 actual PNGs plus4 native geometry and4 DOM reports; root inspected portrait and landscape-left. No confirmed fixture layout defect or horizontal overflow; landscape native reader734x201.67pt (59pt side safe areas), portrait393x563pt. Landscape first screen is tight; this does not prove full-page scrolling or actual-site/physical-XR/iOS15 behavior.

The sole failure at UI test line30 was reading .isEnabled of a nonexistent return action, not enabled=true: current native confirmationDialog AX contains login/guidance/cancel and omits the disabled return while on the original article. Production action still has .disabled(!web.canReturnToOriginal); controller state beginsfalse, login initiatestrue, guarded return resetsfalse. This is observed presentation behavior, not a universal claim about every OS.

Minimal correction touches only the UI test: original-article return must be unavailable (missing OR disabled); short-circuiting rejects existing+enabled and avoids querying a missing node. Login must still provide a present/enabled/hittable return; new actual menu-return tap must remove inline return state, then another login continues the original guidance/draft/background/save/inline-return route. The final inline-return disappearance is also checked. Exact queries, real taps, all four orientation/space/hittable gates and production source are unchanged. Windows24 static invariants/truth table passed; independent limited review found no concrete P1/P2. This adjusted test/new menu-return sequence still needs exact native CI. It does not waive production acceptance.

Actual native video and selected-media triage remain skipped in this failed run. No rendered public-player acceptance, overall network acceptance, successful link email or completion is claimed.
