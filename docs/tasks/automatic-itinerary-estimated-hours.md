# Use estimated opening hours in automatic itineraries

Status: Ready for review

Branch: `hi/v52-eta-recovery`

## Outcome

An automatic itinerary created late in the day can suggest tomorrow when the visits fit typical opening hours better on the next date.

## Scope

- Reuse the existing category estimates in the on-device v5 scheduler when venue hours are unavailable. Prefer less time outside those windows and keep the access status unverified.
- Compare tomorrow for an automatic first itinerary if the selected schedule falls outside estimated hours. Use the existing date and route checks. Preserve fixed dates, confirmed visits, and regular opening hours.

[Product behavior](../../README.md) · [Existing guidance on opening hours](hours-hybrid-integration.md)

## Verification

The repository integration test uses a synthetic 16:00 request in Jakarta with three museums. It checks that automatic planning selects the next date within estimated museum hours, that a manually requested 19:30 departure stays on the selected date, and that reported regular hours can support a same-day itinerary. The automatic case reproduced the same-day schedule before the fix. Live venue hours and the trip reported by the traveller were outside this check.

`swift test --package-path packages/C67Backend` completed with 208 tests recorded and one opt-in skip. The generic iOS Simulator build and `git diff --check` passed. The repository-wide SwiftFormat check still reports findings in 19 files, outside the lines added by this change.

## Follow-up: check the complete itinerary before requesting routes

The v5 scheduler now checks whether an allowed visit order fits using zero travel and unrestricted waiting before it requests route estimates. A schedule that passes this check still needs departure-specific route validation. If no order fits, a second check omits weekly hours while retaining confirmed access, required times, and order locks. This distinguishes a conflict with regular hours from incompatible required constraints without assigning a trip-wide conflict to individual venues.

An automatic first itinerary can try tomorrow when the available regular hours cannot accommodate the visits or the day is too short. Estimated hours continue to inform ranking and remain labeled unverified. An estimate alone leaves the date in place. Fixed dates and dated commitments retain their existing rollover guards.

Synthetic repository regressions cover overlapping opening windows, venues already closed, fixed dates, a required time missed because of a locked order, estimated hours, and the difference between late arrival that satisfies opening hours and unavailable travel estimates.

`swift test --package-path packages/C67Backend` recorded 211 tests including one opt-in skip. The generic iOS Simulator build, `git diff --check`, and two mock UI tests passed on iPhone 18 Pro Simulator (iOS 27.2). The mock UI tests covered next-day review and the v5.2 review and save flow. SwiftFormat still reports the existing findings in 19 files.

## Physical iPhone verification

One XCUITest passed on iPhone 17 (iOS 27.2.1) with a separately signed Debug build and in-memory trip storage. It opened Get Recommendations, picked Museum Sejarah Jakarta, Museum Wayang, and Museum Seni Rupa dan Keramik, then continued through Main spot to Itinerary Review. The test set the planning clock to 16:00 WIB on 26 November 2026 and supplied public venue pins and the published weekly hours. Native MapKit supplied travel estimates on the iPhone.

The review displayed a suggested departure of 09:00 WIB on Friday, 27 November 2026, explained that the original date did not fit, and showed all three visits. The test ended at Review. It used a controlled snapshot for recommendations and opening hours. Live place discovery and live opening-hours lookup were outside this check.

[Museum Sejarah Jakarta hours](https://enjoy.jakarta.go.id/article/museum-sejarah-jakarta) · [Museum Wayang hours](https://enjoy.jakarta.go.id/article/museum-wayang) · [Museum Seni Rupa dan Keramik hours](https://enjoy.jakarta.go.id/article/museum-seni-rupa-dan-keramik)


## Physical iPhone verification with live recommendations and published hours

One XCUITest passed on iPhone 17 (iOS 27.2.1) using the current planner in a separate signed Debug build. Get Recommendations ran museum searches in MapKit near Stasiun Jakarta Kota. The test selected Jakarta History Museum, Museum Bank Indonesia, and Museum Seni Rupa dan Keramik. The planning clock was fixed at 16:00 WIB on 26 November 2026. The test build fetched the venues' public opening-hours pages over HTTPS on the iPhone and obtained all three regular-hours records before the first MapKit ETA request.

The planner made zero ETA requests for 26 November and 24 for 27 November. Itinerary Review showed Friday, 27 November at 09:00 WIB, the reason for moving the date, and all three selected museums. The test ended at Review without saving a trip. The opening-hours lookup used a temporary public-source adapter. The production Pocket hours endpoint requires an authenticated session and was outside this check.

[Museum Sejarah Jakarta](https://enjoy.jakarta.go.id/article/museum-sejarah-jakarta) · [Museum Bank Indonesia](https://www.bi.go.id/en/layanan/kunjungan-bi/default.aspx) · [Museum Seni Rupa dan Keramik](https://enjoy.jakarta.go.id/article/museum-seni-rupa-dan-keramik)
