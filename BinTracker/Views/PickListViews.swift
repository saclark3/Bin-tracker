import SwiftUI

// MARK: - Pick lists tab
/// Named lists of bins (and items) to fetch. Check them off as you grab them, here or on the Apple Watch.
struct PickListsView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var path: [PickListRef] = []
    @State private var showingNew = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if store.pickLists.isEmpty {
                    ContentUnavailableView {
                        Label("No pick lists yet", systemImage: "checklist")
                    } description: {
                        Text("Choose the bins (or just some items in them) you need to fetch, then check them off as you grab them. Pick lists also show on your Apple Watch.")
                    } actions: {
                        Button("New pick list") { showingNew = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.bins.isEmpty)
                    }
                }
                ForEach(store.pickLists) { list in
                    NavigationLink(value: PickListRef(id: list.id)) { PickListRow(list: list) }
                }
                .onDelete { offsets in
                    let lists = store.pickLists
                    offsets.forEach { store.deletePickList(lists[$0]) }
                }
            }
            .navigationTitle("Pick lists")
            .navigationDestination(for: PickListRef.self) { PickListDetailView(listId: $0.id) }
            .navigationDestination(for: BinRef.self) { BinDetailView(binId: $0.id) }
            .toolbar {
                Button { showingNew = true } label: { Label("New pick list", systemImage: "plus") }
                    .disabled(store.bins.isEmpty)
            }
            .sheet(isPresented: $showingNew) {
                PickListEditorView(list: nil) { newId in path.append(PickListRef(id: newId)) }
            }
        }
    }
}

struct PickListRow: View {
    @Environment(HouseholdStore.self) private var store
    let list: PickList

