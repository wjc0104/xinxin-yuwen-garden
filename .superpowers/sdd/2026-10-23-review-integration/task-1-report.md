# Task 1 report: integrate main and order reminder uploads

Status: DONE. Native compilation/execution is explicitly deferred to exact-head CI because this Windows host has no Swift/Xcode.

## Commits and ancestry

- `9d2b4d660267ad6d6eadae9327e30a20ae53c0bd` — Merge main preserving native study features and current data semantics.
  - Parents: `23db847de9ec53693fef43b6e6f51f5ff5772450` and reviewed main `d71f369e750e0892f7448043139ae6ba83ff5c38`.
- `0831ae03311f7e49b79d1281d89c868d8be2563f` — Ensure latest reminder plan wins queued and in-flight reversals.
- This report is committed separately after the focused code commit. No push or shutdown performed.

## Implementation

Resolved six merge conflicts. Kept feature StudySearchIndex/prepared catalog, precise search and live discovery UI. Added incoming main resource-ID and per-lesson mark caches without rebuilding catalog/search on note-only changes; caches are prepared before publishing the snapshot. Kept incoming tombstones and old-backup compatibility, grouped composition undo, reduced startup writes, main workflow triggers, clean package staging and packaged-IPA validation. Retained dynamic version-derived package naming, both `ipa-inspection.json` and `ipa-report.json` artifacts, build-version checking, landscape checks and strict source-gated native workflow.

No App/Resources or project.yml changes relative to task baseline: all 198 lessons, 1163 resource records, stable resource IDs, 336 direct text associations, version 0.0.5/build 5, iOS 15 minimum, arm64 packaging and landscape settings remain intact. Native player implementation files are not in the integration diff.

BarkBridge now tracks the desired generation separately from uploaded certainty:

- Every new desired plan cancels/invalidates the previous task before checking equality with the last confirmed plan. A queued B therefore cannot survive returning to confirmed A, and settled unchanged A remains free of redundant requests.
- Starting any PUT clears upload certainty. Once B is in flight, returning to A must send a new revision for A; cancellation is never treated as proof that the server did not apply B.
- Both generation and revision must match before a response can publish success. An obsolete explicit refresh throws cancellation rather than returning apparent success for the newer plan.
- Latest failures remain explicitly uncertain and allow a retry of the same desired snapshot. Stop invalidates queued/in-flight generations immediately and retains stop-pending recovery on failure; stop persistence failures also receive an honest pending status.
- Production retains the 350 ms debounce, persisted monotonic revision source and server protocol. Profile changes reset confirmed-plan caches.
- Added a narrow initializer injecting transport, debounce, revision and profile storage. It never enters the default keychain-reading initializer. `changed` returns its optional actual task so tests await pipeline completion without sleeps. The production transport, revision and keychain paths remain the defaults.

Self-review also found the feature live-refresh path bypassed main's new deletedIDs. It now excludes deleted stable IDs before metadata merging. One actual LessonRefresh pipeline regression verifies a rediscovered deleted ID remains absent while notes/data are retained. No new core API or deletion policy was introduced.

## Deterministic native coverage authored (not executed locally)

`AppTests/BarkBridgeTests.swift` adds 11 tests against the real BarkBridge and actual encoded reminder plan. Transport gates deliberately ignore cancellation, allowing the old server request to complete successfully after reversal/Stop. Debounce and network completion order are controlled by continuations, with no real network, devices, keychain, user defaults revision writes or wall-clock sleeps.

1. Settled unchanged A avoids debounce/redundant upload.
2. Queued A → B → A cancels B and avoids redundant A.
3. In-flight B succeeds before A's debounce ends: UI stays updating, then newer revision A carries the original A jobs.
4. B succeeds after newer A: A's confirmed status remains intact.
5. Newer A fails then old B succeeds: uncertainty remains until newer A retry succeeds.
6. Stop supersedes in-flight B and ignores its late success.
7. Stop cancels queued B; failed Stop blocks refresh until Stop retry; subsequent enable uses newer revision.
8. Explicit refresh cancels queued B and uploads current A immediately.
9. Superseded explicit refresh does not return success for the later desired plan.
10. Failed enable persists recovery before network mutation and allows refresh.
11. Stop/configuration change/enable uses the new user's connection and device key.

