import Foundation

// Data passed between the iPhone app and the Apple Watch app over WatchConnectivity.
// This file is compiled into both apps, so it must not import Firebase.
//
// How it works:
// - The iPhone sends the watch a snapshot of the household (bins, their items, and pick lists)
//   whenever something changes. The watch saves it, so it keeps working when the phone is
//   downstairs, out of range or switched off.
// - Each check-off or quick add on the watch becomes a `WatchCommand`. The watch applies it to
//   its own copy right away, saves it in a pending queue, and hands it to WatchConnectivity,
//   which delivers it to the phone as soon as the two can talk again (Bluetooth or the same Wi-Fi).
// - The phone writes the command to Firestore and lists its ID in `appliedCommandIds` of the next
//   snapshot, so the watch knows it can drop it from the queue.

enum WatchKeys {
    static let snapshot = "snapshot"          // Data: compressed JSON WatchSnapshot
    static let command = "command"            // Data: JSON WatchCommand
    static let requestSnapshot = "requestSnapshot"
    static let ack = "ack"                    // [String]: command IDs the phone has written
}

struct WatchSnapshot: Codable, Equatable {
    var householdName: String
    var generatedAt: Date
    var bins: [WatchBin]
    var pickLists: [WatchPickList]
    /// Recent watch commands the phone has written to Firestore.
    var appliedCommandIds: [String]

    static let empty = WatchSnapshot(householdName: "", generatedAt: .distantPast, bins: [], pickLists: [], appliedCommandIds: [])

    var isSignedOut: Bool { householdName.isEmpty }

    func bin(_ id: String) -> WatchBin? { bins.first { $0.id == id } }
    func pickList(_ id: String) -> WatchPickList? { pickLists.first { $0.id == id } }

    /// Lookup ignoring case, spaces and dashes; a bare number like "12" also matches "B12".
    func find(code raw: String) -> WatchBin? {
        func norm(_ s: String) -> String { s.uppercased().filter { !$0.isWhitespace && $0 != "-" } }
        let exact = norm(raw)
        guard !exact.isEmpty else { return nil }
        let key = exact.allSatisfy(\.isNumber) ? "B" + exact : exact
        return bins.first { norm($0.code) == exact } ?? bins.first { norm($0.code) == key }
    }

    /// Applies a watch command to this copy, the same way the phone will apply it to Firestore.
    mutating func apply(_ command: WatchCommand) {
        switch command.action {
        case let .setBinPicked(listId, binId, picked, _):
            guard let l = pickLists.firstIndex(where: { $0.id == listId }),
                  let e = pickLists[l].entries.firstIndex(where: { $0.binId == binId }) else { return }
            pickLists[l].entries[e].picked = picked
        case let .setItemPicked(listId, itemId, binId, picked, _):
            guard let l = pickLists.firstIndex(where: { $0.id == listId }),
                  let e = pickLists[l].entries.firstIndex(where: { $0.binId == binId }),
                  let i = pickLists[l].entries[e].items.firstIndex(where: { $0.id == itemId }) else { return }
            pickLists[l].entries[e].items[i].picked = picked
        case let .addItem(binId, name, itemId):
            guard let b = bins.firstIndex(where: { $0.id == binId }),
                  !bins[b].items.contains(where: { $0.id == itemId }) else { return }
            bins[b].items.append(WatchItem(id: itemId, name: name, quantity: 1))
            bins[b].items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            bins[b].lastAccessed = command.date
        }
    }
}

struct WatchBin: Codable, Identifiable, Hashable {
    var id: String
    var code: String
    var name: String
    var colorName: String
    /// "Garage › Shelf 2"
    var location: String
    var lastAccessed: Date?
    var items: [WatchItem]

    var displayName: String { name.isEmpty ? "Untitled bin" : name }
}

struct WatchItem: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var quantity: Int
}

struct WatchPickList: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var createdAt: Date
    /// Bins in walking order (sorted by location), each with any specific items to pull.
    var entries: [WatchPickEntry]

    var total: Int { entries.reduce(0) { $0 + 1 + $1.items.count } }
    var done: Int { entries.reduce(0) { $0 + ($1.picked ? 1 : 0) + $1.items.filter(\.picked).count } }
    var isComplete: Bool { total > 0 && done == total }
}

struct WatchPickEntry: Codable, Identifiable, Hashable {
    var binId: String
    var code: String
    var name: String
    var colorName: String
    var location: String
    var picked: Bool
    var items: [WatchPickItem]

    var id: String { binId }
    var displayName: String { name.isEmpty ? "Untitled bin" : name }
}

struct WatchPickItem: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var quantity: Int
    var picked: Bool
}

struct WatchCommand: Codable, Identifiable, Equatable {
    enum Action: Codable, Equatable {
        /// `logOpened`: also count this as the bin being opened (first check-off for that bin).
        case setBinPicked(listId: String, binId: String, picked: Bool, logOpened: Bool)
        case setItemPicked(listId: String, itemId: String, binId: String, picked: Bool, logOpened: Bool)
        /// `itemId` is chosen on the watch so the item can't be created twice.
        case addItem(binId: String, name: String, itemId: String)
    }

    var id: String = UUID().uuidString
    var date: Date = .now
    var action: Action
}

enum WatchCoding {
    static func encode<T: Encodable>(_ value: T, compress: Bool = false) throws -> Data {
        let data = try JSONEncoder().encode(value)
        return compress ? try (data as NSData).compressed(using: .lzfse) as Data : data
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, compressed: Bool = false) throws -> T {
        let raw = compressed ? try (data as NSData).decompressed(using: .lzfse) as Data : data
        return try JSONDecoder().decode(type, from: raw)
    }
}
