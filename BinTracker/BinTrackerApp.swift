import SwiftUI
import FirebaseCore

@main
struct BinTrackerApp: App {
    /// False when GoogleService-Info.plist hasn't been added to the project yet.
    private let firebaseReady: Bool

    init() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            firebaseReady = true
        } else {
            firebaseReady = false
        }
        // Start listening for the Apple Watch early: iOS may launch the app in the
        // background just to deliver check-offs made on the watch.
        WatchBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            if firebaseReady {
                RootView()
            } else {
                ContentUnavailableView("Firebase isn't set up yet",
                                       systemImage: "exclamationmark.icloud",
                                       description: Text("Add GoogleService-Info.plist to the BinTracker folder and rebuild. See the README."))
            }
        }
    }
}

struct RootView: View {
    @State private var session = AppSession()

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                ProgressView()
            case .signedOut:
                SignInView()
            case .needsHousehold:
                HouseholdSetupView()
            case .ready(let store):
                ContentView()
                    .environment(store)
                    .id(store.householdId)
            }
        }
        .environment(session)
    }
}

struct ContentView: View {
    @Environment(HouseholdStore.self) private var store

    var body: some View {
        TabView {
            BinsView()
                .tabItem { Label("Bins", systemImage: "shippingbox") }
            PickListsView()
                .tabItem { Label("Pick lists", systemImage: "checklist") }
            SearchView()
                .tabItem { Label("Find", systemImage: "magnifyingglass") }
            AreasView()
                .tabItem { Label("Areas", systemImage: "house") }
            CategoriesView()
                .tabItem { Label("Categories", systemImage: "tag") }
            // Household is opened from the Bins tab's toolbar, so iPhone keeps five tabs and no "More" tab.
        }
        .alert("Couldn't save", isPresented: Binding(get: { store.lastError != nil },
                                                     set: { if !$0 { store.clearError() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}
