#if DEBUG
    import SwiftUI
    import C67Domain

    struct TripProgressDesignPreview: View {
        var arrived = false
        var completed = false
        @State private var notice = false

        private let samplePath = [
            PlanningPoint(latitude: -6.1931, longitude: 106.8379),
            PlanningPoint(latitude: -6.1922, longitude: 106.8377),
            PlanningPoint(latitude: -6.1915, longitude: 106.8383),
            ItineraryPreviewData.points[0],
        ]

        var body: some View {
            NavigationStack {
                TripProgressContent(trip: TripDesignPreviewData.trip(status: completed ? .completed : .active, arrived: arrived),
                                    details: ItineraryPreviewData.details, isDesignPreview: true,
                                    previewDistance: "450 m",
                                    previewStep: ("80 m", "Turn right onto Jalan Cikini Raya"), previewPath: samplePath,
                                    openDirections: { notice = true }, openMaps: { notice = true }, arrive: { notice = true },
                                    completeVisit: { notice = true }, returnToTrip: { notice = true },
                                    returnToStartingPoint: { notice = true })
                    .alert("Design preview", isPresented: $notice) { Button("OK", role: .cancel) {} } message: {
                        Text("Sample map and estimates. No live guidance or trip event is recorded.")
                    }
            }
        }
    }
    #Preview("TRIP STARTED") { TripProgressDesignPreview() }
    #Preview("TRIP DONE · Arrival") { TripProgressDesignPreview(arrived: true) }
    #Preview("Arrival · Dark, large text") {
        TripProgressDesignPreview(arrived: true).preferredColorScheme(.dark).dynamicTypeSize(.accessibility3)
    }
#endif
