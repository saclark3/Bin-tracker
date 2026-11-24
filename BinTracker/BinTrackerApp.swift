import SwiftUI
import SwiftData

@main
struct BinTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // All data stays on the device in a local SwiftData store.
        .modelContainer(for: [Area.self, StorageLocation.self, Bin.self, Item.self, AccessEvent.self])
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            BinsView()
                .tabItem { Label("Bins", systemImage: "shippingbox") }
            SearchView()
                .tabItem { Label("Find", systemImage: "magnifyingglass") }
            AreasView()
                .tabItem { Label("Areas", systemImage: "house") }
        }
    }
}
