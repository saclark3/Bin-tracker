import SwiftUI

/// Areas (rooms) → spots within them → bins at each spot.
struct AreasView: View {
    @Environment(HouseholdStore.self) private var store

    @State private var showingNewArea = false
    @State private var newAreaName = ""

    var body: some View {
        NavigationStack {
            List {
                if store.areas.isEmpty {
                    ContentUnavailableView {
                        Label("No areas yet", systemImage: "house")
                    } description: {
                        Text("Add the parts of your home where you keep bins, like Garage, Attic or Hall closet.")
                    } actions: {
                        Button("Add common areas") { addStarterAreas() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                ForEach(store.areas) { area in
                    NavigationLink(value: area) {
                        Label {
                            VStack(alignment: .leading) {
                                Text(area.name)
                                Text("\(store.spots(in: area).count) spots · \(store.binCount(in: area)) bins")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: area.symbol) }
                    }
                }
                .onDelete { offsets in
                    let list = store.areas
                    offsets.forEach { store.deleteArea(list[$0]) }
                }

                let unplaced = store.unplacedBins
                if !unplaced.isEmpty {
                    Section("Bins with no location") {
                        ForEach(unplaced) { bin in
                            NavigationLink(value: BinRef(id: bin.id)) { BinRow(bin: bin) }
                        }
                    }
                }
            }
            .navigationTitle("Areas")
            .navigationDestination(for: Area.self) { AreaDetailView(areaId: $0.id) }
            .navigationDestination(for: Spot.self) { SpotDetailView(spotId: $0.id) }
            .navigationDestination(for: BinRef.self) { BinDetailView(binId: $0.id) }
            .toolbar {
                Button { showingNewArea = true } label: { Label("New area", systemImage: "plus") }
            }
            .alert("New area", isPresented: $showingNewArea) {
                TextField("e.g. Garage", text: $newAreaName)
                Button("Add") {
                    let name = newAreaName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { store.addArea(name) }
                    newAreaName = ""
                }
                Button("Cancel", role: .cancel) { newAreaName = "" }
            }
        }
    }

    /// GUESS: a starter set to save typing on first launch. Easy to rename or delete.
    private func addStarterAreas() {
        for name in ["Garage", "Basement", "Attic", "Hall closet", "Bedroom closet"] {
            store.addArea(name)
        }
    }
}

struct AreaDetailView: View {
    @Environment(HouseholdStore.self) private var store
    let areaId: String

    @State private var showingNewSpot = false
    @State private var newSpotName = ""
    @State private var renaming = false
    @State private var renameText = ""

    var body: some View {
        if let area = store.area(areaId) {
            content(area)
        } else {
            ContentUnavailableView("Area not found", systemImage: "house")
        }
    }

    private func content(_ area: Area) -> some View {
        let spots = store.spots(in: area)
        return List {
            Section {
                if spots.isEmpty {
                    Text("Add spots in \(area.name), like \"Shelf 1\" or \"Under the stairs\".")
                        .foregroundStyle(.secondary)
                }
                ForEach(spots) { spot in
                    NavigationLink(value: spot) {
                        HStack {
                            Text(spot.name)
                            Spacer()
                            Text("\(store.bins(at: spot).count) bins").foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in offsets.forEach { store.deleteSpot(spots[$0]) } }
            } header: {
                Text("Spots")
            } footer: {
                Text("Deleting a spot keeps its bins; they move to \"Bins with no location\".")
            }
        }
        .navigationTitle(area.name)
        .toolbar {
            Menu {
                Button("Add spot", systemImage: "plus") { showingNewSpot = true }
                Button("Rename area", systemImage: "pencil") { renameText = area.name; renaming = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .alert("New spot in \(area.name)", isPresented: $showingNewSpot) {
            TextField("e.g. Shelf 2", text: $newSpotName)
            Button("Add") {
                let name = newSpotName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.addSpot(name, in: area) }
                newSpotName = ""
            }
            Button("Cancel", role: .cancel) { newSpotName = "" }
        }
        .alert("Rename area", isPresented: $renaming) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.renameArea(area, to: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct SpotDetailView: View {
    @Environment(HouseholdStore.self) private var store
    let spotId: String
    @State private var showingNewBin = false

    var body: some View {
        if let spot = store.spot(spotId) {
            let bins = store.bins(at: spot)
            List {
                if bins.isEmpty {
                    Text("No bins here yet.").foregroundStyle(.secondary)
                }
                ForEach(bins) { bin in
                    NavigationLink(value: BinRef(id: bin.id)) { BinRow(bin: bin) }
                }
            }
            .navigationTitle(spot.name)
            .toolbar {
                Button { showingNewBin = true } label: { Label("New bin here", systemImage: "plus") }
            }
            .sheet(isPresented: $showingNewBin) {
                BinEditorView(bin: nil, presetSpotId: spot.id)
            }
        } else {
            ContentUnavailableView("Spot not found", systemImage: "mappin.slash")
        }
    }
}
