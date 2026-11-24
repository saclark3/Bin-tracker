import SwiftUI
import SwiftData

// MARK: - Bin editor (new + edit)
struct BinEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Area.name) private var areas: [Area]

    let bin: Bin?
    var onCreate: ((Bin) -> Void)? = nil
    var presetLocation: StorageLocation? = nil

    @State private var code = ""
    @State private var name = ""
    @State private var notes = ""
    @State private var colorName = BinColor.blue.rawValue
    @State private var location: StorageLocation?
    @State private var loaded = false

    init(bin: Bin?, presetLocation: StorageLocation? = nil, onCreate: ((Bin) -> Void)? = nil) {
        self.bin = bin
        self.presetLocation = presetLocation
        self.onCreate = onCreate
    }

    private var codeError: String? {
        let c = BinCode.normalize(code)
        if c.isEmpty { return "Enter an ID to write on the box." }
        if c.count > BinCode.maxLength { return "Keep it to \(BinCode.maxLength) characters or fewer so it's easy to write." }
        if BinCode.isTaken(c, excluding: bin, in: context) { return "\(c) is already used by another bin." }
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
                        BinBadge(code: BinCode.normalize(code).isEmpty ? "?" : BinCode.normalize(code), colorName: colorName)
                    }
                    if let codeError, !code.isEmpty || bin != nil {
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
                    Picker("Location", selection: $location) {
                        Text("Not set").tag(StorageLocation?.none)
                        ForEach(areas) { area in
                            ForEach(area.sortedLocations) { loc in
                                Text(loc.fullPath).tag(StorageLocation?.some(loc))
                            }
                        }
                    }
                } header: {
                    Text("Where is it?")
                } footer: {
                    if areas.allSatisfy({ $0.locations.isEmpty }) {
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
        loaded = true
        if let bin {
            code = bin.code; name = bin.name; notes = bin.notes
            colorName = bin.colorName; location = bin.location
        } else {
            code = BinCode.next(in: context)
            location = presetLocation
        }
    }

    private func save() {
        let c = BinCode.normalize(code)
        if let bin {
            bin.code = c; bin.name = name; bin.notes = notes
            bin.colorName = colorName; bin.location = location
        } else {
            let new = Bin(code: c, name: name, notes: notes, colorName: colorName, location: location)
            context.insert(new)
            onCreate?(new)
        }
        dismiss()
    }
}

// MARK: - Item editor
struct ItemEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Bin.code) private var allBins: [Bin]

    @Bindable var item: Item
    let bin: Bin

    @State private var name = ""
    @State private var quantity = 1
    @State private var notes = ""
    @State private var targetBin: Bin?
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
                    Picker("Bin", selection: $targetBin) {
                        ForEach(allBins) { b in
                            Text(b.name.isEmpty ? b.code : "\(b.code) · \(b.name)").tag(Bin?.some(b))
                        }
                    }
                }
                Section {
                    Button("Remove from bin", role: .destructive) {
                        context.delete(item)
                        AccessLogger.log(.edited, for: bin, in: context)
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
                name = item.name; quantity = item.quantity; notes = item.notes; targetBin = bin
            }
        }
    }

    private func save() {
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.quantity = quantity
        item.notes = notes
        item.updatedAt = .now
        if let targetBin, targetBin !== bin {
            item.bin = targetBin
            AccessLogger.log(.edited, for: targetBin, in: context)
        }
        AccessLogger.log(.edited, for: bin, in: context)
        dismiss()
    }
}
