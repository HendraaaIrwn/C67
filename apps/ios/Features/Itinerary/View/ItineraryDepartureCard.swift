import SwiftUI
import C67Domain

struct ItineraryDepartureCard: View {
    let proposal: PlanProposal
    let departureForecast: DepartureWeatherLoader
    let includesPreparationWeather: Bool
    var weatherAdvice: String?
    var isDesignPreview = false
    var editDeparture: (() -> Void)?
    var editEndpoints: ((ItineraryEditRoute) -> Void)?
    @Environment(\.locale) private var locale
    @State private var weatherRetry = 0
    /// The provider mark scales with Dynamic Type alongside the footnote-sized link arrow.
    @ScaledMetric(relativeTo: .footnote) private var attributionHeight = 14.0

    private var departureContext: String {
        if isDesignPreview { return "Set to beat the morning rush." }
        if proposal.firstItinerary == true { return proposal.explanation }
        if proposal.input.enginePreferences?.flexibleDeparture == true { return "Chosen within your available departure window." }
        return "Based on your selected departure time."
    }

    var body: some View {
        departureCard
            .task(id: forecastIdentity) {
                guard !isDesignPreview, let departure = proposal.estimatedExperienceDeparture else { departureForecast.clear(); return }
                #if DEBUG
                    if proposal.synthetic, ProcessInfo.processInfo.arguments.contains("--before-you-go-weather-fixture") {
                        departureForecast.usePreparationWeatherFixture(origin: proposal.input.origin, departure: departure)
                        return
                    }
                #endif
                guard !proposal.synthetic else { departureForecast.clear(); return }
                await departureForecast.load(origin: proposal.input.origin, departure: departure, includesPreparationWeather: includesPreparationWeather)
            }
    }

    private var forecast: DepartureWeatherLoader.Forecast? {
        departureForecast.forecast(for: proposal.input.origin, departure: proposal.estimatedExperienceDeparture)
    }

