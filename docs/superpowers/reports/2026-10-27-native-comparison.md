# Native comparison and reader-transition control, 2026-10-27

## Exact source and observed runs

Source582c131cfd2d2328fad7978a8401ebeff75ef5bb was tested twice, without changing source between them.

- Explicit diagnostics: https://github.com/wjc0104/xinxin-yuwen-garden/actions/runs/40454552797 overallSUCCESS. Actual31app tests incl9WK,7UI tests inclreader4orientations/menu-return/relogin/note draft, realnative720source/audio/seek, actualdiagnosticplaybackUI allPASS. All3initial+5pausedUI images were visually normal with changing textbook/instructor content; paused48.103049059s, sameplayer/item/controller,1.5x running enter/exit and2x selection without resuming all retained. Independent visual and numerical reports were saved locally.
- Counterexample retained: same-item-render/g1-s4.png is visibly darkgreen with instructor outline, while s1-s3normal. It maps to initial-inline-playing-4 (receiptseq4), not fullscreen dismissal. ReturnedPTS20.533/current24.678 differ4.145s; buffer requesthost1265.001748792 and screenshot1265.745..1265.943 are not synchronous. Do not claim all buffers normal, samePTS or resolved green-frame root cause.
- Independent triage is INCONCLUSIVE/network_deadline, cleanupVerifiedtrue and priorBytesEqualityEstablishedfalse. A successful advisory step exit is not independent decode or three-way comparison success.
- Ordinary diagnostics-off control: https://github.com/wjc0104/xinxin-yuwen-garden/actions/runs/40457202110 failed deterministic UI before actualplayer/triage execution.31app incl9WK passed; exactsearch andpoetrylogin passed. This is NOT an ordinary player PASS/FAIL.

## Ordinary primary failure boundary

The first leftlandscape completed rotation, geometry and screenshot: app852x393, web734x201.667, options44pt andhittable. The next options.tap blocked in two60s animation-idle waits, reported missing app-animation-complete notification and exceeded120s execution allowance. Spindump runner stack is options.tap -> _waitForQuiescenceAsPreEvent -> waitForQuiescenceIncludingAnimationsIdle. App355/355 andWebContent355/355 main-thread samples were runloopidle (AppCPU below0.001s), not evidence of a JS busyloop. This localizes the dependency but does not establish a pureXCTest defect or rule out app-transition problems.

After runnerkill/restart, landscapeorientation leaked into later tests; the timestamp field became nonhittable with keyboard. This may be secondary contamination, but a real compactheight editor issue is not excluded without a clean baseline. No speculative VideoStudyView/publicpoetry rewrite was made.

## Bounded transition experiment, not production fix or acceptance

- Add a DEBUG-only public UIView.setAnimationsEnabled(false) branch, requiring ALLthree explicit arguments: --ui-testing, --ui-testing-poetry-layout, --ui-testing-reader-static-transitions. The finalargument is supplied ONLY to the original four-direction syntheticreader test. A fixedcontent NSLog marks activation. OtherUItests, ordinaryactualplayer andRelease do not disable animations. No global simulator preference or privatequiescence API.
- EveryUItest begins withportrait state isolation. Timestamp test additionally waits for actualportrait app.frame afterlaunch/relaunch and fails ifnotrestored; actualinput/type/save assertions remain.
- Existingfourorientation/space/44pt/realquery/tap/hittable/menu/guidance gates, playerhelpers andoriginaltimeouts remain. This does not waive rotation or actualvideo evidence, and an experimentPASS does not acceptrelease-state animation behavior.
- Staging static invariants andindependent limitedreview found no concreteP1/P2; no Swift/native success was claimed beforethe newexactcommitrun. Root verifiedbaseline/candidateSHA256 andbackedup bothfiles beforeapply. A newordinaryrun must inspect realresults; do not blindlyrerun or greenwash.

## Delivery status

Main not synchronized. Native finalacceptance, greenbuffer rootcause andusable directprivateWeb delivery remain incomplete. No successful link email or shutdown. Privatehosting, WiFi/mobile plusproxyon/off andiOS15 physicaldevice behavior are not inferred fromrunner tests.
