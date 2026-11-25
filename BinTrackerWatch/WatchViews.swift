import SwiftUI

@main
struct BinsWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView().environment(store)
        }
    }
}

enum WatchRoute: Hashable {
    case pickList(String)
    case bin(String)
    case find
}

// MARK: - Home
struct WatchRootView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                if store.snapshot.isSignedOut {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "iphone").font(.title2)
                        Text("Open Bins on your iPhone and sign in. Your bins and pick lists will appear here.")
                            .font(.footnote)
                    }
                } else {
                    Section("Pick lists") {
                        if store.snapshot.pickLists.isEmpty {
                            Text("Make a pick list in the iPhone app.").font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(store.snapshot.pickLists) { list in
                            NavigationLink(value: WatchRoute.pickList(list.id)) { WatchPickListRow(list: list) }
                        }
                    }
                    Section("Bins") {
                        NavigationLink(value: WatchRoute.find) {
                            Label("Find a bin", systemImage: "magnifyingglass")
                        }
                        ForEach(store.recentBins.prefix(5)) { bin in
                            NavigationLink(value: WatchRoute.bin(bin.id)) { WatchBinRow(bin: bin) }
                        }
                    }
                }
                Section { WatchSyncStatus() }
            }
            .navigationTitle("Bins")
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case .pickList(let id): WatchPickListView(listId: id)
                case .bin(let id): WatchBinView(binId: id)
                case .find: WatchFindView()
                }
            }
        }
    }
}

struct WatchSyncStatus: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if store.snapshot.generatedAt > .distantPast {
                Text("Updated \(store.snapshot.generatedAt, format: .relative(presentation: .named))")
            }
            if !store.pending.isEmpty {
                Label(store.phoneReachable ? "Syncing \(store.pending.count)…"
                                           : "\(store.pending.count) change\(store.pending.count == 1 ? "" : "s") will sync when your iPhone is nearby",
                      systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

struct WatchBadge: View {
    let code: String
    let colorName: String

    var body: some View {
        Text(code)
            .font(.system(.body, design: .rounded).weight(.heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(minWidth: 40)
            .background(watchColor(colorName), in: RoundedRectangle(cornerRadius: 6))
    }
}

func watchColor(_ name: String) -> Color {
    switch name {
    case "green": .green
    case "orange": .orange
    case "red": .red
    case "purple": .purple
    case "yellow": .yellow
    case "gray": .gray
    default: .blue
    }
}

struct WatchBinRow: View {
    let bin: WatchBin
    var body: some View {
        HStack {
            WatchBadge(code: bin.code, colorName: bin.colorName)
            VStack(alignment: .leading) {
                Text(bin.displayName).lineLimit(1)
                Text(bin.location).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

// MARK: - Pick lists
struct WatchPickListRow: View {
    let list: WatchPickList
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(list.name).font(.headline).lineLimit(2)
            HStack(spacing: 4) {
                if list.isComplete { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                Text(list.isComplete ? "All done" : "\(list.done) of \(list.total)")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct WatchPickListView: View {
    @Environment(WatchStore.self) private var store
    let listId: String

    var body: some View {
        if let list = store.snapshot.pickList(listId) {
            List {
                Section {
                    ProgressView(value: Double(list.done), total: Double(max(list.total, 1)))
                        .tint(list.isComplete ? .green : .accentColor)
                    Text(list.isComplete ? "All done" : "\(list.done) of \(list.total) checked off")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(list.entries) { entry in
                    Section(entry.location) {
                        Button { store.toggle(entry, in: list) } label: {
                            HStack {
                                WatchCheck(checked: entry.picked)
                                WatchBadge(code: entry.code, colorName: entry.colorName)
                                    .opacity(entry.picked ? 0.5 : 1)
                                Text(entry.displayName).lineLimit(2).strikethrough(entry.picked)
                            }
                        }
                        ForEach(entry.items) { item in
                            Button { store.toggle(item, of: entry, in: list) } label: {
                                HStack {
                                    WatchCheck(checked: item.picked)
                                    Text(item.quantity == 1 ? item.name : "\(item.name) ×\(item.quantity)")
                                        .strikethrough(item.picked)
                                }
                                .padding(.leading, 8)
                            }
                        }
                    }
                }
                if list.entries.isEmpty {
                    Text("This list is empty.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(list.name)
        } else {
            Text("This pick list was deleted.").foregroundStyle(.secondary)
        }
    }
}

struct WatchCheck: View {
    let checked: Bool
    var body: some View {
        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(checked ? Color.green : Color.secondary)
    }
}

// MARK: - Bins and quick add
struct WatchFindView: View {
    @Environment(WatchStore.self) private var store
    @State private var query = ""

    var body: some View {
        List {
            TextField("Bin ID, name or item", text: $query)
            ForEach(store.search(query)) { bin in
                NavigationLink(value: WatchRoute.bin(bin.id)) { WatchBinRow(bin: bin) }
            }
            if !query.isEmpty && store.search(query).isEmpty {
                Text("No matches").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Find")
    }
}

struct WatchBinView: View {
    @Environment(WatchStore.self) private var store
    let binId: String
    @State private var newItem = ""

    var body: some View {
        if let bin = store.snapshot.bin(binId) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        WatchBadge(code: bin.code, colorName: bin.colorName)
                        if !bin.name.isEmpty { Text(bin.name).font(.headline) }
                        Label(bin.location, systemImage: "mappin.and.ellipse")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Contents (\(bin.items.count))") {
                    TextField("Add an item", text: $newItem)
                        .onSubmit {
                            store.addItem(named: newItem, to: bin)
                            newItem = ""
                        }
                    ForEach(bin.items) { item in
                        Text(item.quantity == 1 ? item.name : "\(item.name) ×\(item.quantity)")
                    }
                }
            }
            .navigationTitle(bin.code)
        } else {
            Text("This bin was deleted.").foregroundStyle(.secondary)
        }
    }
}
