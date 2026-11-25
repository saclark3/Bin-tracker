import SwiftUI

struct BinDetailView: View {
    @Environment(HouseholdStore.self) private var store
    let binId: String

    @State private var quickItem = ""
    @State private var editingItem: Item?
    @State private var showingEditBin = false
    @State private var showingHistory = false
    @State private var loggedView = false
    @FocusState private var quickFocused: Bool

    var body: some View {
        if let bin = store.bin(binId) {
            content(bin)
        } else {
            ContentUnavailableView("Bin not found", systemImage: "shippingbox",
                                   description: Text("It may have been deleted on another device."))
        }
    }

    private func content(_ bin: Bin) -> some View {
        List {
            Section {
                VStack(spacing: 8) {
                    BinBadge(code: bin.code, colorName: bin.colorName, large: true)
                    if !bin.name.isEmpty { Text(bin.name).font(.title3.bold()) }
                    Label(store.locationPath(of: bin), systemImage: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                    let cats = store.categories(of: bin)
                    if !cats.isEmpty {
                        FlowLayout(alignment: .center) { ForEach(cats) { CategoryChip(category: $0) } }
                    }
                    if !bin.notes.isEmpty {
                        Text(bin.notes).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            let items = store.items(in: bin)
            Section("Contents (\(items.count))") {
                HStack {
                    TextField("Add an item…", text: $quickItem)
                        .focused($quickFocused)
                        .submitLabel(.done)
                        .onSubmit { addQuickItem(to: bin) }
                    Button { addQuickItem(to: bin) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .disabled(quickItem.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(items) { item in
                    Button { editingItem = item } label: { ItemRow(item: item) }
                        .tint(.primary)
                }
                .onDelete { offsets in offsets.forEach { store.deleteItem(items[$0]) } }
            }

            Section("Usage") {
                LabeledContent("Last accessed", value: bin.lastAccessed?.relativeDescription ?? "Never")
                LabeledContent("Last 7 days", value: "\(store.accessCount(bin, days: 7))×")
                LabeledContent("Last 30 days", value: "\(store.accessCount(bin, days: 30))×")
                LabeledContent("All time", value: "\(bin.accessCount)×")
                Button {
                    store.logAccess(.opened, for: bin)
                } label: {
                    Label("I just opened this box", systemImage: "shippingbox.and.arrow.backward")
                }
                Button("Access history") { showingHistory = true }
            }
        }
        .navigationTitle(bin.code)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Edit") { showingEditBin = true } }
        .onAppear {
            guard !loggedView else { return }
            loggedView = true
            store.logAccess(.viewed, for: bin)
        }
        .sheet(item: $editingItem) { ItemEditorView(item: $0) }
        .sheet(isPresented: $showingEditBin) { BinEditorView(bin: bin) }
        .sheet(isPresented: $showingHistory) { AccessHistoryView(bin: bin) }
    }

    private func addQuickItem(to bin: Bin) {
        let name = quickItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.addItem(named: name, to: bin)
        quickItem = ""
        quickFocused = true   // keep keyboard up for rapid entry while packing a box
    }
}

struct ItemRow: View {
    let item: Item
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.name)
                if !item.notes.isEmpty {
                    Text(item.notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if item.quantity != 1 {
                Text("×\(item.quantity)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .contentShape(Rectangle())
    }
}

struct AccessHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HouseholdStore.self) private var store
    let bin: Bin

    var body: some View {
        NavigationStack {
            List {
                let events = store.events(for: bin)
                if events.isEmpty {
                    Text("No activity in the last \(HouseholdStore.historyDays) days").foregroundStyle(.secondary)
                }
                ForEach(events) { event in
                    HStack {
                        Label {
                            VStack(alignment: .leading) {
                                Text(event.kind.label)
                                if !event.by.isEmpty {
                                    Text(event.by).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } icon: { Image(systemName: event.kind.symbol) }
                        Spacer()
                        Text(event.date, format: .dateTime.month().day().hour().minute())
                            .foregroundStyle(.secondary).font(.caption)
                    }
                }
            }
            .navigationTitle("\(bin.code) history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
