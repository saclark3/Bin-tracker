import SwiftUI
import SwiftData

enum BinSort: String, CaseIterable, Identifiable {
    case recent = "Recently used"
    case frequent = "Most used"
    case code = "Bin ID"
    var id: String { rawValue }
}

struct BinsView: View {
    @Environment(\.modelContext) private var context
    @Query private var bins: [Bin]

    @State private var path: [Bin] = []
    @State private var sort: BinSort = .recent
    @State private var jumpCode = ""
    @State private var jumpError: String?
    @State private var showingNewBin = false
    @FocusState private var jumpFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack {
                        Image(systemName: "number")
                            .foregroundStyle(.secondary)
                        TextField("Type a bin ID, e.g. B12 or 12", text: $jumpCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($jumpFocused)
                            .submitLabel(.go)
                            .onSubmit(jump)
                        if !jumpCode.isEmpty {
                            Button("Open", action: jump)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    if let jumpError {
                        Text(jumpError).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Go to bin")
                }

                Section {
                    if bins.isEmpty {
                        ContentUnavailableView("No bins yet",
                                               systemImage: "shippingbox",
                                               description: Text("Tap + to add your first bin. Write its ID on the box."))
                    }
                    ForEach(sortedBins) { bin in
                        NavigationLink(value: bin) { BinRow(bin: bin) }
                    }
                    .onDelete(perform: delete)
                } header: {
                    Picker("Sort", selection: $sort) {
                        ForEach(BinSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .textCase(nil)
                    .padding(.bottom, 4)
                }
            }
            .navigationTitle("Bins")
            .navigationDestination(for: Bin.self) { BinDetailView(bin: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewBin = true } label: { Label("New bin", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $showingNewBin) {
                BinEditorView(bin: nil) { newBin in path.append(newBin) }
            }
            .onChange(of: jumpCode) { jumpError = nil }
        }
    }

    private var sortedBins: [Bin] {
        switch sort {
        case .recent:
            bins.sorted { ($0.lastAccessed ?? $0.createdAt) > ($1.lastAccessed ?? $1.createdAt) }
        case .frequent:
            bins.sorted { $0.accessCount(sinceDaysAgo: 30) > $1.accessCount(sinceDaysAgo: 30) }
        case .code:
            bins.sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }
        }
    }

    private func jump() {
        guard !jumpCode.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let bin = BinCode.find(jumpCode, in: context) {
            jumpCode = ""
            jumpFocused = false
            path.append(bin)
        } else {
            jumpError = "No bin with ID \(BinCode.lookupKey(jumpCode))."
        }
    }

    private func delete(at offsets: IndexSet) {
        let list = sortedBins
        for i in offsets { context.delete(list[i]) }
    }
}

struct BinRow: View {
    let bin: Bin

    var body: some View {
        HStack(spacing: 12) {
            BinBadge(code: bin.code, colorName: bin.colorName)
            VStack(alignment: .leading, spacing: 2) {
                Text(bin.name.isEmpty ? "Untitled bin" : bin.name).font(.headline)
                Text(bin.locationPath).font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label("\(bin.items.count)", systemImage: "list.bullet")
                    Label("\(bin.accessCount(sinceDaysAgo: 30))× in 30d", systemImage: "clock.arrow.circlepath")
                    if let last = bin.lastAccessed {
                        Text(last.relativeDescription)
                    }
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
