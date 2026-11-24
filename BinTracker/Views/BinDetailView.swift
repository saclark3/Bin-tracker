import SwiftUI
import SwiftData

struct BinDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var bin: Bin

    @State private var quickItem = ""
    @State private var editingItem: Item?
    @State private var showingEditBin = false
    @State private var showingHistory = false
    @FocusState private var quickFocused: Bool

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    BinBadge(code: bin.code, colorName: bin.colorName, large: true)
                    if !bin.name.isEmpty { Text(bin.name).font(.title3.bold()) }
                    Label(bin.locationPath, systemImage: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                    if !bin.notes.isEmpty {
                        Text(bin.notes).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Contents (\(bin.items.count))") {
                HStack {
                    TextField("Add an item…", text: $quickItem)
                        .focused($quickFocused)
                        .submitLabel(.done)
                        .onSubmit(addQuickItem)
                    Button(action: addQuickItem) { Image(systemName: "plus.circle.fill").font(.title2) }
                        .disabled(quickItem.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(bin.sortedItems) { item in
                    Button { editingItem = item } label: { ItemRow(item: item) }
                        .tint(.primary)
                }
                .onDelete(perform: deleteItems)
            }

            Section("Usage") {
                LabeledContent("Last accessed", value: bin.lastAccessed?.relativeDescription ?? "Never")
                LabeledContent("Last 7 days", value: "\(bin.accessCount(sinceDaysAgo: 7))×")
                LabeledContent("Last 30 days", value: "\(bin.accessCount(sinceDaysAgo: 30))×")
                LabeledContent("All time", value: "\(bin.totalAccessCount)×")
                Button {
                    AccessLogger.log(.opened, for: bin, in: context)
                } label: {
                    Label("I just opened this box", systemImage: "shippingbox.and.arrow.backward")
                }
                Button("Access history") { showingHistory = true }
            }
        }
        .navigationTitle(bin.code)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { showingEditBin = true }
        }
        .onAppear { AccessLogger.log(.viewed, for: bin, in: context) }
        .sheet(item: $editingItem) { ItemEditorView(item: $0, bin: bin) }
        .sheet(isPresented: $showingEditBin) { BinEditorView(bin: bin) }
        .sheet(isPresented: $showingHistory) { AccessHistoryView(bin: bin) }
    }

    private func addQuickItem() {
        let name = quickItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let item = Item(name: name)
        context.insert(item)
        bin.items.append(item)
        AccessLogger.log(.edited, for: bin, in: context)
        quickItem = ""
        quickFocused = true   // keep keyboard up for rapid entry while packing a box
    }

    private func deleteItems(at offsets: IndexSet) {
        let list = bin.sortedItems
        for i in offsets { context.delete(list[i]) }
        AccessLogger.log(.edited, for: bin, in: context)
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
    let bin: Bin

    var body: some View {
        NavigationStack {
            List {
                if bin.accessEvents.isEmpty {
                    Text("No activity yet").foregroundStyle(.secondary)
                }
                ForEach(bin.recentEvents) { event in
                    HStack {
                        Label(event.kind.label, systemImage: event.kind.symbol)
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
