import SwiftUI

// MARK: - Bin editor (new + edit)
struct BinEditorView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let bin: Bin?
    var presetSpotId: String?
    var onCreate: ((String) -> Void)?

    @State private var code = ""
    @State private var name = ""
    @State private var notes = ""
    @State private var colorName = BinColor.blue.rawValue
    @State private var spotId: String?
    @State private var loaded = false

    init(bin: Bin?, presetSpotId: String? = nil, onCreate: ((String) -> Void)? = nil) {
        self.bin = bin
        self.presetSpotId = presetSpotId
        self.onCreate = onCreate
    }

    private var codeError: String? {
        let c = BinCode.normalize(code)
        if c.isEmpty { return "Enter an ID to write on the box." }
        if c.count > BinCode.maxLength { return "Keep it to \(BinCode.maxLength) characters or fewer so it's easy to write." }
        if store.isTaken(c, excluding: bin?.id) { return "\(c) is already used by another bin." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("ID", text: $code)
                            .font(.system(.title, design: .rounded).weight(.heavy))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        let shown = BinCode.normalize(code)
                        BinBadge(code: shown.isEmpty ? "?" : shown, colorName: colorName)
                    }
                    if let codeError, loaded {
                        Text(codeError).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Bin ID")
                } footer: {
                    Text("Write this on the box. Short IDs like B12 are easiest to read from across the room.")
                }

                Section("Details") {
                    TextField("Name (optional), e.g. Holiday lights", text: $name)
                    Picker("Label colour", selection: $colorName) {
                        ForEach(BinColor.allCases) { c in
                            Label(c.rawValue.capitalized, systemImage: "circle.fill")
                                .foregroundStyle(c.color)
                                .tag(c.rawValue)
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                Section {
                    Picker("Location", selection: $spotId) {
                        Text("Not set").tag(String?.none)
                        ForEach(store.areas) { area in
                            ForEach(store.spots(in: area)) { spot in
                                Text(store.path(of: spot)).tag(String?.some(spot.id))
                            }
                        }
                    }
                } header: {
                    Text("Where is it?")
                } footer: {
                    if store.spots.isEmpty {
                        Text("Add areas and spots in the Areas tab to pick a location here.")
                    }
                }
            }
            .navigationTitle(bin == nil ? "New bin" : "Edit bin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(codeError != nil)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        if let bin {
            code = bin.code; name = bin.name; notes = bin.notes
            colorName = bin.colorName; spotId = bin.spotId
        } else {
            code = store.nextCode
            spotId = presetSpotId
        }
        loaded = true
    }

    private func save() {
        let c = BinCode.normalize(code)
        if var existing = bin {
            existing.code = c; existing.name = name; existing.notes = notes
            existing.colorName = colorName; existing.spotId = spotId
            store.updateBin(existing)
        } else {
            let newId = store.createBin(Bin(id: "", code: c, name: name, notes: notes,
                                            colorName: colorName, spotId: spotId))
            onCreate?(newId)
        }
        dismiss()
    }
}

// MARK: - Item editor
struct ItemEditorView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let item: Item

    @State private var name = ""
    @State private var quantity = 1
    @State private var notes = ""
    @State private var binId = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item name", text: $name)
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                Section("Move to another bin") {
                    Picker("Bin", selection: $binId) {
                        ForEach(store.bins.sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }) { b in
                            Text(b.name.isEmpty ? b.code : "\(b.code) · \(b.name)").tag(b.id)
                        }
                    }
                }
                Section {
                    Button("Remove from bin", role: .destructive) {
                        store.deleteItem(item)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                name = item.name; quantity = item.quantity; notes = item.notes; binId = item.binId
            }
        }
    }

    private func save() {
        var updated = item
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.quantity = quantity
        updated.notes = notes
        updated.binId = binId
        store.updateItem(updated, previousBinId: item.binId)
        dismiss()
    }
}
