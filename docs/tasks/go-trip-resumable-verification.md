# Resume Go Trip route verification

Status: Ready for review

Branch: `hi/v52-eta-recovery`

## Outcome

An otherwise valid saved trip can start after one temporary MapKit failure. If verification still fails, Try again reuses any exact successful quotes that are still valid for the same trip revision.

## Scope

- Apply the retry policy only to verification before starting a saved flexible schedule. Preserve the saved stop order and verify all access, waiting, check-in, and deadline constraints with the existing evaluator.
- Use a 25-second overall deadline, with up to seven seconds per ETA request and at most one automatic retry for the whole attempt. Confirmed throttling and unclassified failures skip the automatic retry.
- Keep valid quotes in memory for up to 90 seconds. Match the trip revision and configuration, directed leg, and requested departure minute. Reset or reject stale progress when the trip or account scope changes.
- Use the Museum Polri and six-stop public coordinates from the ETA task with synthetic travel times and injected return-leg failures. Add the return to Blok M MRT to the museum fixture for this check. Build and install the local `C67 Staging` Run build on the iPhone.

[Earlier v5.2 route recovery](planner-v52-eta-recovery.md)

## Verification plan

Run the package scenarios with one failed return lookup, a failed automatic retry followed by Try again, a changed departure minute, explicit throttling, and a recovered ETA that misses the deadline. Verify the existing Start confirmation in the Simulator and install the signed Staging-mode app on the physical iPhone.

## Results

| Synthetic route with one injected return timeout | ETA requests during Go Trip | Result |
| --- | ---: | --- |
| Blok M MRT → Museum Polri → Blok M MRT | 3 | Both route legs verified and the trip became active. The museum visit ended at 09:30 WIB. |
| Six stops with return to Blok M MRT | 8 | All seven legs verified and the trip became active. Only the return ETA was requested twice. |

- On a six-stop run where both automatic return requests failed, Try again issued one fresh ETA in the same departure minute. Moving the first departure forward a minute required two fresh requests because the museum wait kept the later departure minutes the same. Separate fixtures verified throttling, unclassified failures, and the return deadline.
- SwiftPM passed with 203 tests recorded, including one opt-in skip. The iPhone 18 Pro Simulator UI test reached active trip after the existing start flow. The live failure itself was simulated by the package tests.
- The signed `C67 Staging` Debug Run build embedded staging mode and installed and launched on iPhone 17 under `io.hendrairawan.c67.recoveryui`. Signing reused the development provisioning profile from the previous device tests. This verified the physical launch. The failure scenarios ran in the package suite with controlled ETAs.
- `git diff --check` passed. Repository-wide SwiftFormat still reports existing issues outside the newly edited lines.

## Physical Staging UI with live MapKit

The physical iPhone 17 / iOS 27.2.1 tests use the `C67 Staging` scheme and a separately signed test bundle with memory-only trip storage. The harness sets the Go Trip clock to one minute after the saved departure on 26 November 2026 WIB. It supplies the public pins and venue constraints, then throws one timeout at the first return ETA call during Go Trip. The retry and each other ETA request go to native MapKit. The tests use the app UI to plan, save, and start each trip.

| Route | Saved → verified departure (WIB) | ETA calls after one Go Trip tap | Confirmation | Active after confirmation | Verified return |
| --- | --- | --- | ---: | ---: | --- |
| Museum Polri | 08:49 → 08:50 | 2 live and 1 injected timeout | 1.54 s | 4.42 s from Go Trip | 09:36 WIB |
| Six stops | 08:51 → 08:52 | 7 live and 1 injected timeout | 2.59 s | 5.86 s from Go Trip | 12:43 WIB |

Only the return leg was requested twice in each run. Museum Polri → Blok M MRT at 09:30 WIB returned a live ETA of 316 seconds after the injected timeout. Taman Bendera Pusaka → Blok M MRT at 12:39 WIB returned 240 seconds on retry. The trip remained planned at the **Start with this schedule** confirmation in both cases. The tests used one confirmation tap and observed active status and the active arrival UI. The first six-stop run was interrupted by the isolated test app's iOS location prompt before route verification. The independent replay passed with the original itinerary constraints.

