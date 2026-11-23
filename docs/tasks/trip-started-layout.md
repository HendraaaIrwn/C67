# Task: Refine the active trip layout

- Status: Ready for review
- Owner: iOS maintainers
- Branch: codex/trip-progress-polish

## Outcome

The active trip map follows the TRIP STARTED reference. The blue banner presents the first available route step, and the floating lower panel presents travel estimates, the current stop, and trip controls.

## Scope and dependencies

- The native map continues to use MapKit. The banner labels the first calculated step as a route preview. The external Apple Maps action opens directions for live guidance.
- The panel shows planned estimates when the current route is unavailable and retains location recovery and manual arrival. It fits its content and scrolls when accessibility text needs more room.
- The two lower actions use the existing Back to trip and I’m here behavior. Trip lifecycle operations and geographic weather overlays are outside this visual change.
- The design preview uses labeled sample route geometry and estimates.

## References

[Design system](../product/design-system.md) · [iOS feature overview](../../apps/ios/README.md)

## Acceptance criteria and evidence

- [x] At default text size, the panel stays compact and shows the current stop plus reachable, aligned actions.
- [x] Navigation and arrival actions remain accessible with large text in Dark Mode.
- [x] Starting a synthetic Pocket trip shows the current stop and usable controls when location is unavailable.

## Verification

Four focused C67 UI integration scenarios passed on iPhone 18 Pro Simulator (iOS 27.2), with sample route data in the design preview and the synthetic Pocket flow for the unavailable-location state. The result bundle is `/tmp/c67-trip-started-refined.xcresult`. Live routing and physical-device behavior were outside the run.


## Follow-up: Planned starting point while GPS is pending

The first leg uses the saved trip origin as a clearly labeled map marker and fallback route origin when a fresh device position is unavailable. Active trip navigation still requests device location. A live route takes priority when it becomes available, and automatic arrival continues to use only fresh device location samples. Later legs keep their existing navigation behavior.

Two focused integration scenarios passed on iPhone 18 Pro Simulator (iOS 27.2). The synthetic Pocket flow checked the labeled starting point, planned metrics, and manual arrival availability without GPS. The design-preview scenario checked route and arrival controls. Live MapKit route calculation was outside the synthetic flow. Result bundle: `/tmp/c67-trip-planned-origin-final.xcresult`.


## Follow-up: Approved destination-first layout

The active panel uses the approved destination-first composition, a solid adaptive surface, and paired travel metrics. The blue banner shows maneuver distance first and route provenance below the instruction. Waiting for GPS and Try again share one row at standard text sizes. Three focused UI integration scenarios passed on iPhone 18 Pro Simulator (iOS 27.2), covering layout, Dark Mode at accessibility size, and the synthetic no-GPS state. Result bundle: `/tmp/c67-trip-started-approved-layout.xcresult`.


## Follow-up: Arrival planned visit window

The Arrival panel shows the itinerary’s start and end times using the trip’s time zone and the approved dot-separated format. It retains the blue confirmation, green map marker, next stop, and trip actions. It uses the same estimated schedule as the itinerary when the stop has no stored window and an experience estimate is available.

Three focused UI integration scenarios passed on iPhone 18 Pro Simulator (iOS 27.2). They covered the rendered time range, accessibility text in Dark Mode, and proceeding to the next stop through Pocket after confirming arrival. The separate legacy trip-creation scenario stopped before the itinerary screen. Result bundles: `/tmp/c67-arrival-visit-window.xcresult` and `/tmp/c67-arrival-visit-window-pocket.xcresult`.

The Up next row displays the travel estimate without the approximation symbol. The Pocket arrival integration passed on iPhone 18 Pro Simulator (iOS 27.2), including advancing to the next stop. Result bundle: `/tmp/c67-arrival-estimate-label.xcresult`.

## Follow-up: Trip complete summary

The approved summary centers the confirmation and trip identity. Visited stops use a separate trailing time column at standard text sizes. The completion icon, headings, rows, and actions animate in sequence with an immediate presentation when Reduce Motion is enabled.

Pocket and the in-memory mock retain the recorded arrival time when each stop is completed. The summary displays those times in the trip's time zone and omits times when the saved record has no arrival history. The legacy HTTP contract is unchanged. The Return to starting point action opens Apple Maps at the trip's saved origin using the selected travel mode. Done dismisses the summary.

Three UI integration scenarios passed on iPhone 18 Pro Simulator (iOS 27.2). They covered the time-column alignment, action order and preview callback, both actions in Dark Mode at accessibility XXXL, and completing a three-stop synthetic Pocket trip with recorded times. Live Apple Maps directions were outside the run. Result bundle: `/tmp/c67-trip-complete-motion-final.xcresult`.

The completion mark now uses a bundled Lottie vector that draws the checkmark and settles the green circle once. Reduce Motion and missing-asset fallback show the static mark. Two UI integration scenarios passed on iPhone 18 Pro Simulator (iOS 27.2), covering the summary layout and action reachability at accessibility XXXL in Dark Mode. Result bundle: `/tmp/c67-trip-complete-lottie.xcresult`.

The Lottie mark starts after the final summary entrance has settled and a brief pause has elapsed. The vector plays over approximately 1.17 seconds. The two focused UI integration scenarios passed again. Result bundle: `/tmp/c67-trip-complete-lottie-delayed.xcresult`.
