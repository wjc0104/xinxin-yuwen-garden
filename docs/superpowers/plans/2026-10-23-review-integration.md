# Integrate the reviewed branches and close the two findings

## Global Constraints

The user authorized continuing after the review: fix the reminder race and missing poetry-site login entry, integrate the two reviewed branches, run the workflows, preserve the downloadable artifact, then force-shutdown the computer. Only the controller may shut down. If the five-hour primary usage window has <=5 percent remaining, checkpoint and force-shutdown without waiting; weekly usage is not a shutdown trigger. User downloads the artifact personally. Existing source sync/push/main integration authorization remains in force; no new permission menu is needed.

Primary device is iPhone XR/iOS15, tester iOS16.3. Preserve minimum iOS15, arm64 TrollStore IPA, bundle ID com.wm0104.xinxingarden, version0.0.5/build5, Chinese simple UI. Keep the stock AVPlayerViewController, explicit-intent StudyAVPlayer, six speeds0.5/0.75/1/1.25/1.5/2 with default1, same-player fullscreen/landscape/paused state/drafts, strict real source/audio/frame/seek/retry tests and forced legacy transport tests. No private APIs, stream unlocking, credential output, real-message sends, account/service deployment or silent simulated public-source success.

Preserve all198 lessons,1163 resource records and stable IDs/notes/favorites/attachments/backups. Preserve336 external text associations, honest13 trial-script associations across8 lessons. No copyrighted full external articles or data recrawl. Reader follows original-site authentication and access restrictions; no automatic authentication or expanded access. Calendar/network/notification permissions stay user-initiated. Bark backend is not yet configured by the user; tests must not contact real devices or alter the real keychain.

Reviewed starting feature is898d2e099eb0bbfe99012707d0a5c12f7f44bd92; reviewed main isd71f369e750e0892f7448043139ae6ba83ff5c38; merge base isdfd4941. Both exact heads already have successful existing workflows, including real native and landscape on feature39808866097. Do not redo completed original revision005 tasks/reviews. New plan baseline is898d2e0; final review covers only this integration/fix delta, including incoming main changes. Keep both histories, no reset/force-push.

Windows has no Swift/Xcode. Run meaningful local Python/Node/data checks as affected; final Swift/native/UI/IPA acceptance is exact-head CI. Real playback/source failure remains blocking; search availability failures are separately reported with retained old resources and truthful partial status. User only requested these fixes and integration, no unrelated redesign.

## Task 1: Integrate main and fix reminder upload ordering

Merge origin/main d71f369 into the current feature898d2e0. Resolve conflicts preserving feature native video, precise indexed search/live discovery, text coverage, WebKit changes and the newer main semantics: deletedIDs/tombstones with old-backup compatibility, grouped composition undo, indexed lookup, reduced writes, packaged-IPA validation and main workflow triggers. Preserve0.0.5/build5/landscape and complete diagnostics/artifact scripts. Do not replace feature with the older main0.0.3 UI/library. Keep merge ancestry.

Fix main BarkBridge.changed finding at88: lastUploaded=A, desiredB is queued or in flight, desired returns toA; early equality currently leavesB active and never sendsA. Ensure the final desired snapshot wins in both debounce and in-flight scenarios. Cancellation alone is not proof the server did not receiveB: in-flight reversal must send a newer revision forA. Handle failure/stop/enable/refresh honestly; no stale request may report success for a later desired plan. Keep350ms debounce, existing server revision protocol and per-user configuration behavior.

Add deterministic regression coverage for A->B->A before debounce, A->B(in-flight)->A, unchanged settledA avoiding redundant uploads, stop/failure ordering as affected. Use minimal test seams exercising the actual coordinator/pipeline, no real network/device/keychain mutation and no tests that merely mirror a branch. Preserve existing tests. Review covering output in report; do not claim native execution locally. Commit merge/resolution and focused fix locally; no push/agents/shutdown.

## Task 2: Connect the poetry-site login entry

On the integrated feature, wire the existing unused WebStudyController.openLogin into a clear Chinese reader action for supported poetry sites. Add a clear way to return to the original resource after login in the same WKWebView/cookie context, without pretending an external Safari session authenticates the embedded reader. Preserve selection/notes/original attribution/browser escape hatch and user drafts. Only target actual gushiwen.cn/guwendao.net domains or their subdomains, not substring lookalikes. Do not read credentials, bypass access controls or auto-submit anything. Keep original-site restrictions and present truthful login/return guidance. Avoid broad CSS/site rewrites unrelated to the finding.

Add focused controller/UI regression checks demonstrating the action is wired and original navigation can be restored; no live login credentials or claim of authentication success. Commit locally; no push/agents/shutdown.

## Final acceptance

Task-scoped reviews, then one final integration-delta review, with one combined fix wave and scoped re-review if required. Run exact feature core/iOS/IPA workflows; inspect native decoded frame, landscape/draft/speed UI screenshots and downloaded IPA metadata/hash. Merge/push main only after acceptance, verify final main workflows/artifact, save delivery/checkpoint and reports. Then controller schedules shutdown.exe /s /f /t60; user downloads from Actions. Primary<=5 percent checkpoint shutdown overrides all remaining work.
