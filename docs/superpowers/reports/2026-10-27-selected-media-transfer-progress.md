# Selected-media transfer-progress evidence, 2026-10-27

## Why this limited diagnostic exists
Ordinary exact e8c15b23095921b46ca63cfc88560323a8fc4706 run[40461835497](https://github.com/wjc0104/xinxin-yuwen-garden/actions/runs/40461835497) failed the initial actual displayed-video gates[true,false,false]. The first raw UI picture is normal around displayed8s; two later original screenshots actually show dark-green video/instructor outlines around displayed17/25s.31app+7UI and a separate native720/audio/seek test passed, but those results do not erase the ordinary UI failure or prove later fullscreen behavior. No diagnostic pixel-buffer output was enabled in that ordinary run.

The earlier explicit run[40454552797](https://github.com/wjc0104/xinxin-yuwen-garden/actions/runs/40454552797) also retained a real green buffer counterexample. Its independent same-locator fetch ended INCONCLUSIVE/network_deadline without byte/time progress. Returned-buffer PTS, UI screenshot clock and separately fetched source bytes are distinct evidence; priorBytesEqualityEstablished remains false.

## Narrow change
Only fetch and its main report call plus direct offline tests change. The additive transferProgress record contains fixed stages(opening/validating_headers/reading_body/complete), bytesRead(0..CAP+1), bytesWritten(0..CAP), elapsedMilliseconds(monotonic duration truncated/saturated0..2147483647) and complete(boolean). Read bytes are counted before the existing post-read deadline guard, and written bytes only after successful write returns. These are application-level returned/accepted bytes, not wire traffic, durable storage or decoded frames. validating_headers does not mean headers passed; reading_body begins only after existing checks pass.

Progress survives a failed fetch. Partial bytes never become a successful prefix hash or decode result. No URL, signed query, header, exception text, raw media, private locator or path is newly exported. Existing32MiB CAP,35s transfer budget,5s socket timeout, one fetch, HTTPS/redirect/authentication/range/size checks, returned-PTS selection, safe paths/cleanup and actual FFmpeg gates remain unchanged. No Swift, player, source-selection or workflow changes.

## Local verification and limitations
New regressions first failed against baseline because progress was absent. Final staged tests use real original repository dependencies/workflow, not a replacement source-root fixture: public6PASS, transport9PASS, selected-media17run/16PASS/1existing local FFmpeg-pair-unavailable skip. Cases cover pre-body deadline, returned bytes crossing deadline, partial written chunks, socket exceptions, headers/overflow/incomplete transfer, privacy sentinel and cleanup. Required-tools failure policy is retained. A Windows offline test skip is not native/real decode acceptance.

Implementation and independent review are separate; root must verify frozen hashes, back up and apply only the scoped files before an exact new commit/run. One explicit diagnostic run may collect the new progress even when actual UI playback fails; its outcome is not a replacement for the original ordinary failure. No timeout increase, retry-until-green, smaller-prefix guess or player rewrite is included.

## Delivery boundary
This is an evidence-gap improvement, not a green-screen fix. Native final acceptance, same-prior-byte proof and direct private Web/mobile-network delivery remain open. No main synchronization, usable-link claim, success email or shutdown is implied.