`AppTests/LessonRefreshTests.swift` adds the deleted-stable-ID integration regression using its existing URLProtocol fake. Existing core, native playback, UI, library, storage and schedule tests were preserved. No native tests are claimed passed; exact-head CI is required to compile and execute all of this.

## Local commands and observed results

Ran from `C:\Users\wm14\Documents\Codex\2026-10-20\diao\xinxin-yuwen-garden` after the implementation:

- `python scripts/check-catalog.py` — PASS: 6 books, 198 lesson/recitation entries, unique IDs and official source checks.
- `python scripts/check-library.py` — PASS: 198 entries, 1163 resources, video parts, 198 offline outlines and 336 validated direct public texts.
- `python scripts/test-text-sources.py` — 12 tests, OK.
- `python scripts/test-public-source-diagnostics.py` — 4 tests, OK.
- `node --test reminder-service/worker.test.js` — 5 tests, 5 pass, 0 fail. Includes stale revision unable to undo Stop.
- `python -m compileall -q scripts` — exit 0.
- Offline temporary synthetic packaged-IPA fixtures executed the actual `scripts/inspect-ipa.py` CLI: valid 0.0.5/build5 arm64/iOS15/landscape fixture accepted; wrong version, wrong build, missing landscape and unsafe archive path rejected (5/5). These were generated ZIP/header fixtures, not a real built IPA or native acceptance. No downloaded artifact was overwritten.
- `git -c safe.directory=C:/Users/wm14/Documents/Codex/2026-10-20/diao/xinxin-yuwen-garden diff --check` and staged equivalent — exit 0.
- `git ... merge-base --is-ancestor origin/main HEAD` — exit 0. Merge parent inspection confirms both histories retained.
- `git ... diff --exit-code 23db847 HEAD -- App/Resources project.yml` — exit 0. Changed-file inspection confirms no native player files changed.
- `Get-Command swift -ErrorAction SilentlyContinue` — no Swift executable found. No swift test/xcodebuild claims.

Python 3.14 emitted ResourceWarning cleanup messages for fake HTTPError 412/500 objects in the existing text-source/diagnostic tests. Tests still passed; output is therefore not pristine. Git emitted expected LF-to-CRLF working-copy warnings. No real Bark messages, credential access/output, deployment, source recrawl or account changes occurred.

## Self-review and limitations

Reviewed the focused diff and merged feature delta. Checked generation ownership before request launch, queued cancellation before settled equality, both response orderings, in-flight uncertainty, retry clearing, busy request counts, Stop/enable persistence recovery, per-profile cache reset and live refresh tombstone forwarding. Corrected Stop's persistence-error status and stale explicit refresh's apparent-success return during self-review.

No known unresolved implementation defect. Native Swift/Xcode compilation, the 11 Bark regressions plus LessonRefresh regression, full Swift core suite, simulator playback/UI/landscape and real IPA acceptance remain mandatory controller CI work. Offline synthetic inspector results establish only the CLI validation branches, not a working IPA. Tombstones retain the incoming main stable-ID semantics; they do not add a new content-identity or URL blacklist.

Files changed in merge/fix: `.github/workflows/{build-ipa,ios-tests}.yml`; `App/{AppStore,BarkBridge,CatalogViews,LessonRefresh,NotesViews,ReadingViews,ScheduleViews}.swift`; `AppTests/{BarkBridgeTests,LessonRefreshTests,PlaybackAndResponsivenessTests}.swift`; `Sources/GardenCore/{DiskStore,Models,ScheduleEngine,StudyLibrary}.swift`; `Tests/GardenCoreTests/StudyLibraryTests.swift`; `scripts/{inspect-ipa.py,package-ipa.sh}`. Controller ledger was not edited.
