# Task 2 report: poetry-site login entry

Status: DONE (implementation complete; exact-head native execution remains the controller's acceptance work).

Base: `8a35ad2`. Implementation commit: `a035c24` — Connect poetry reader login and return within the embedded session.

## Implemented

- The actual web-text `ReadingView` now exposes Chinese `原站登录` and `返回原文` actions only for `gushiwen.cn` / `guwendao.net` or their subdomains, using exact-host / dot-suffix matching rather than substring matching.
- `EmbeddedResource.makeUIView` attaches the actual WKWebView and the initial, validated resource URL to `WebStudyController`. Login uses the existing `https://www.guwendao.net/user/wode.aspx` endpoint. Return reloads the captured original URL, including query and fragment, in that same WKWebView. Repeated login taps cannot overwrite the original URL. No web view, data store, or user agent is replaced by either action.
- Return availability indicates only that the user initiated login navigation. Chinese guidance directs the user to log in personally on the original page, return explicitly, and respect the site's login/access result. It explicitly says an external browser's login state does not establish embedded-reader login.
- Attribution, Safari escape, user selection extraction, note sheet, note persistence, and video draft handling remain in their existing paths. No authentication/credential script, automatic submit, cookie extraction, bypass, CSS rewrite, data refresh, or data-file change was added.
- A DEBUG-only `--ui-testing-offline-reader` switch cancels embedded reader navigation in the existing navigation delegate. Its sole use is a deterministic UI action regression with no original-site/login network requests; it is absent from Release and off unless explicitly passed.

## Authored regression tests (not executed here)

`AppTests/WebStudyControllerTests.swift` adds four native XCTest methods:

1. Exact roots, case-insensitive roots and real subdomains accepted; prefix/suffix/lookalike hosts rejected.
2. A request-recording WKWebView performs no network requests. Repeated login and return record the canonical login/login/exact-original sequence; the original URL, WKWebView identity, website data store, and user agent remain intact. Both source domains are covered, including query and fragment. Return before login is a no-op.
3. Unsupported/lookalike originals, non-HTTP originals, and originals carrying user info cannot trigger login or return.
4. Detached controllers do not claim navigation availability.

`UITests/GardenUITests.swift` adds `testPoetryLoginAndReturnKeepReaderActionsAndNotesWithoutRemoteLogin`:

- Opens the actual shipped `观沧海` resource via its stable resource ID.
- Uses the explicit offline-reader launch switch, never remote login/page availability or credentials.
- Checks Chinese labels, honest guidance, initial disabled return, enabled return after tapping the actual login action, and disabled return after tapping the actual return action.
- Checks attribution, selection action and Safari escape before/after navigation; opens the existing note sheet during login state, retains an unsaved draft across background/activation, saves it, and locates it in saved notes after returning.
- Retains screenshots `17-诗词原站登录与返回入口` and `18-诗词返回原文保留阅读操作` for the controller's native artifact inspection.

These tests are automatically included by existing XcodeGen `AppTests` / `UITests` directory sources and existing deterministic iOS workflow. Suggested focused native command (controller/macOS only):

```sh
xcodebuild test -project XinxinGarden.xcodeproj -scheme XinxinGarden -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -parallel-testing-enabled NO -only-testing:GardenAppTests/WebStudyControllerTests -only-testing:GardenUITests/GardenUITests/testPoetryLoginAndReturnKeepReaderActionsAndNotesWithoutRemoteLogin CODE_SIGNING_ALLOWED=NO
```

## Executed verification

Working directory for all repository commands: `C:/Users/wm14/Documents/Codex/2026-10-20/diao/xinxin-yuwen-garden`.

| Command | Result |
| --- | --- |
| `python scripts/check-catalog.py` | Exit 0: 6 books, 198 lesson/recitation entries, unique IDs and official sources verified. |
| `python scripts/check-library.py` | Exit 0: 198 lessons, 1163 resources, 198 offline outlines, 336 direct public text associations verified. No source recrawl. |
| `python scripts/test-text-sources.py` | Exit 0: 12 tests, OK. Existing Python ResourceWarnings from simulated HTTPError 412/500 cleanup appeared. |
| `python scripts/test-public-source-diagnostics.py` | Exit 0: 4 tests, OK. Existing ResourceWarning from simulated HTTPError 412 cleanup appeared. |
| `node --test reminder-service/worker.test.js` | Exit 0: 5/5 tests passed, 0 failures. Test stubs only; no real device messages. |
| `git -c safe.directory=C:/Users/wm14/Documents/Codex/2026-10-20/diao/xinxin-yuwen-garden diff --check` | Exit 0, no output. |
| `Get-Command python,node,swift -ErrorAction SilentlyContinue` | Python and Node found; Swift absent on this Windows host. |

No TDD was required by Task 2; native tests were authored alongside implementation and have **not** been compiled/run here. The passing Python/Node checks validate existing offline data/service behavior, not Swift compilation or WKWebView runtime.

## Files changed

- `App/EmbeddedResource.swift`
- `App/ReadingViews.swift`
- `AppTests/WebStudyControllerTests.swift` (new)
- `UITests/GardenUITests.swift`

This report is local under the existing ignored `.superpowers` directory and is not included in the implementation commit.

## Self-review and limitations

- Read the complete implementation diff and new controller tests after local verification. Checked strict host boundary, validated original URL, retained original across repeated login navigation, same WKWebView/data-store use, return availability rather than authentication claims, DEBUG-only offline seam, unchanged selection/note/browser paths, and no bundled data/IDs/version/minimum-iOS changes.
- No implementation defect found during self-review. Native compilation, native UI execution, layout screenshots, final exact-head workflows and IPA acceptance remain for the controller; no native/runtime/authentication success is claimed.
- Actual original-site authentication remains manual and was not tested with any credentials. The existing canonical login URL was reused without re-crawling sources or asserting cross-domain authentication success. Site redirects, account requirements, and access restrictions remain controlled by the original site.
- Existing DOM selection is naturally page-local during a navigation; the existing selection extraction/note workflow is preserved. No programmatic text expansion or selection restriction override was introduced.
- `ReadingViews.swift` and `GardenUITests.swift` are pre-existing larger files; the change stays in the existing reader/header and test patterns without restructuring them.
- No push, shutdown, external messages, ledger edit, or subagent dispatch performed.
