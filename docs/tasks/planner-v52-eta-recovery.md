# Recover v5.2 schedules using observed ETAs

- Status: Ready for review
- Owner: Hendra / coding assistant
- Reviewers: Unassigned
- Branch: `hi/v52-eta-recovery`

## Outcome

When the initial v5.2 search fails, check a small number of additional candidates guided by ETAs from the same search. Explain missing route estimates and exhausted search limits with distinct messages.

## Scope and dependencies

- Native v5.2 scheduling, route failure messaging, and regression coverage. Use one ranked recovery list and the existing exact evaluator, budget, cancellation, and route session.
- Verification uses deterministic package fixtures, the iOS Simulator, and an isolated benchmark on the connected physical iPhone with public pins and live MapKit. See the [research report](../research/planner-v52-reliability.md).

## Acceptance and verification

- Recover the flexible museum example with the original wait cap while preserving successful first-pass schedules, fixed departure, order locks, and the endpoint.
- Keep incomplete searches distinct from established conflicts. Verify ETA-unavailable and budget outcomes at the repository boundary.
- Run package tests, the pinned Swift layout check, the relevant app checks, and the museum and six-stop scenarios on the physical iPhone.

## Result and handoff

v5.2 now generates one recovery shortlist only after the initial search returns no complete itinerary. The shortlist uses nearby, directed ETAs from the same command. It checks up to four new candidates with at most 12 fresh quotes within the original 72-quote cap. The original evaluator checks every selected stop and the final leg at the actual estimated departure minute. Missing MapKit estimates and an exhausted search limit have distinct recovery messages. The previously tested ranking refresh is deferred.

The signed Release benchmark on physical iPhone 17 / iOS 27.2.1 ran both cases through the updated `PocketPlanningRepository` and the native MapKit ETA adapter. It used the same public pins and controlled visit constraints as the [prior comparison](../research/planner-v52-reliability.md#live-mapkit-comparison-on-physical-iphone).

| Live MapKit scenario | Repository time | ETA calls | Verified itinerary |
| --- | ---: | ---: | --- |
| Blok M MRT to Museum Polri | 1.052 s | 5 | Depart 08:49, arrive 08:55, visit 09:00–09:30, wait 5 minutes |
| Six stops with required return | 2.979 s | 16 | Depart 08:51, return to Blok M at 12:43 before 13:25, wait 3 minutes |

All calls returned usable MapKit estimates. Both cases recovered on the first additional candidate. Independent exact-minute replay confirmed every selected visit, first-stop constraints, and the required return. The trace preserved the previously observed first-search paths of four and nine quote keys. The two latency observations include the repository job polling interval and may vary with the provider. The benchmark is installed under its own bundle identifier. Evidence: `/tmp/travelants-production-iphone.AF2NCo/production-result-pair-2.txt`.

- `swift test --package-path packages/C67Backend` passed 197 tests and skipped one opt-in benchmark. The new checks cover the recovered departure and return, fixed departure and unchanged first-pass success, revalidation with changed ETA, and the separate missing-ETA and route-budget messages.
- The focused v5.2 itinerary and save test passed on iPhone 18 Pro Max Simulator / iOS 27.2. The broader mock check on iPhone 18 Pro Simulator passed 63 of 66 tests. The two selection-limit unit tests and the automatic itinerary UI test failed at the same assertions on unmodified `1f5ed76`. The UI test stopped at Recommendations with two selected places.
- `git diff --check` passed. The pinned formatter reported no findings on changed Swift lines or new Swift files. Its repository-wide check still reported existing layout findings in 20 files.
- The changes are local on `hi/v52-eta-recovery`. Commit, push, and release distribution remain pending.

## Physical Travelants UI follow-up

A signed Debug build of Travelants was installed on the physical iPhone 17 / iOS 27.2.1 under the separate development bundle ID `io.hendrairawan.c67.recoveryui`. Its ordinary launch uses the on-device Pocket mode. The test build used isolated launch flags to populate the public pins and controlled visit constraints, then left generation and review to the actual app UI, production repository, and live MapKit adapter. The fixture and UI tests were built from a temporary copy.

Both XCUITests passed through Home → Add Specific Place → Main spot → Itinerary Review. Museum Polri appeared in the review timeline at the proposed 08:49 WIB departure. The six-stop review showed all six selected places and a proposed 08:51 WIB departure. The tests ended at review before saving. Result bundle: `/tmp/travelants-device-ui.uF82Zv/physical-review.xcresult`. Review screenshots: `review-evidence/review-museum.png` and `review-evidence/review-six-stops.png` under the same temporary directory.
