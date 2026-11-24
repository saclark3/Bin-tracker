import SwiftUI
import SwiftData

/// Areas (rooms) → spots within them → bins at each spot.
struct AreasView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Area.name) private var areas: [Area]
    @Query private var allBins: [Bin]

    @State private var showingNewArea = false
    @State private var newAreaName = ""

    private var unplacedBins: [Bin] { allBins.filter { $0.location == nil } }

    var body: some View {
        NavigationStack {
            List {
                if areas.isEmpty {
                    ContentUnavailableView {
                        Label("No areas yet", systemImage: "house")
                    } description: {
                        Text("Add the parts of your home where you keep bins, like Garage, Attic or Hall closet.")
                    } actions: {
                        Button("Add common areas") { addStarterAreas() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                ForEach(areas) { area in
                    NavigationLink(value: area) {
                        Label {
                            VStack(alignment: .leading) {
                                Text(area.name)
                                Text("\(area.locations.count) spots · \(area.binCount) bins")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: area.symbol) }
                    }
                }
                .onDelete { offsets in offsets.forEach { context.delete(areas[$0]) } }

                if !unplacedBins.isEmpty {
                    Section("Bins with no location") {
                        ForEach(unplacedBins) { bin in
                            NavigationLink(value: bin) { BinRow(bin: bin) }
                        }
                    }
                }
            }
            .navigationTitle("Areas")
            .navigationDestination(for: Area.self) { AreaDetailView(area: $0) }
            .navigationDestination(for: StorageLocation.self) { LocationDetailView(location: $0) }
            .navigationDestination(for: Bin.self) { BinDetailView(bin: $0) }
            .toolbar {
                Button { showingNewArea = true } label: { Label("New area", systemImage: "plus") }
            }
            .alert("New area", isPresented: $showingNewArea) {
                TextField("e.g. Garage", text: $newAreaName)
                Button("Add") {
                    let name = newAreaName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { context.insert(Area(name: name, symbol: AreaSymbol.guess(for: name))) }
                    newAreaName = ""
                }
                Button("Cancel", role: .cancel) { newAreaName = "" }
            }
        }
    }

    /// GUESS: a starter set to save typing on first launch. Easy to rename or delete.
    private func addStarterAreas() {
        for name in ["Garage", "Basement", "Attic", "Hall closet", "Bedroom closet"] {
            context.insert(Area(name: name, symbol: AreaSymbol.guess(for: name)))
        }
    }
}

struct AreaDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var area: Area
    @State private var showingNewLocation = false
    @State private var newLocationName = ""
    @State private var renaming = false
    @State private var renameText = ""

    var body: some View {
        List {
            Section {
                if area.locations.isEmpty {
                    Text("Add spots in \(area.name), like \"Shelf 1\" or \"Under the stairs\".")
                        .foregroundStyle(.secondary)
                }
                ForEach(area.sortedLocations) { loc in
                    NavigationLink(value: loc) {
                        HStack {
                            Text(loc.name)
                            Spacer()
                            Text("\(loc.bins.count) bins").foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let list = area.sortedLocations
                    offsets.forEach { context.delete(list[$0]) }
                }
            } header: {
                Text("Spots")
            } footer: {
                Text("Deleting a spot keeps its bins; they move to \"Bins with no location\".")
            }
        }
        .navigationTitle(area.name)
        .toolbar {
            Menu {
                Button("Add spot", systemImage: "plus") { showingNewLocation = true }
                Button("Rename area", systemImage: "pencil") { renameText = area.name; renaming = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .alert("New spot in \(area.name)", isPresented: $showingNewLocation) {
            TextField("e.g. Shelf 2", text: $newLocationName)
            Button("Add") {
                let name = newLocationName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    let loc = StorageLocation(name: name)
                    context.insert(loc)
                    area.locations.append(loc)
                }
                newLocationName = ""
            }
            Button("Cancel", role: .cancel) { newLocationName = "" }
        }
        .alert("Rename area", isPresented: $renaming) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { area.name = name }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct LocationDetailView: View {
    @Bindable var location: StorageLocation
    @State private var showingNewBin = false

    private var sortedBins: [Bin] {
        location.bins.sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }
    }

    var body: some View {
        List {
            if location.bins.isEmpty {
                Text("No bins here yet.").foregroundStyle(.secondary)
            }
            ForEach(sortedBins) { bin in
                NavigationLink(value: bin) { BinRow(bin: bin) }
            }
        }
        .navigationTitle(location.name)
        .toolbar {
            Button { showingNewBin = true } label: { Label("New bin here", systemImage: "plus") }
        }
        .sheet(isPresented: $showingNewBin) {
            BinEditorView(bin: nil, presetLocation: location)
        }
    }
}

enum AreaSymbol {
    static func guess(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("garage") { return "car" }
        if n.contains("basement") { return "stairs" }
        if n.contains("attic") { return "house.lodge" }
        if n.contains("closet") { return "cabinet" }
        if n.contains("bed") { return "bed.double" }
        if n.contains("kitchen") || n.contains("pantry") { return "refrigerator" }
        if n.contains("office") { return "desktopcomputer" }
        if n.contains("shed") || n.contains("yard") { return "tree" }
        if n.contains("bath") { return "bathtub" }
        return "square.grid.2x2"
    }
}
