# Selected-media triage implementation

Base: `0574e2f04ce057a6ca05f05b14bce26bd5cf30dc`.
Implementation commit: `a0cf25a4d5fa929609199a31176c31923e1a104f` on existing `feat/native-video-notes`. This report is committed separately so it can identify the exact implementation commit.

Changed files:

- `App/SameItemRenderDiagnostic.swift`: DEBUG + existing UI-testing + explicit same-item flag only. Writes the actual UI item's AVURLAsset URL to fixed private `Library/Caches/selected-media-private.json`. The locator contains only schema, launch UUID, launch-local generation/namespace and original URL. Sample metadata adds the same nonsecret launch UUID. No new fetch, source resolution, player, output attachment, seek or transport command is introduced.
- `scripts/triage-selected-media.py`: post-test CI helper, standard library only, no dependency installation or alternate-source fallback.
- `scripts/test-selected-media-triage.py`: focused synthetic/offline boundary checks.
- `.github/workflows/ios-tests.yml`: scoped offline check plus explicit-input-only helper after attempted playback tests and attachment export, before simulator artifact upload. The helper returns zero for unavailable evidence and does not modify the XCTest step result. Upload additions are exact `report.json` and `frame-[1-4].png` paths, within existing simulator-results artifact.

## Private handoff, bounds and cleanup

The locator is outside `same-item-render`, transport trace, XC attachments and upload patterns. Swift silently validates HTTPS, existing approved media hosts and absence of userinfo, writes at most16KiB atomically, requests mode0600 and removes any preceding locator when another diagnostic item replaces it. Locator errors/descriptions are never logged. No headers/cookies/credentials are written. Release/default behavior remains unchanged.

The helper privately captures simctl output, restricts its container to the selected simulator's standard `~/Library/Developer/CoreSimulator/Devices/<UUID>/data/Containers/Data/Application/<UUID>` path, validates cache ancestry and rejects symlink components. Locator/schema/sample size and generation+launch+namespace linkage are checked before any download. No second pagelist/playurl call occurs.

One range request asks for bytes0...33554431 of that original locator, with the existing fixed public Referer/User-Agent. Every redirect rechecks HTTPS, approved hostname, absent userinfo and port443/default; foreign/HTTP/credential redirects are rejected, at most3 hops, no retry. Environment proxies and cookie handlers are disabled. Responses carrying Set-Cookie/WWW-Authenticate or content encoding are rejected. A206 requires a start-zero, exact cap-or-object-end Content-Range; a200 is accepted only as a bounded complete response. Content-Length and bytes actually read are checked; reading enforces32MiB even without a declared size. Network uses a35s monotonic deadline plus5s individual I/O timeout. An error is exported only as a fixed reason code.

The prefix and all process output live in a newly created mode0700 `RUNNER_TEMP/selected-media-private-*` directory, outside build/artifact paths. Public prefix evidence is SHA256, byte count and safe range/status metadata only. SHA256 identifies the captured prefix, never a full object unless the response itself is complete. The finally path removes the private locator and the owned private directory before writing the public report. Cleanup rejects paths outside the expected roots, symlinks and unexpected private directory names. Missing/unsafe container evidence does not claim cleanup verification. Cleanup failure makes the diagnostic INCONCLUSIVE. On cancellation/process termination, disposable runner destruction is containment; successful cleanup is not claimed without a completed helper report.

## Actual PTS and independent decode

Targets come from successful copied buffers' `itemTimeForDisplay.value/timescale`, never current player time or screenshot time. Only epoch-zero finite valid returned times in0...30s are accepted; duplicate times are collapsed and at most4 are examined. Original target CMTime values/timescales are exported.

Existing ffprobe/FFmpeg tools are required. ffprobe uses the software `h264` decoder whitelist, selected video stream and a start-omitted31s read interval from the beginning. FFmpeg explicitly uses `-hwaccel none -c:v h264`, sequential decode from input beginning, `-copyts` and passthrough frame timing. No input fast seek, keyframe-only scan, remux, trim or timestamp reset is used. Selected frame indices come from the probe's decoded frames; each exported row includes original integer PTS, stream timebase where available, actual frame PTS, target difference and frame type. Nearest represented PTS must be within0.1s; the exact difference remains visible.

Missing moov, incomplete sample/reference chain, decoder stderr/nonzero exit, unsupported tools/codec, absent PTS or unavailable target are INCONCLUSIVE. Both process runs have35s runtime limits and bounded private stdout/stderr. Their stderr, command arguments and paths are never printed/uploaded. Safe stream/frame fields are explicitly selected and sanitized; tags are excluded. Decode images are limited to4 PNGs, each at most4MiB and1920x1080, and must have valid PNG dimension headers before export. Image content still requires inspection; the helper makes no automatic green/normal or source-corruption finding.

Every report explicitly includes `priorBytesEqualityEstablished: false` and limitation `same_locator_new_fetch_not_prior_AVFoundation_bytes`. This is a new fetch at the same selected locator. It cannot establish what AVFoundation previously received or a same-byte Apple-versus-FFmpeg comparison. A truncated prefix or cap-limited metadata failure is never bad-source proof. No snapshot/replay or product repair was implemented.

## Verification and unchanged gates

Offline results on Windows, after implementation commit:

- `python scripts/test-selected-media-triage.py`:7 passed. Fake transport exercises actual URL/redirect/range/deadline/overflow/credential checks; temp files exercise locator linkage, original returnedPTS selection, metadata limits, app-container paths, cleanup and safe allowlisted report/frame export on success/download/decode failures. Fake subprocesses exercise private stderr rejection and deadline termination. Decode fixtures check software/no-seek arguments, actualPTS/frame type and exclusion of tags. Symlink rejection is exercised when unprivileged symlinks are supported.
- Existing `test-player-transport-diagnostics.py`:7 passed.
- Existing `test-public-source-diagnostics.py`:6 passed.
- Python compile checks and `git diff --check` passed.

No network/media/device probe, push, CI dispatch, main mutation or shutdown was performed. Native Swift compile and real ffprobe/FFmpeg/source behavior remain for root's exact-head CI review/experiment. Synthetic checks do not prove native rendering or decoder equivalence. Tool absence may legitimately produce INCONCLUSIVE on the runner; no package is installed.

All original5 paused image gates and3 initial-playing gates are unchanged, as are native/source/audio/frame/seek/retry/legacy/fractional/rate/stock/landscape/notes checks and explicit method opt-in. Product data, version0.0.5/build5, minimumiOS15, arm64/TrollStore, public reader/API/Bark/permissions and source policy were not modified. The separately root-managed Intel output-free control was not touched.
