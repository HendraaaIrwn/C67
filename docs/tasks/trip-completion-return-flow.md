# Task: Complete return-to-start trips after the final visit

- Status: Ready for review
- Owner and reviewers: iOS and Pocket maintainers
- Branch: `hi/v52-eta-recovery`

## Outcome

Finishing the final visit opens Trip complete. The summary offers directions back to the saved starting point on a map in Travelants.

## Scope and dependencies

- Pocket trip completion and restoration, the native trip progress screen, and focused regression checks.
- Route estimates still include a planned return leg when the itinerary requires one. A distinct custom endpoint still requires arrival.
- Verification uses synthetic trip data. External actions authorized: none.

## References

[Trip complete summary](trip-started-layout.md#follow-up-trip-complete-summary) · [Pocket integration](../guides/pocket-engine-integration.md)

## Acceptance criteria

- [x] Finishing the last stop on a return-to-start trip immediately shows Trip complete, optional return directions, and Done.
- [x] Previously saved trips waiting only for a return to their origin reopen as completed, retaining visit history.
- [x] A distinct custom endpoint still supports confirmation after the last visit.

## Verification plan

Run C67Backend tests, the focused C67 app unit and Simulator UI tests, a generic Simulator build, the pinned Swift formatter check, and the diff whitespace check.

## Result and handoff

Pocket records completion together with the last visit when the trip ends at its starting point. It applies the same rule while reading older local trips and their saved command results, preserving trip revision and recorded visit times. A distinct custom endpoint continues to use the endpoint arrival screen.

- `swift test --package-path packages/C67Backend` passed with 199 tests reported and one opt-in skip. Coverage includes active replans and restoration of a legacy return trip.
- Two focused UI tests passed in mock configuration on iPhone 18 Pro Simulator (iOS 27.2). One completed a three-stop synthetic Pocket trip and dismissed the summary with Done. The other checked the summary's return-directions preview callback. Result bundle: `/tmp/c67-trip-completion-final.xcresult`.
- The custom-endpoint app test passed in mock configuration on iPhone 18 Pro Max Simulator (iOS 27.2). It confirmed persisted progress, a distinct endpoint, and completion on arrival. Result bundle: `/tmp/c67-trip-completion-unit.xcresult`.
- The generic iOS Simulator build passed with code signing disabled.
- `git diff --check` passed. The repository-wide SwiftFormat check reported existing issues in 20 files. The changed Swift lines produced no diagnostics.

## Physical iPhone verification — 25 November 2026

The latest signed Debug staging build installed over the existing development app on iPhone 17 (iOS 27.2.1). The test used an isolated synthetic Pocket trip and the real Apple Maps app. The local development profile omitted WeatherKit and Sign in with Apple entitlements.

XCUITest confirmed that Finish last visit opened Trip complete directly. Tapping Return to starting point foregrounded Apple Maps, which displayed driving directions from My Location to Starting point and was loading routes at capture. Result bundle: `/var/folders/yj/ty_bvsbx3szcfgx5dr91mrbc0000gq/T/c67-device-completion.l8eflo5t/physical-trip-completion.xcresult`.

## Follow-up: Return route inside Travelants

The return action opens a dismissible MapKit sheet above Trip complete. The destination is the saved trip origin. The sheet shows the route line, travel mode, distance, estimated time, and the first available instruction. It uses device location when available and identifies the last visited stop when showing the fallback route. Closing the sheet returns to the completion summary.

The generic iOS Simulator build and three focused XCUITests passed on iPhone 18 Pro Simulator (iOS 27.2). The synthetic Pocket test verified that the app stayed in the foreground and Close restored Trip complete. The preview tests verified the map and sample estimate, and the summary controls at an accessibility text size in Dark Mode. Result bundle: `/tmp/c67-in-app-return-route.xcresult`.

The repository-wide SwiftFormat check reported 19 files with existing diagnostics. The changed Swift lines produced no diagnostics. The diff whitespace check passed.

The signed Debug staging build installed over the existing development app on iPhone 17 (iOS 27.2.1). The physical XCUITest used a synthetic Pocket trip and a simulated public position in Blok M. Live MapKit rendered a route to the starting point with a 740 m distance, a four-minute driving estimate, and a first turn instruction. Travelants stayed in the foreground and Close restored Trip complete. The test cleared the simulated position after the run. Result bundle: `/var/folders/yj/ty_bvsbx3szcfgx5dr91mrbc0000gq/T/c67-device-completion.l8eflo5t/physical-in-app-return.xcresult`.

C67Backend reported 203 tests with one opt-in skip.

## Follow-up: Match the active trip navigation layout

The return route uses the same blue instruction banner, route focus control, distance and ETA metrics, and floating panel as navigation between stops. It opens full-screen from Trip complete. Back to summary closes the map and restores the completion summary. Return directions still use the saved origin and the trip’s travel mode.

The generic Simulator build and four focused XCUITests passed on iPhone 18 Pro Simulator (iOS 27.2). Coverage includes the shared active-trip controls, return layout, closing the route in the Pocket flow, and reaching Back to summary in Dark Mode at accessibility XXXL. The final Light Mode screenshot shows the full-screen map and the white label on the blue return button. Result bundle: `/tmp/c67-return-navigation-final.xcresult`.

The diff whitespace check passed. The repository-wide SwiftFormat check reported existing formatting diagnostics in 19 files.

The signed staging build installed on physical iPhone 17 (iOS 27.2.1). The live-route test showed the full-screen map, maneuver banner, route focus control, 740 m distance and four-minute driving estimate, then returned to Trip complete. It used a synthetic trip and a simulated position in Blok M. The final build with the white button label passed the physical design-preview test. Other device automation interrupted two attempts to repeat the live-route scenario on that final build.

The physical result bundles are `physical-return-layout-final.xcresult` for the live-route test and `physical-return-layout-preview.xcresult` for the final preview. They are under `/var/folders/yj/ty_bvsbx3szcfgx5dr91mrbc0000gq/T/c67-device-completion.l8eflo5t`.
