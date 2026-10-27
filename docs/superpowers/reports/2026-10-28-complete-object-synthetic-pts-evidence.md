# Run 40599641666 synthetic PTS investigation

## Evidence, not yet a causal fix

- Read `run-40599641666/failed-step.log` and current repo test/coordinator code. The exact reported run/head is `40599641666` / `0b94743` (root supplied); failure is `test_real_local_h264_aac_command_path` line 571 -> `decode` line 802 `target in timeline` -> `exact_pts_unavailable`, 2.327 s. The log contains no frame PTS and does not identify which target is absent. Native project generation/playback had not begun at this failure.
- The named synthetic fixture uses locally generated 601 s, 1 fps H264/AAC, `-bf 0`, `-use_editlist 0`. The test requests exact nominal integer PTS 5/15/25/52. Its fixture-only terminal-moov cleanup removes unsupported metadata/grouping boxes. The coordinator already probes from beginning through 54 s, requires stream start_pts=0, and matches exact Fraction PTS.
- Existing evidence does **not** distinguish mux timing, audio priming, fixture normalization, or probe interval behavior. Those are hypotheses, not established causes. No decoder/fixture/threshold/PTS matching change is justified yet.
- Searched existing PATH and codex runtime, Program Files, scoop/chocolatey/WinGet install roots: no local ffmpeg/ffprobe. No install/download/network/CI initiated.

## One-file candidate, evidence only

Candidate: `scripts/test-complete-object-control.py`

SHA256: `bfc8c7f126fec583d1e68dad9e0f126de523bbd56c6e1d7b96f9dab4e97ffdde`

Only the named synthetic test wraps its unchanged `c.decode` call in a test-private helper. Only on `exact_pts_unavailable`, it reuses existing bounded `private/probe.stdout` (no extra process/probe). It emits at most 4096 bytes of fixed-schema `COMPLETE_OBJECT_SYNTHETIC_PTS` numeric evidence:

- frameCount, streamStartPTS, time-base numerator/denominator;
- first and last four raw PTS with exact rational seconds;
- each fixed target's exactPresent and lower/upper rational witnesses.

No arbitrary dict/string/tag/path/error/stderr output, and no raw private-media source. Bad/unsupported metadata emits only `unavailable`. The exact original exception object is re-raised; original failure and exact-match contract remain intact. Successful decode emits no extra diagnostics. Production/coordinator/fixture/gates unchanged.

## Actual verification

Windows bundled Python `-B`, UTF-8. Candidate imports the unchanged repo coordinator through a read-only import-location override in the ephemeral test harness; no sibling coordinator copy is a candidate.

**43 tests, 41 pass, 2 skip, 0 failures/errors, 1.080 s, exit0.** Existing skips remain POSIX process-group assertion (Windows) and real FFmpeg command path (tools absent). Two new offline tests prove:

1. fake synthetic shifted PTS produces bounded numeric exact-neighbor evidence, strips unknown sentinel strings/paths, and re-raises the original exact_pts_unavailable object;
2. wrong time-base/start/PTS fields cannot escape sentinel content; they emit only unavailable and preserve failure; unrelated decode failure never reads probe metadata or prints extra output.

No actual FFmpeg/native success is claimed.

## Next smallest step

Root review/integrate this one test-only evidence candidate, run the named synthetic gate on the same macOS toolchain, and inspect its bounded timeline. Only after a concrete PTS difference is observed should a fixture-only single-variable fix be designed and verified. Do not alter decode exact rational matching, widen gates, seek, substitute nearest frames, or rewrite player behavior.
