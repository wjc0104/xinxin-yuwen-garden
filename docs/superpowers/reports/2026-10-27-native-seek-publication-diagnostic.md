# Native seek publication attribution (diagnostic only)

Baseline: `a1c43dbcf5d7809c6c625e09bb8704411644f569`. Run `40485724427` failed the existing native seek publication predicate ten times against the historical tuple array; this does not establish ten races. Separate-process UI success cannot supply the missing native-unit publication origin.

## Minimal scope

- DEBUG-only nil-default observer records clock/app-completion publications after the original assignments. Revision rejection is recorded from the unchanged guard branch, without another clock/revision read. Release production tokens remain equivalent.
- The original failing native helper retains its assertions, predicate, targets, commands, waits and timeouts. Its one sink clock read feeds both the original tuple and diagnostic. No AVFoundation completion thread writes diagnostic storage.
- Fixed enum/numeric/bool events are bounded to 256 and the keepAlways unit-result JSON attachment to 64 KiB, with explicit dropped/truncated/nonfinite/unavailable/completed metadata. No URLs, paths, credentials, identifiers, notes or arbitrary exception strings are emitted. The observer is restored to nil in defer.
- Source callbacks follow the synchronous sink; sinkSequence points backward. Reject events have no sink link. nativeAwaitResumed is wait resumption, not an exact completion callback.

## Review and verification boundary

The frozen two-file candidate and writer report received independent limited review without an actionable P1/P2. Root verified the baseline/candidate hashes and backed up both originals before the controlled copy. After the controlled copy, the actual candidate repository passed all 6 public-source, 9 transport and 17 triage policy tests (one existing unavailable Windows FFmpeg-tool-path skip). `git diff --check` passed. The exact native run is recorded separately in the task checkpoint. Windows has no Swift/Xcode: static/lexical checks and JSON bound models are not Swift compilation, actual attachment export or native runtime evidence.

This is instrumentation, not a fix. Synchronous recording can perturb interleavings. Any diagnostic pass does not erase the previous native failure or ordinary UI dark-green frames in run `40461835497`; ordinary native acceptance remains open. No main merge, final IPA acceptance, usable hosted-mobile delivery, email or shutdown is claimed.