## Start directly after a small timing adjustment

After the existing route and schedule validation, Go Trip activates directly when the itinerary stays on the same date and its departure, stop timing, travel estimates, and finish move by at most five minutes. The origin, mode, endpoint, ordered stops, and visit durations must match, and no check-in buffer shortfall may worsen. Larger changes require the existing confirmation. Trips whose dates or constraints fail validation remain blocked by the existing checks.

Verification covers the five-minute boundary, six-minute confirmation, material changes despite a small departure shift, and the two physical Staging UI scenarios with one injected return timeout and live MapKit elsewhere.

| Physical iPhone 17, C67 Staging | Saved → verified departure (WIB) | ETA calls after Go Trip | Go Trip to active |
| --- | --- | --- | ---: |
| Museum Polri | 08:49 → 08:50 | 2 live and 1 injected timeout | 1.53 s |
| Six stops | 08:51 → 08:52 | 7 live and 1 injected timeout | 2.49 s |

Both scenarios became active after exactly one Go Trip tap with zero confirmation and manual retry taps. The return leg retried at the same departure minute. The physical suite passed both tests in one run, and the ordinary updated Staging build was then installed and launched without test flags. SwiftPM recorded 205 tests with one opt-in skip. The focused iPhone Simulator app test confirmed that the larger same-day change still required confirmation.

## Physical controls for a material shift and a conflict

- Six stops, valid six-minute shift. The test moved departure from 08:51 to 08:45 WIB on 26 November. All seven Go Trip ETA calls used live MapKit. The return at 12:43 WIB remained before the 13:25 deadline. **Start with this schedule** appeared after 1.75 seconds. The trip stayed planned at revision 1 until one confirmation tap made it active at revision 2.
- Museum Polri, return deadline conflict. At the 09:30 WIB return the test added 15 minutes once to the 316-second live MapKit ETA, producing a 1,216-second ETA and a rounded finish at 09:51 WIB, beyond the 09:40 deadline. The app showed **Itinerary needs attention** with the time-window message and no start confirmation. The repository reported `V4_WINDOW_TOO_SHORT` / `return_deadline_exceeded` and left the trip planned at revision 1.

Both controls passed on iPhone 17 / iOS 27.2.1 using the `C67 Staging` scheme and the isolated test bundle. Venue constraints and deadlines remained in force. The ordinary staging build reopened without test flags.

## Explain the return deadline conflict

For a fixed Go Trip itinerary whose final leg breaches the deadline, retain the last stop, calculated arrival, and actual deadline in the planner failure. Render the route and both times in the trip time zone. Use the saved endpoint name when available and the starting point label for an unnamed return. Keep the existing general error for other scheduling conflicts.

Verification checks the leg identifier and both times in the package fixture, then checks the visible notice and planned status in the physical Museum Polri scenario with an adjusted live ETA.

The final `C67 Staging` replay passed on iPhone 17 / iOS 27.2.1. One Go Trip tap displayed Museum Polri → starting point, estimated arrival 09:51, and deadline 09:40 in the notice after 1.65 seconds. The harness added 15 minutes to the 316-second live MapKit return ETA. The trip remained planned at revision 1 without a start confirmation. SwiftPM recorded 205 tests with one opt-in skip. The signed ordinary Staging app was then installed in place and launched without test flags.

## Show the selected starting point name

The on-device planning input now keeps the selected starting point name with its coordinates and saves it with the trip. Go Trip uses it for a return notice. Existing trips with no saved name still use the starting point label. Changing the origin invalidates the previous name, and using the device position clears any selected name. The server request representations are unchanged.

Verification covers capturing the name in the app draft, restoring it from a saved trip, decoding an earlier input with no name, and the named Museum Polri conflict on physical Staging.

The focused iPhone Simulator app test and the package persistence test passed. SwiftPM recorded 206 tests with one opt-in skip. The iPhone 17 / iOS 27.2.1 Staging replay seeded the selected name and used the normal Save flow. The notice displayed Museum Polri → Blok M MRT with 09:51 estimated arrival and a 09:40 deadline after the live return ETA was extended by 15 minutes. The trip stayed planned. The ordinary Staging build was installed in place and launched without flags.