    var body: some View {
        let p = store.progress(of: list)
        HStack(spacing: 12) {
            ProgressRing(done: p.done, total: p.total)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name).font(.headline)
                let bins = store.bins(in: list)
                Text(bins.map(\.code).joined(separator: ", "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(p.total > 0 && p.done == p.total ? "All done" : "\(p.done) of \(p.total) checked off")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ProgressRing: View {
    let done: Int
    let total: Int

    var body: some View {
        let fraction = total == 0 ? 0 : Double(done) / Double(total)
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 4)
            Circle().trim(from: 0, to: fraction)
                .stroke(fraction >= 1 ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if fraction >= 1 {
                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.green)
            }
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - One pick list
struct PickListDetailView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let listId: String

    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var openBin: BinRef?

    var body: some View {
        if let list = store.pickList(listId) {
            content(list)
        } else {
            ContentUnavailableView("Pick list not found", systemImage: "checklist",
                                   description: Text("It may have been deleted on another device."))
        }
    }

    /// Bins grouped by area, so the list reads in the order you'd walk the house.
    private struct AreaGroup: Identifiable {
        let area: String
        var bins: [Bin]
        var id: String { area }
    }

    private func groups(_ list: PickList) -> [AreaGroup] {
        var result: [AreaGroup] = []
        for bin in store.bins(in: list) {
            let area = store.spot(bin.spotId).flatMap { store.area($0.areaId)?.name } ?? "No location"
            if let i = result.firstIndex(where: { $0.area == area }) { result[i].bins.append(bin) }
            else { result.append(AreaGroup(area: area, bins: [bin])) }
        }
        return result
    }

    private func content(_ list: PickList) -> some View {
        let p = store.progress(of: list)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                        .tint(p.total > 0 && p.done == p.total ? .green : .accentColor)
                    Text(p.total > 0 && p.done == p.total ? "All done" : "\(p.done) of \(p.total) checked off")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Tap a bin when you grab it, or an item when you pull it out. Checking off also counts as opening the bin.")
            }

            ForEach(groups(list)) { group in
                Section(group.area) {
                    ForEach(group.bins) { bin in
                        PickBinRow(list: list, bin: bin) { openBin = BinRef(id: $0.id) }
                        ForEach(store.chosenItems(in: list, bin: bin)) { item in
                            PickItemRow(list: list, item: item)
                        }
                    }
                }
            }
            if list.binIds.isEmpty && list.itemIds.isEmpty {
                Text("Nothing on this list yet. Tap Edit to add bins.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button { showingEdit = true } label: { Label("Edit list", systemImage: "pencil") }
                Button { store.resetPickList(list) } label: { Label("Uncheck everything", systemImage: "arrow.counterclockwise") }
                    .disabled(p.done == 0)
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete list", systemImage: "trash") }
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
        }
        .navigationDestination(item: $openBin) { BinDetailView(binId: $0.id) }
        .sheet(isPresented: $showingEdit) { PickListEditorView(list: list) }
        .confirmationDialog("Delete \(list.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete list", role: .destructive) {
                store.deletePickList(list)
                dismiss()
            }
        } message: {
            Text("The bins and items aren't affected.")
        }
    }
}

struct CheckMark: View {
    let checked: Bool
    var body: some View {
        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(checked ? Color.green : Color.secondary)
            .contentTransition(.symbolEffect(.replace))
    }
}

struct PickBinRow: View {
    @Environment(HouseholdStore.self) private var store
    let list: PickList
    let bin: Bin
    let onOpenBin: (Bin) -> Void

    var body: some View {
        let picked = list.isPicked(bin)
        let hasItems = !store.chosenItems(in: list, bin: bin).isEmpty
        Button {
            store.setPicked(bin, in: list, !picked)
        } label: {
            HStack(spacing: 12) {
                CheckMark(checked: picked)
                BinBadge(code: bin.code, colorName: bin.colorName)
                    .opacity(picked ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bin.displayName).font(.headline).strikethrough(picked)
                    Text(store.spot(bin.spotId)?.name ?? "No location set")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if hasItems {
                        Text("Pull the items below").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .sensoryFeedback(.success, trigger: picked) { _, new in new }
        .swipeActions {
            Button(role: .destructive) {
                store.updatePickList(list, name: list.name,
                                     binIds: list.binIds.filter { $0 != bin.id },
                                     itemIds: list.itemIds.filter { id in store.items.first { $0.id == id }?.binId != bin.id })
            } label: { Label("Remove", systemImage: "minus.circle") }
        }
        .contextMenu {
            Button { onOpenBin(bin) } label: { Label("Open bin", systemImage: "shippingbox") }
        }
    }
}

struct PickItemRow: View {
    @Environment(HouseholdStore.self) private var store
    let list: PickList
    let item: Item

    var body: some View {
        let picked = list.isPicked(item)
        Button {
            store.setPicked(item, in: list, !picked)
        } label: {
            HStack(spacing: 12) {
                CheckMark(checked: picked)
                Text(item.name).strikethrough(picked)
                Spacer()
                if item.quantity != 1 {
                    Text("×\(item.quantity)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.leading, 32)
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .sensoryFeedback(.success, trigger: picked) { _, new in new }
        .swipeActions {
            Button(role: .destructive) {
                store.updatePickList(list, name: list.name, binIds: list.binIds,
                                     itemIds: list.itemIds.filter { $0 != item.id })
            } label: { Label("Remove", systemImage: "minus.circle") }
        }
    }
}

// MARK: - New / edit pick list
struct PickListEditorView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let list: PickList?
    var startingBinIds: [String] = []
    var onCreate: ((String) -> Void)? = nil

    @State private var name = ""
    @State private var binIds: [String] = []
    @State private var itemIds: Set<String> = []
    @State private var query = ""
    @State private var loaded = false

    init(list: PickList?, startingBinIds: [String] = [], onCreate: ((String) -> Void)? = nil) {
        self.list = list
        self.startingBinIds = startingBinIds
        self.onCreate = onCreate
    }

    private var shownBins: [Bin] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.bins
            .filter { bin in
                q.isEmpty || bin.code.localizedCaseInsensitiveContains(q) || bin.name.localizedCaseInsensitiveContains(q)
                    || store.items(in: bin).contains { $0.name.localizedCaseInsensitiveContains(q) }
            }
            .sorted {
                // Chosen bins first, then by ID.
                let a = binIds.contains($0.id), b = binIds.contains($1.id)
                if a != b { return a }
                return $0.code.localizedStandardCompare($1.code) == .orderedAscending
            }
    }

    private var defaultName: String {
        "Pick list " + Date.now.formatted(.dateTime.month(.abbreviated).day())
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Name") {
                    TextField(defaultName, text: $name)
                }
                Section {
                    ForEach(shownBins) { bin in
                        editorRow(bin)
                    }
                } header: {
                    Text(binIds.isEmpty ? "Choose bins" : "Bins (\(binIds.count) chosen)")
                } footer: {
                    Text("Tap bins to add them. To pull just some things from a bin, tap Choose items.")
                }
            }
            .searchable(text: $query, prompt: "Bin ID, name or item")
            .navigationTitle(list == nil ? "New pick list" : "Edit pick list")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: BinRef.self) { ref in
                if let bin = store.bin(ref.id) {
                    PickItemsChooser(bin: bin, itemIds: $itemIds, binIds: $binIds)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(list == nil ? "Create" : "Save", action: save).disabled(binIds.isEmpty)
                }
                if !store.categories.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Menu {
                            ForEach(store.categories) { c in
                                Button("\(c.name) (\(store.bins(in: c).count))") {
                                    for bin in store.bins(in: c) where !binIds.contains(bin.id) { binIds.append(bin.id) }
                                }
                            }
                        } label: {
                            Label("Add a category's bins", systemImage: "tag")
                        }
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let list {
                    name = list.name
                    binIds = list.binIds
                    itemIds = Set(list.itemIds)
                } else {
                    binIds = startingBinIds
                }
            }
        }
    }

    @ViewBuilder
    private func editorRow(_ bin: Bin) -> some View {
        let chosen = binIds.contains(bin.id)
        let chosenItems = store.items(in: bin).filter { itemIds.contains($0.id) }
            Button {
                if chosen {
                    binIds.removeAll { $0 == bin.id }
                    chosenItems.forEach { itemIds.remove($0.id) }
                } else {
                    binIds.append(bin.id)
                }
            } label: {
                HStack(spacing: 12) {
                    BinBadge(code: bin.code, colorName: bin.colorName)
                    VStack(alignment: .leading) {
                        Text(bin.displayName)
                        Text(store.locationPath(of: bin)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(chosen ? Color.accentColor : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .tint(.primary)

            if chosen && !store.items(in: bin).isEmpty {
                NavigationLink(value: BinRef(id: bin.id)) {
                    Text(chosenItems.isEmpty ? "Whole bin · Choose items"
                                             : "\(chosenItems.count) item\(chosenItems.count == 1 ? "" : "s"): "
                                               + chosenItems.map(\.name).joined(separator: ", "))
                        .font(.subheadline)
                        .lineLimit(2)
                }
                .padding(.leading, 68)
            }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? defaultName : trimmed
        // Keep only items whose bins are still on the list.
        let keptItems = store.items.filter { itemIds.contains($0.id) && binIds.contains($0.binId) }.map(\.id)
        if let list {
            store.updatePickList(list, name: finalName, binIds: binIds, itemIds: keptItems)
        } else {
            let id = store.createPickList(name: finalName, binIds: binIds, itemIds: keptItems)
            onCreate?(id)
        }
        dismiss()
    }
}

/// Tick the specific items to pull from one bin. None ticked means "grab the whole bin".
struct PickItemsChooser: View {
    @Environment(HouseholdStore.self) private var store
    let bin: Bin
    @Binding var itemIds: Set<String>
    @Binding var binIds: [String]

    var body: some View {
        List {
            Section {
                ForEach(store.items(in: bin)) { item in
                    let chosen = itemIds.contains(item.id)
                    Button {
                        if chosen { itemIds.remove(item.id) } else {
                            itemIds.insert(item.id)
                            if !binIds.contains(bin.id) { binIds.append(bin.id) }
                        }
                    } label: {
                        HStack {
                            Text(item.name)
                            if item.quantity != 1 { Text("×\(item.quantity)").foregroundStyle(.secondary) }
                            Spacer()
                            Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(chosen ? Color.accentColor : Color.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .tint(.primary)
                }
            } footer: {
                Text("Leave everything unticked to grab the whole bin.")
            }
        }
        .navigationTitle("Items in \(bin.code)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - "Add to pick list" menu used on bin and item screens
struct AddToPickListMenu<Label: View>: View {
    @Environment(HouseholdStore.self) private var store
    let bin: Bin
    var item: Item? = nil
    let onNewList: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            ForEach(store.pickLists) { list in
                let already = item.map { list.itemIds.contains($0.id) } ?? list.binIds.contains(bin.id)
                Button {
                    if let item { store.add(item, to: list) } else { store.add(bin, to: list) }
                } label: {
                    if already { SwiftUI.Label(list.name, systemImage: "checkmark") } else { Text(list.name) }
                }
                .disabled(already)
            }
            Button(action: onNewList) {
                SwiftUI.Label("New pick list…", systemImage: "plus")
            }
        } label: { label() }
    }
}
