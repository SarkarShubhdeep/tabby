import SwiftUI

@main
struct TabbyApp: App {
    @State private var session = BillSession()
    @State private var router = Router()
    @State private var peopleStore = PeopleStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(router)
                .environment(peopleStore)
        }
    }
}

struct RootView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .review: ReviewItemsView()
                    case .people: PeopleView()
                    case .assign: AssignView()
                    case .summary: SummaryView()
                    }
                }
        }
    }
}
