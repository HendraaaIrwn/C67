# Estimate coffee visit duration from branch evidence

Status: Ready for review

Branch: `hi/v52-eta-recovery`

## Outcome

Travellers see an appropriately short pickup or longer seated coffee estimate in Review, supported by a public source for the selected branch. Review asks for the visit intent when the longer visit would affect the verified itinerary.

## Scope

- Extend the authenticated Pocket order path with optional coffee branch address and website metadata for unedited coffee stops. Use its existing consent boundary and batched Luna request. Reuse the public web reader and include only branch-matched exact cited evidence in the returned coffee classification.
- Keep unknown service explicit. Use a provisional 15-minute pickup estimate and check a 50-minute alternative. Ask when the checked longer choice conflicts with the schedule or changes the selected order. Keep manual and scheduled-session durations authoritative.
- Show the estimate rationale and supporting source in Review. Keep the existing selectable duration path, and require a response before saving or starting while a material question is open.
- Verify the local server, contract, native scheduler, and synthetic app flow. Shared deployment and live venue validation are outside this implementation task.

[Native planning architecture](../architecture/decisions/0010-pocket-native-ui-integration.md) · [Pocket service](../../server/pocket/README.md) · [Order contract](../../contracts/api/openapi.json)

## Verification

Run the Pocket Python suite, contract checks, SwiftPM suite, and the focused Staging-mode iPhone Simulator Review test. Test accepted takeaway-only and seated branch evidence, reject generic takeaway and cross-branch evidence, and compare a tight and a roomy schedule.

## Result

- The local Pocket suite passed 72 tests. Its synthetic compact order produced different pickup and seated estimates from address-bound quotes and rejected generic takeaway and wrong-branch evidence.
- SwiftPM recorded 207 tests with one opt-in skip. The provisional visit fit in both test windows. The solver requested a choice when the 50-minute alternate conflicted and skipped the question when it fit with the same order.
- The focused iPhone 18 Pro Simulator Staging Review test passed with a synthetic Luna result. It showed the branch rationale and source link with no question for a verified branch.
- The API contract checker and `git diff --check` passed. The shared server has no deployment from this task. Real branch search, live Luna responses, and physical-device behavior remain unverified.
