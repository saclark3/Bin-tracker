import SwiftUI

// MARK: - Categories tab
/// All categories with how many bins are in each. Tap one to see and change its bins.
struct CategoriesView: View {
    @Environment(HouseholdStore.self) private var store

    @State private var showingNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if store.categories.isEmpty {
                    ContentUnavailableView {
                        Label("No categories yet", systemImage: "tag")
                    } description: {
                        Text("Group bins by what's in them, like Holiday, Camping or Tools. A bin can be in more than one category.")
                    } actions: {
                        Button("New category") { showingNew = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                ForEach(store.categories) { category in
                    NavigationLink(value: category) {
                        HStack {
                            CategoryDot(colorName: category.colorName)
                            Text(category.name)
                            Spacer()
                            Text("\(store.bins(in: category).count) bins")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let list = store.categories
                    offsets.forEach { store.deleteCategory(list[$0]) }
                }
            }
            .navigationTitle("Categories")
            .navigationDestination(for: BinCategory.self) { CategoryDetailView(categoryId: $0.id) }
            .navigationDestination(for: BinRef.self) { BinDetailView(binId: $0.id) }
            .toolbar {
                Button { showingNew = true } label: { Label("New category", systemImage: "plus") }
            }
            .alert("New category", isPresented: $showingNew) {
                TextField("e.g. Holiday", text: $newName)
                Button("Add") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { store.addCategory(name) }
                    newName = ""
                }
                Button("Cancel", role: .cancel) { newName = "" }
            }
        }
    }
}

// MARK: - One category
struct CategoryDetailView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let categoryId: String

    @State private var showingAddBins = false
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var confirmingDelete = false

    var body: some View {
        if let category = store.category(categoryId) {
            content(category)
        } else {
            ContentUnavailableView("Category not found", systemImage: "tag",
                                   description: Text("It may have been deleted on another device."))
        }
    }

    private func content(_ category: BinCategory) -> some View {
        let bins = store.bins(in: category)
        return List {
            Section {
                if bins.isEmpty {
                    Text("No bins in this category yet.").foregroundStyle(.secondary)
                }
                ForEach(bins) { bin in
                    NavigationLink(value: BinRef(id: bin.id)) { BinRow(bin: bin) }
                        .swipeActions {
                            Button("Remove") { store.setBin(bin, in: category, false) }
                                .tint(.orange)
                        }
                }
                Button { showingAddBins = true } label: {
                    Label("Add or remove bins", systemImage: "checklist")
                }
            } header: {
                Text("Bins (\(bins.count))")
            } footer: {
                Text("Swipe a bin to take it out of this category. The bin itself isn't deleted.")
            }

            Section("Colour") {
                Picker("Colour", selection: Binding<String>(
                    get: { category.colorName },
                    set: { var c = category; c.colorName = $0; store.updateCategory(c) }
                )) {
                    ForEach(BinColor.allCases) { c in
                        Label(c.rawValue.capitalized, systemImage: "circle.fill")
                            .foregroundStyle(c.color)
                            .tag(c.rawValue)
                    }
                }
            }

            Section {
                Button("Rename") {
                    renameText = category.name
                    showingRename = true
                }
                Button("Delete category", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddBins) { CategoryBinsPicker(category: category) }
        .alert("Rename category", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, !store.categoryNameTaken(name, excluding: category.id) {
                    var c = category; c.name = name; store.updateCategory(c)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(category.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete category", role: .destructive) {
                store.deleteCategory(category)
                dismiss()
            }
        } message: {
            Text("Its bins and their contents are kept. They just won't be in this category anymore.")
        }
    }
}

/// Tick the bins that belong in one category.
struct CategoryBinsPicker: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let category: BinCategory

    @State private var query = ""

    private var bins: [Bin] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.bins
            .filter { q.isEmpty || $0.code.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q) }
            .sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.bins.isEmpty {
                    Text("Add some bins first in the Bins tab.").foregroundStyle(.secondary)
                }
                ForEach(bins) { bin in
                    let included = bin.categoryIds.contains(category.id)
                    Button {
                        store.setBin(bin, in: category, !included)
                    } label: {
                        HStack(spacing: 12) {
                            BinBadge(code: bin.code, colorName: bin.colorName)
                            VStack(alignment: .leading) {
                                Text(bin.displayName)
                                Text(store.locationPath(of: bin)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: included ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(included ? Color.accentColor : Color.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .tint(.primary)
                }
            }
            .searchable(text: $query, prompt: "Bin ID or name")
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

// MARK: - Picker used in the bin editor
/// Multi-select list of categories, with a field to create a new one on the spot.
struct CategoryPickerView: View {
    @Environment(HouseholdStore.self) private var store
    @Binding var selection: [String]

    @State private var newName = ""
    @FocusState private var newFocused: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("New category", text: $newName)
                        .focused($newFocused)
                        .submitLabel(.done)
                        .onSubmit(addNew)
                    Button(action: addNew) { Image(systemName: "plus.circle.fill").font(.title2) }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("New categories are ticked for this bin and shared with everyone in your household.")
            }

            Section {
                if store.categories.isEmpty {
                    Text("No categories yet. Type one above to create it.").foregroundStyle(.secondary)
                }
                ForEach(store.categories) { category in
                    let on = selection.contains(category.id)
                    Button {
                        if on { selection.removeAll { $0 == category.id } } else { selection.append(category.id) }
                    } label: {
                        HStack {
                            CategoryDot(colorName: category.colorName)
                            Text(category.name)
                            Spacer()
                            if on { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold) }
                        }
                        .contentShape(Rectangle())
                    }
                    .tint(.primary)
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addNew() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let id = store.addCategory(name)
        if !selection.contains(id) { selection.append(id) }
        newName = ""
        newFocused = true
    }
}

// MARK: - Small pieces

struct CategoryDot: View {
    let colorName: String
    var body: some View {
        Image(systemName: "tag.fill")
            .foregroundStyle(BinColor.color(named: colorName))
    }
}

struct CategoryChip: View {
    let category: BinCategory
    var body: some View {
        Text(category.name)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(BinColor.color(named: category.colorName))
            .background(BinColor.color(named: category.colorName).opacity(0.15), in: Capsule())
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        let proposed = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        return CGSize(width: proposed ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            if alignment == .center { x += (bounds.width - row.width) / 2 }
            else if alignment == .trailing { x = bounds.maxX - row.width }
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if extra > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
