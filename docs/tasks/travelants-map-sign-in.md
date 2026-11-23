# Task: Apply the Travelants map sign-in design

- Status: Ready for review
- Owner: iOS
- Branch: `codex/travelants-splash-login`

## Outcome

Apply the selected Peta Perjalanan concept to the Travelants sign-in screen and capture the implemented screen in Light and Dark appearance.

## Scope and dependencies

- Authenticated Pocket entry screen, local map illustration, and generated Xcode project membership.
- Existing Apple sign-in, review sign-in, privacy, and account-deletion recovery actions.
- Local Simulator builds and synthetic account fixtures.

## Acceptance and verification

- Match the selected map artwork and sign-in hierarchy in both appearances.
- Keep the native Apple control and existing sign-in entry points usable with larger text.
- Build for Simulator, run focused account and splash UI tests, capture both appearances, and check Swift formatting and whitespace.

## Implementation

The sign-in screen uses a decorative map drawn locally in SwiftUI and an appearance-specific Travelants mark. The screen responds to Dynamic Type and scrolls when its content grows. The existing account root owns authentication and session recovery, including the App Review entry point and account-deletion status.

## Result and handoff

- The Xcode 27.2 generic Simulator build and all 158 C67Backend tests passed.
- On iPhone 18 Pro Simulator (iOS 27.2), two Apple sign-in unit tests and six mock UI tests passed. The UI run covered launch, sign-in entry, privacy, App Review sign-in and session restoration, and both deletion paths. The Apple deletion flow returned to a usable sign-in screen at Accessibility XXXL.
- Captured and inspected the installed C67 app in Light and Dark on iPhone 18 Pro and iPad Pro 11-inch (M5), both on iOS 27.2. Captures used the synthetic Pocket auth and privacy fixtures. Screenshots and the test result bundle are in `/tmp/travelants-login-implemented/`.
- The affected Swift files pass the pinned formatter. The repository-wide check reports eight existing files outside this change.
- Physical devices and live Apple authorization were outside this run.
