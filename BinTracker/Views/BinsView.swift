import SwiftUI

enum BinSort: String, CaseIterable, Identifiable {
    case recent = "Recently used"
    case frequent = "Most used"
    case code = "Bin ID"
    var id: String { rawValue }
}

struct BinsView: View {
    @Environment(HouseholdStore.self) private var store

    @State private var path: [BinRef] = []
    @State private var sort: BinSort = .recent
    @State private var jumpCode = ""
    @State private var jumpError: String?
    @State private var showingNewBin = false
    /// Show only bins in this category (nil = all bins).
    @State private var filterCategoryId: String?
    @FocusState private var jumpFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack {
                        Image(systemName: "number").foregroundStyle(.secondary)
                        TextField("Type a bin ID, e.g. B12 or 12", text: $jumpCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($jumpFocused)
                            .submitLabel(.go)
                            .onSubmit(jump)
                        if !jumpCode.isEmpty {
                            Button("Open", action: jump).buttonStyle(.borderedProminent)
                        }
                    }
                    if let jumpError {
                        Text(jumpError).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Go to bin")
                }

                Section {
                    if store.bins.isEmpty {
                        ContentUnavailableView("No bins yet",
                                               systemImage: "shippingbox",
                                               description: Text("Tap + to add your first bin. Write its ID on the box."))
                    } else if let filter = activeFilter, sortedBins.isEmpty {
                        Text("No bins in \(filter.name) yet.").foregroundStyle(.secondary)
                    }
                    ForEach(sortedBins) { bin in
                        NavigationLink(value: BinRef(id: bin.id)) { BinRow(bin: bin) }
                    }
                    .onDelete { offsets in
                        let list = sortedBins
                        offsets.forEach { store.deleteBin(list[$0]) }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Sort", selection: $sort) {
                            ForEach(BinSort.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if let filter = activeFilter {
                            Button { filterCategoryId = nil } label: {
                                Label("Showing \(filter.name) only", systemImage: "xmark.circle.fill")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .textCase(nil)
                    .padding(.bottom, 4)
                }
            }
            .navigationTitle("Bins")
            .navigationDestination(for: BinRef.self) { BinDetailView(binId: $0.id) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Category", selection: $filterCategoryId) {
                            Text("All bins").tag(String?.none)
                            ForEach(store.categories) { c in
                                Text("\(c.name) (\(store.bins(in: c).count))").tag(String?.some(c.id))
                            }
                        }
                        if store.categories.isEmpty {
                            Text("Create categories in the Categories tab")
                        }
                    } label: {
                        Label("Filter by category",
                              systemImage: activeFilter == nil ? "line.3.horizontal.decrease.circle"
                                                               : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewBin = true } label: { Label("New bin", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showingNewBin) {
                BinEditorView(bin: nil) { newId in path.append(BinRef(id: newId)) }
            }
            .onChange(of: jumpCode) { jumpError = nil }
        }
    }

    private var activeFilter: BinCategory? { store.category(filterCategoryId) }

    private var sortedBins: [Bin] {
        let shown = activeFilter.map { c in store.bins.filter { $0.categoryIds.contains(c.id) } } ?? store.bins
        switch sort {
        case .recent:
            return shown.sorted { ($0.lastAccessed ?? $0.createdAt) > ($1.lastAccessed ?? $1.createdAt) }
        case .frequent:
            return shown.sorted { store.accessCount($0, days: 30) > store.accessCount($1, days: 30) }
        case .code:
            return shown.sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }
        }
    }

    private func jump() {
        guard !jumpCode.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let bin = store.find(code: jumpCode) {
            jumpCode = ""
            jumpFocused = false
            path.append(BinRef(id: bin.id))
        } else {
            jumpError = "No bin with ID \(BinCode.lookupKey(jumpCode))."
        }
    }
}

struct BinRow: View {
    @Environment(HouseholdStore.self) private var store
    let bin: Bin

    var body: some View {
        HStack(spacing: 12) {
            BinBadge(code: bin.code, colorName: bin.colorName)
            VStack(alignment: .leading, spacing: 2) {
                Text(bin.displayName).font(.headline)
                Text(store.locationPath(of: bin)).font(.subheadline).foregroundStyle(.secondary)
                let cats = store.categories(of: bin)
                if !cats.isEmpty {
                    FlowLayout(spacing: 4) { ForEach(cats) { CategoryChip(category: $0) } }
                }
                HStack(spacing: 10) {
                    Label("\(store.items(in: bin).count)", systemImage: "list.bullet")
                    Label("\(store.accessCount(bin, days: 30))× in 30d", systemImage: "clock.arrow.circlepath")
                    if let last = bin.lastAccessed { Text(last.relativeDescription) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The bin ID drawn large, like the label written on the box.
struct BinBadge: View {
    let code: String
    let colorName: String
    var large = false

    var body: some View {
        Text(code)
            .font(large ? .system(size: 44, weight: .heavy, design: .rounded)
                        : .system(.headline, design: .rounded).weight(.heavy))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 20 : 8)
            .padding(.vertical, large ? 10 : 6)
            .frame(minWidth: large ? 120 : 56)
            .background(BinColor.color(named: colorName), in: RoundedRectangle(cornerRadius: large ? 16 : 10))
    }
}
