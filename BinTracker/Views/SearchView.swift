import SwiftUI

/// "Where did I put the…?" Searches item names and notes, plus bin IDs, names and categories.
struct SearchView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var query = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var matchingItems: [Item] {
        guard !trimmed.isEmpty else { return [] }
        return store.items.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.notes.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var matchingBins: [Bin] {
        guard !trimmed.isEmpty else { return [] }
        let key = BinCode.lookupKey(trimmed)
        let prefix = BinCode.normalize(trimmed)
        let categoryIds = Set(store.categories.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }.map(\.id))
        return store.bins.filter {
            let code = BinCode.normalize($0.code)
            return code == key || code.hasPrefix(prefix) || $0.name.localizedCaseInsensitiveContains(trimmed)
                || !categoryIds.isDisjoint(with: $0.categoryIds)
        }
        .sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmed.isEmpty {
                    ContentUnavailableView("Find anything",
                                           systemImage: "magnifyingglass",
                                           description: Text("Search for an item to see which bin it's in and where that bin lives."))
                } else if matchingItems.isEmpty && matchingBins.isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                }

                if !matchingBins.isEmpty {
                    Section("Bins") {
                        ForEach(matchingBins) { bin in
                            NavigationLink(value: BinRef(id: bin.id)) { BinRow(bin: bin) }
                        }
                    }
                }

                if !matchingItems.isEmpty {
                    Section("Items") {
                        ForEach(matchingItems) { item in
                            if let bin = store.bin(item.binId) {
                                NavigationLink(value: BinRef(id: bin.id)) { SearchResultRow(item: item, bin: bin) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Find")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Item, bin ID, name or category")
            .navigationDestination(for: BinRef.self) { BinDetailView(binId: $0.id) }
        }
    }
}

struct SearchResultRow: View {
    @Environment(HouseholdStore.self) private var store
    let item: Item
    let bin: Bin

    var body: some View {
        HStack(spacing: 12) {
            BinBadge(code: bin.code, colorName: bin.colorName)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.name).font(.headline)
                    if item.quantity != 1 { Text("×\(item.quantity)").foregroundStyle(.secondary) }
                }
                Label(store.locationPath(of: bin), systemImage: "mappin.and.ellipse")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
