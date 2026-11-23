# Task: Play the four-second Travelants splash on iOS

Status: Ready for review
Owner: iOS
Branch: `codex/travelants-splash-login`

## Outcome

Play the approved four-second logo sequence once when opening Travelants, then fade the splash out over 320 milliseconds to reveal the existing entry screen.

## Scope and dependencies

- App entry, the splash module, its bundled video, and focused app and UI verification.
- Use the supplied silent MP4 at its authored timing. Keep the native launch canvas continuous with the in-app splash.
- Run local Simulator checks with synthetic mock data.

## References

- [Approved Figma prototype](https://www.figma.com/proto/LAHLd1gDy3UQEWhwdQHPzM/Travelants02?node-id=31-1323&starting-point-node-id=31%3A1323&page-id=3%3A17&scaling=scale-down)
- [iOS UI](../../apps/ios/README.md) and [design system](../product/design-system.md)

## Acceptance criteria

- [x] Pin Portal begins with the pin alone. The route advances from the bottom waypoint and each of the three blue dots pulses as it appears. Thread Through follows the completed route.
- [x] The four-second bundled movie plays once, then fades out over the existing entry screen. A missing or failed movie cannot prevent entry.
- [x] Reduce Motion and the established DEBUG `--skip-splash` flag bypass playback.

## Verification plan

Build with Xcode, check the video metadata in the app test host, and exercise launch and handoff on an iPhone Simulator in mock mode. Inspect the running animation and its three pulses. Run Swift formatting and whitespace checks.

## Result and handoff

- The approved MP4 is bundled byte for byte and has a four-second, 60 fps video track with no audio. Playback waits for the movie to end and falls back to the entry screen on failure or after a five-second deadline.
- The default cold launch and the DEBUG skip path passed on iPhone 18 Pro Simulator (iOS 27.2, mock data). The run passed 35 app and UI tests. Result bundle: `/tmp/c67-splash-playback-v2.xcresult`.
- The simulated cold launch showed the pin-only portal, all three pulses, the thread after route completion, and the Trip screen. Capture: `/tmp/c67-splash-evidence/pulse-samples.png`.
- The fade follow-up passed 10 app tests and the mock cold-launch UI test on iPhone 18 Pro Simulator (iOS 27.2). The captured transition shows Trip appearing underneath the fading splash. Capture: `/tmp/c67-splash-evidence/fade-samples.png`. Result bundle: `/tmp/c67-splash-fade.xcresult`.
- Restoring the original artwork and centered tile passed the generic Simulator build, 10 app tests, the cold-launch UI test, and 158 C67Backend tests. The restored movie matches the approved export byte for byte. A mock cold-launch capture on the same Simulator confirmed the tile and fade into Trip. Capture: `/tmp/c67-splash-evidence/restored-contact.png`. Result bundle: `/tmp/c67-splash-restore.xcresult`.
- The generic Simulator build, all 158 C67Backend package tests, the pinned formatter on the four changed Swift files, and `git diff --check` passed. Repository-wide formatting still reports eight pre-existing files.
- The system Reduce Motion toggle and physical devices were outside this Simulator run.
