import Foundation

public enum PlanningVisitActivity: String, Codable, Sendable {
    case oneExhibition, severalGalleries, briefParkVisit, picnicOrStroll, quickMeal, leisurelyMeal, coffeePickup, seatedCoffee

    public var minutes: Int {
        switch self {
        case .oneExhibition, .seatedCoffee: 45
        case .severalGalleries: 90
        case .briefParkVisit: 20
        case .picnicOrStroll: 60
        case .quickMeal: 35
        case .leisurelyMeal: 75
        case .coffeePickup: 15
        }
    }

    public var title: String {
        switch self {
        case .oneExhibition: "One exhibition"
        case .severalGalleries: "Several galleries"
        case .briefParkVisit: "Brief park visit"
        case .picnicOrStroll: "Picnic or leisurely walk"
        case .quickMeal: "Quick meal"
        case .leisurelyMeal: "Leisurely meal"
        case .coffeePickup: "Pick up coffee"
        case .seatedCoffee: "Sit down for coffee"
        }
    }
}

private enum VisitCategory: String {
    case museum, park, restaurant, cafe

    static let generalEstimate = 45

    var estimate: Int {
        switch self {
        case .museum: 75
        case .park: 35
        case .restaurant: 60
        case .cafe: 30
        }
    }

    var activities: [PlanningVisitActivity] {
        switch self {
        case .museum: [.oneExhibition, .severalGalleries]
        case .park: [.briefParkVisit, .picnicOrStroll]
        case .restaurant: [.quickMeal, .leisurelyMeal]
        case .cafe: [.coffeePickup, .seatedCoffee]
        }
    }

    var rationale: String {
        switch self {
        case .museum: "Estimated for a museum visit."
        case .park: "Estimated for a park visit."
        case .restaurant: "Estimated for a restaurant visit."
        case .cafe: "Estimated for a café visit."
        }
    }
}

public extension PlanningPlace {
    private var visitCategory: VisitCategory? {
        categories.lazy.compactMap { value in
            let key = value.folding(options: .diacriticInsensitive, locale: nil).lowercased().filter(\.isLetter)
            return VisitCategory(rawValue: key.hasPrefix("mkpoicategory") ? String(key.dropFirst("mkpoicategory".count)) : key)
        }.first
    }

    var visitActivities: [PlanningVisitActivity] { visitCategory?.activities ?? [] }

    var categoryVisitMinutes: Int { visitCategory?.estimate ?? VisitCategory.generalEstimate }

    package var localVisitEstimate: (minutes: Int, rationale: String, shorterActivity: PlanningVisitActivity?) {
        let category = visitCategory
        let activity = visitActivity.flatMap { category?.activities.contains($0) == true ? $0 : nil }
        let minutes = activity?.minutes ?? category?.estimate ?? VisitCategory.generalEstimate
        let rationale = activity.map { "\($0.title), chosen by you." } ?? category?.rationale ?? "General visit estimate."
        return (minutes, rationale, category?.activities.first { $0.minutes < minutes })
    }
}
