# Estimate v5.2 visit durations on device

Branch `hi/v52-eta-recovery`

Status ready for review

## Outcome

Travelants v5.2 estimates visit lengths from a selected activity or a place category on the iPhone. Review shows the chosen duration and its basis per stop. A shorter activity can be applied after a complete schedule check and explicit approval.

## Scope

- Respect scheduled sessions and traveller-entered durations before applying local estimates. Category defaults are 75 minutes for museums, 35 for parks, 60 for restaurants, 30 for cafés, and 45 for a general visit.
- Use the same duration rules for places added through search and recommendations. Skip Luna for automatic duration selection. Preserve the visit lengths already reviewed when refreshing ETAs or starting a saved trip.
- When a duration conflicts with the schedule, check up to two shorter activities with the available route budget. Show only a choice with a complete itinerary through the final leg. Ask for a new calculation after approval because route estimates can change.

[Pocket integration](../guides/pocket-engine-integration.md) · [Verification](../testing/verification.md)

## Verification plan

- Use synthetic Museum Polri records to test the category estimate, a 30-minute manual duration, and a 30-minute scheduled session.
- Test the café category estimate and both selected activities. Exercise the duration editor and Review in Staging app mode on Simulator.
- Check six stops with a return deadline, first with a complete set of ETAs and then with the return ETA missing. Exercise the approval flow through Review on Simulator.

## Results

- The C67Backend suite recorded 215 tests and one opt-in benchmark skip. Synthetic checks covered Museum Polri at 75 minutes, manual and scheduled 30-minute visits, the café activity choices, park and restaurant rules, and eligibility for the shorter six-stop route with and without its return ETA.
- Three UI tests passed on iPhone 18 Pro Simulator with iOS 27.2. They covered automatic planning without an AI prompt, duration explanations and café activity edits, and retaining all six stops after explicitly accepting a 45-minute museum visit. The C67 scheme ran the tests with synthetic inputs. The C67 Staging scheme built successfully in the Staging configuration for Simulator.
- The contract check and `git diff --check` passed. The whole-repository SwiftFormat check continues to flag files in the working tree.

## Physical iPhone verification

The signed C67 Staging Debug Run build was installed in place and launched without test flags on iPhone 17. Live UI verification used the same planner in a separately signed C67 Staging test app with in-memory storage. All selected places and POI categories came from native MapKit search on the iPhone. Every route estimate used native MapKit. The test set the Blok M MRT origin and the trip window. It used a controlled 65-minute Museum Polri access window for the six-stop case. Pocket opening-hours lookup was outside this test.

- Museum Polri showed **75 min · Estimated for a museum visit.**
- Filosofi Kopi showed **30 min · Estimated for a café visit.** Choosing pickup produced 15 minutes and choosing to sit produced 45 minutes, with the traveller's choice shown as the reason.
- The six-stop solver offered **One exhibition** at Museum Polri for 45 minutes in place of 75. Dismissing the option left Review blocked. The first recalculation after approval displayed the missing-travel-time notice. Its native MapKit trace recorded a burst limit of 50 ETA requests per 60 seconds and a 43-second reset time on the failed request.
- The six-stop replay reproduced the rate limit on immediate approval. A separate replay waited 55 seconds with the option visible, then approved once and reached Review on the first post-approval check. Review showed Museum Polri at 45 minutes for one exhibition, Tiahahu Literacy Park at 35 minutes for a park visit, Filosofi Kopi at 30 minutes for a café visit, and M Bloc Space, Blok M Square, and Plaza Blok M at 45 minutes each as general visit estimates. The test confirmed all six visit rows and their reasons. The test app was removed and ordinary C67 Staging returned to the foreground without test flags.

## Reuse the route when approving a shorter visit

Keep the solver-verified alternative in memory for the pending planning job. Explicit approval uses the existing planning command and creates a normal Review proposal with the original verified route, departure, and ETA timestamps. Reuse requires the same effective planning input, the same pending failed job, a verified route checked less than two minutes ago, and a departure minute that is still current or future. A stale result, changed input, or changed session goes through the normal route calculation.

The C67Backend suite recorded 216 tests and one opt-in benchmark skip. The new regression tests verified zero additional travel calls for a matching approval in both trip creation and Review editing. They also checked exact request replay and fresh route calls for an expired result, a changed origin, a session change, and a matching duration entered without explicitly approving the offered alternative.

The six-stop Simulator UI test confirmed that dismissing the option leaves the trip blocked and that accepting it opens a Review with all six stops. The approval action starts after the schedule-details sheet dismisses so a fast response can navigate cleanly.

The final C67 Staging native UI replay passed on iPhone 17 (iOS 27.2.1) using live MapKit search and ETA. With the same controlled 65-minute Museum Polri access window, dismissing the option left Review blocked. One approval opened Review in 3.27 seconds with all six durations and reasons. The trace recorded 51 scheduling ETA attempts during validation of the option and zero from approval through test teardown. The test used no cooldown or Retry action. The separately signed ordinary C67 Staging build was then installed in place and launched without test flags.
