import SwiftUI
import SwiftData

/// "Where did I put the…?" Searches item names and notes, plus bin IDs and names.
struct SearchView: View {
    @Query(sort: \Item.name) private var items: [Item]
    @Query(sort: \Bin.code) private var bins: [Bin]
    @State private var query = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var matchingItems: [Item] {
        guard !trimmed.isEmpty else { return [] }
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.notes.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var matchingBins: [Bin] {
        guard !trimmed.isEmpty else { return [] }
        let key = BinCode.lookupKey(trimmed)
        return bins.filter {
            BinCode.normalize($0.code) == key
                || BinCode.normalize($0.code).hasPrefix(BinCode.normalize(trimmed))
                || $0.name.localizedCaseInsensitiveContains(trimmed)
        }
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
                            NavigationLink(value: bin) { BinRow(bin: bin) }
                        }
                    }
                }

                if !matchingItems.isEmpty {
                    Section("Items") {
                        ForEach(matchingItems) { item in
                            if let bin = item.bin {
                                NavigationLink(value: bin) { SearchResultRow(item: item, bin: bin) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Find")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Item, bin ID or bin name")
            .navigationDestination(for: Bin.self) { BinDetailView(bin: $0) }
        }
    }
}

struct SearchResultRow: View {
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
                Label(bin.locationPath, systemImage: "mappin.and.ellipse")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
