# Weather preparation for itineraries

Status: Ready for review

Branch: `hi/v52-eta-recovery`

## Outcome

Travellers see practical weather preparations in Before you go on the itinerary review and on planned trips. Metric-based tips name the forecast value and when it applies.

## Scope

- Use the departure forecast for the origin and reuse available forecast readings for scheduled outdoor visits. Use direct radiation for a visit when its schedule has direct-sun exposure evidence.
- Use WeatherKit for departure conditions, apparent temperature, UV and precipitation. Use Open-Meteo for supplemental direct radiation and as the departure fallback. The Open-Meteo adapter uses the departure hour's starting timestamp for apparent temperature and the ending timestamp for the three preceding-hour values.
- Show up to one row per weather concern. Prepare rain gear from 40% precipitation, prepare water and cooling breaks from 32 °C apparent temperature, prepare sun protection from UV 3, and plan shade breaks from 500 W/m² direct radiation. Storm conditions keep their dedicated advice. The UV threshold follows the WHO guidance. The other cutoffs are app preparation rules.
- Keep daylight, scheduling and route scoring behavior independent of the preparation display. Persist the peak precipitation reading for each outdoor visit from available overlapping samples. Earlier proposals keep their existing readings when decoded.

[Previous preparation card](itinerary-preparation.md) · [Open-Meteo data definitions](https://open-meteo.com/en/docs) · [WHO UV index guidance](https://www.who.int/news-room/questions-and-answers/item/radiation-the-ultraviolet-%28uv%29-index/)

## Acceptance criteria

- Four simultaneous forecast signals can show four actions in the review, with values and time or stop context. The opening-hours reminder still appears.
- A missing or invalid reading produces no advice for that reading. A selected outdoor visit carries the precipitation peak for its scheduled window and source.
- Attribution remains visible for providers used by weather tips, and existing saved proposal readings keep their meaning.

## Verification plan

Run C67Backend tests, the departure weather parsing tests, and the staging-mode Before you go scenario on the iPhone Simulator. Check the live Open-Meteo response schema at public Blok M coordinates separately from the synthetic app tests.

## Result

- C67Backend passed with 198 scenarios recorded, including one opt-in skip. The integration fixture also confirmed that the selected visit's precipitation evidence excludes a higher value before the visit and survives proposal encoding.
- The staging-mode review on iPhone 18 Pro Simulator / iOS 27.2 showed all four weather tips and the opening-hours reminder. Both app forecast decoding tests passed. The wider Simulator run passed 65 of 67 tests and reproduced two earlier selection-limit failures documented in the [v5.2 ETA recovery task](planner-v52-eta-recovery.md).
- A live Open-Meteo response for public Blok M coordinates contained the four documented fields and expected units. Live WeatherKit and physical iPhone app behavior were outside this run.
- `git diff --check` passed. SwiftFormat reported the existing findings in 20 files, all outside the lines added for this task.

## Physical iPhone live forecast follow-up

The signed Travelants Debug update was installed on iPhone 17 / iOS 27.2.1 under the existing development bundle `io.hendrairawan.c67.recoveryui`. Two XCUITest runs started at Home, continued through Add Specific Place and Main spot, and reached Itinerary Review with every expected stop. The temporary harness populated the public pins and controlled constraints from the earlier MapKit tests. Both runs used live MapKit and live departure weather. The weather was attributed to Open-Meteo. The development signature did not carry the WeatherKit entitlement.

| Route for 26 November 2026 | Suggested departure (WIB) | Before you go |
| --- | --- | --- |
| Blok M MRT → Museum Polri | 08:49 | Pack rain gear (49% precipitation), Bring water (feels like 32 °C), Pack sun protection (UV 4.2), Check opening hours |
| Six stops with return to Blok M MRT | 08:51 | The same four tips |

Both departures were in the same forecast hour at the same origin. Neither fixture specified stop exposure, so the weather advice shown referred to departure. Device diagnostics showed WeatherKit authentication failing and Open-Meteo returning 32.3 °C apparent temperature, UV 4.25, 10 W/m² direct radiation, and 49% precipitation in both cases. Direct radiation was below the 500 W/m² cutoff for the shade tip. Both tests stopped at Review before saving. An ordinary launch then reopened Home with the existing trip still present.

The two physical tests passed in `/tmp/travelants-device-ui.uF82Zv/physical-weather-review-fresh.xcresult`.

A subsequent build using the `C67 Staging` scheme and its Debug Run configuration installed and launched on the same iPhone under the same development bundle. The app bundle embedded `C67_APP_MODE=staging` so launch from Home uses staging mode. The local development profile omitted WeatherKit and Sign in with Apple entitlements. This check verified installation and process launch.

The staging itinerary now hides the standalone Schedule decision disclosure below the map. On iPhone 18 Pro Simulator, the staging-mode v5.2 UI test verified all four synthetic weather tips and reached the map without the disclosure. The updated `C67 Staging` build installed and launched on the physical iPhone 17.

The Main spot screen also hides the automatic Trip options button in staging. The staging-mode iPhone 18 Pro Simulator test verified that Next reached Review and that Before you go remained visible. The `C67 Staging` update installed on the iPhone 17. The device lock blocked the remote launch.