    private var departureCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let departure = proposal.estimatedExperienceDeparture {
                // HIG text styles, smallest to largest: footnote label, subheadline date, large-title time, body weather.
                HStack(alignment: .center) {
                    Text("SUGGESTED DEPARTURE")
                        .font(.footnote.italic())
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if editDeparture != nil || editEndpoints != nil { editMenu }
                }
                Text(ItineraryFormatting.date(departure, zone: proposal.input.timeZone, locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                Text(Self.clockTime(departure, zone: proposal.input.timeZone))
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let originalDate = proposal.rescheduledFromDate {
                    let date = ItineraryFormatting.date(originalDate, zone: proposal.input.timeZone, locale: locale)
                    Text("The trip didn’t fit on \(date). Travelants found a schedule for this date instead.")
                        .font(.footnote)
                        .padding(.top, 4)
                }
                departureWeather
                weatherAttribution
            } else {
                ViewThatFits(in: .horizontal) {
                    Label("SUGGESTED DEPARTURE", systemImage: "clock")
                        .fixedSize()
                    Text("Suggested departure")
                }
                .font(.subheadline)
                Text(ItineraryFormatting.date(proposal.departureAt ?? proposal.input.startsAt, zone: proposal.input.timeZone, locale: locale))
                    .font(.largeTitle.bold())
                Text(ItineraryFormatting.time(proposal.departureAt ?? proposal.input.startsAt, zone: proposal.input.timeZone, locale: locale))
                    .font(.title.bold())
                Text(departureContext).font(.subheadline)
                if let weatherAdvice {
                    Label(weatherAdvice, systemImage: "sun.max")
                        .font(.subheadline)
                        .padding(.top, 8)
                } else if proposal.input.enginePreferences?.automaticFirstPlan == true {
                    Label("Estimated finish \(ItineraryFormatting.time(proposal.finishesAt, zone: proposal.input.timeZone, locale: locale))",
                          systemImage: "flag.checkered")
                        .font(.subheadline)
                        .padding(.top, 8)
                } else {
                    Label("Finish by \(ItineraryFormatting.time(proposal.input.finishBy, zone: proposal.input.timeZone, locale: locale))",
                          systemImage: "flag.checkered")
                        .font(.subheadline)
                        .padding(.top, 8)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            // Brand blue at the top fading to a brighter sky blue, as in the Sketch card.
            LinearGradient(colors: [Color(red: 0.204, green: 0.443, blue: 0.937), Color(red: 0.137, green: 0.596, blue: 0.949)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("itineraryDeparture")
    }

    private var forecastIdentity: String {
        "\(proposal.input.origin.latitude),\(proposal.input.origin.longitude),\(proposal.estimatedExperienceDeparture?.timeIntervalSince1970 ?? 0),\(proposal.synthetic),\(isDesignPreview),\(includesPreparationWeather),\(weatherRetry)"
    }

    @ViewBuilder private var departureWeather: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isDesignPreview, let weatherAdvice {
                Label(weatherAdvice, systemImage: "sun.max")
            } else if let forecast {
                // "32°": degrees in the user's preferred unit, without the unit letter, as in the Sketch card.
                let degrees = forecast.temperature.converted(to: UnitTemperature(forLocale: locale)).value
                Label("\(Int(degrees.rounded()))° · \(forecast.condition)", systemImage: forecast.symbol)
            } else if departureForecast.isLoading {
                Text("Checking departure weather…")
            } else {
                Text("Weather unavailable for this time")
                if !proposal.synthetic, !isDesignPreview, departureForecast.failure == .temporarilyUnavailable {
                    Button("Try weather again") { weatherRetry += 1 }
                }
            }
        }
        .font(.body)
        .symbolRenderingMode(.monochrome)
        .padding(.top, 12)
        .accessibilityIdentifier("itineraryDepartureWeather")
    }

    /// "08:00 AM": the card shows the departure on a 12-hour clock.
    static func clockTime(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone) ?? .current
        formatter.dateFormat = "hh:mm a"
        return formatter.string(from: date)
    }

    private var editMenu: some View {
        Menu {
            if let editDeparture { Button("Departure date and time", action: editDeparture) }
            if let editEndpoints {
                Button("Starting point") { editEndpoints(.startingPoint) }
                Button("End point") { editEndpoints(.endPoint) }
            }
        } label: {
            Text("Edit")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .modifier(EditGlassBackground())
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityIdentifier("itineraryDepartureEdit")
    }

    /// The weather provider's mark, white on the card, linking to its legal and data-source page.
    @ViewBuilder private var weatherAttribution: some View {
        if let forecast, !proposal.synthetic, !isDesignPreview {
            let source = (name: forecast.source, url: forecast.sourceURL, mark: forecast.markOnDarkURL)
            HStack {
                Spacer()
                Link(destination: source.url) {
                    HStack(spacing: 10) {
                        if let mark = source.mark {
                            AsyncImage(url: mark) { image in
                                image.resizable().scaledToFit()
                            } placeholder: { Text(source.name) }
                                .frame(height: attributionHeight)
                        } else {
                            Text(source.name).font(.subheadline.weight(.semibold))
                        }
                        Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("\(source.name) data sources")
            }
            .padding(.top, 4)
            .padding(.bottom, -10)
        }
    }
}

struct ItineraryPreparationCard: View {
    private typealias Kind = PlanningScheduleDecision.Reading.Kind

    private struct Reading {
        let value: Double
        let stop: String?
        let source: String?

        var when: String {
            if let stop { return String(localized: "during your visit to \(stop)") }
            return String(localized: "around departure")
        }
    }

    private struct WeatherTip: Identifiable {
        let id: Kind
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        let symbol: String
        let source: String?
    }

    let forecast: DepartureWeatherLoader.Forecast?
    let outdoor: [PlanningScheduleDecision.Outdoor]
    let stops: [ScheduledPlanningStop]
    let evidence: [PlanningEvidence]
    let hoursConflicts: [String]
    let hasDefaultTravelTime: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        let weather = weatherTips
        VStack(alignment: .leading, spacing: 14) {
            Text("Before you go")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("itineraryPreparationTitle")
            VStack(spacing: 12) {
                ForEach(weather) { row in
                    tip(row.title, detail: row.detail, symbol: row.symbol)
                    separator
                }
                if hoursConflicts.count > 1 {
                    tip("Check opening hours", detail: "\(hoursConflicts.count) visits may fall outside regular hours. Confirm directly with the venues.", symbol: "clock")
                } else if let hoursConflict = hoursConflicts.first {
                    tip("Check opening hours", detail: "Your visit to \(hoursConflict) may fall outside its regular hours. Confirm with the venue.", symbol: "clock")
                } else {
                    tip("Check opening hours", detail: "Confirm hours for your visit date, especially on holidays.", symbol: "clock")
                }
                if hasDefaultTravelTime {
                    separator
                    tip("Allow extra travel time", detail: "Some legs use a default estimate. Check your route before leaving.", symbol: "map")
                }
            }
            ForEach(Array(Set(weather.compactMap(\.source))).sorted(), id: \.self) { source in
                attribution(for: source)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("itineraryPreparation")
    }

    private var weatherTips: [WeatherTip] {
        var tips: [WeatherTip] = []
        if forecast?.precipitation == .storm {
            tips.append(.init(id: .precipitationChance, title: "Check the storm forecast",
                              detail: "Storms are forecast around departure. Check local weather alerts before leaving.",
                              symbol: "cloud.bolt.rain", source: forecast?.source))
        } else if let rain = strongest(.precipitationChance), rain.value >= 40 {
            let percent = (rain.value / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
            tips.append(.init(id: .precipitationChance, title: "Pack rain gear",
                              detail: "Up to a \(percent) chance of precipitation \(rain.when). Bring a rain jacket or umbrella.",
                              symbol: "umbrella", source: rain.source))
        } else if forecast?.precipitation == .rain {
            tips.append(.init(id: .precipitationChance, title: "Pack an umbrella", detail: "Rain is forecast around departure.",
                              symbol: "umbrella", source: forecast?.source))
        }
        if let heat = strongest(.apparentTemperature), heat.value >= 32 {
            let temperature = Measurement(value: heat.value, unit: UnitTemperature.celsius)
                .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
            tips.append(.init(id: .apparentTemperature, title: "Bring water",
                              detail: "Feels like \(temperature) \(heat.when). Plan water and cooling breaks.", symbol: "drop", source: heat.source))
        }
        if let uv = strongest(.uvIndex), uv.value >= 3 {
            let index = uv.value.formatted(.number.precision(.fractionLength(0 ... 1)).locale(locale))
            let protection: LocalizedStringKey = uv.value >= 8
                ? "Limit time in direct sun and use sunscreen, a hat and sunglasses."
                : "Bring sunscreen, a hat and sunglasses."
            tips.append(.init(id: .uvIndex, title: "Pack sun protection", detail: "UV index \(index) \(uv.when). \(Text(protection))",
                              symbol: "sunglasses", source: uv.source))
        }
        if let sun = strongest(.directRadiation), sun.value >= 500 {
            let amount = sun.value.formatted(.number.precision(.fractionLength(0)).locale(locale))
            tips.append(.init(id: .directRadiation, title: "Plan shade breaks",
                              detail: "Direct sunlight averages \(amount) W/m² \(sun.when). Look for shaded places to rest.",
                              symbol: "sun.max", source: sun.source))
        }
        return tips
    }

    private func strongest(_ kind: Kind) -> Reading? {
        let departureValue: Double? = switch kind {
        case .precipitationChance: forecast?.precipitationChance.map { $0 * 100 }
        case .apparentTemperature: forecast?.feelsLikeCelsius
        case .uvIndex: forecast?.uvIndex
        case .directRadiation: forecast?.directRadiation
        }
        let source = kind == .directRadiation && forecast?.source == DepartureWeatherLoader.appleWeatherName
            ? DepartureWeatherLoader.openMeteoName : forecast?.source
        var result = departureValue.map { Reading(value: $0, stop: nil, source: source) }
        let now = Date.now
        for visit in outdoor where visit.interval.end > now {
            guard let stop = stops.first(where: { $0.id == visit.id }),
                  let reading = visit.readings.first(where: { $0.kind == kind }),
                  let value = reading.value, value.isFinite, value > (result?.value ?? -.infinity) else { continue }
            result = Reading(value: value, stop: stop.name, source: reading.source)
        }
        return result
    }

    @ViewBuilder private func attribution(for source: String) -> some View {
        if forecast?.source != source {
            if let data = evidence.first(where: { $0.kind == "weather" && !$0.synthetic && $0.label == source }), let url = data.url {
                Link(destination: url) {
                    if let mark = data.attributionLogoURL, mark.host == "weatherkit.apple.com" {
                        AsyncImage(url: mark) { image in
                            image.resizable().scaledToFit()
                        } placeholder: { Text(source) }
                            .frame(height: 14)
                            .accessibilityLabel(source)
                    } else {
                        Text(source)
                    }
                }
                .font(.footnote)
            } else if source == DepartureWeatherLoader.openMeteoName {
                Link(source, destination: DepartureWeatherLoader.openMeteoURL)
                    .font(.footnote)
            }
        }
    }

    private var separator: some View {
        Divider().accessibilityHidden(true)
    }

    private func tip(_ title: LocalizedStringKey, detail: LocalizedStringKey, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(minWidth: 22)
                .foregroundStyle(AppColor.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Liquid Glass capsule on iOS 26 and later; a translucent white capsule before.
private struct EditGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.tint(Color(red: 0.16, green: 0.38, blue: 0.86).opacity(0.55)).interactive(), in: .capsule)
            } else {
                fallback(content)
            }
        #else
            fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.white.opacity(0.24), in: .capsule)
            .overlay { Capsule().strokeBorder(.white.opacity(0.35)) }
    }
}
