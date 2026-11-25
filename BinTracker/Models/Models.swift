import Foundation
import SwiftUI
import FirebaseFirestore

// Plain value types mirrored from Firestore documents under
// households/{householdId}/{areas|spots|bins|items|events|categories}.

private func fsDate(_ value: Any?) -> Date? { (value as? Timestamp)?.dateValue() }

// MARK: - Area
/// A part of the home, such as "Garage" or "Basement".
struct Area: Identifiable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var createdAt: Date

    init(id: String, name: String, symbol: String, createdAt: Date = .now) {
        self.id = id; self.name = name; self.symbol = symbol; self.createdAt = createdAt
    }

    init?(_ doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let name = d["name"] as? String else { return nil }
        self.init(id: doc.documentID, name: name,
                  symbol: d["symbol"] as? String ?? "square.grid.2x2",
                  createdAt: fsDate(d["createdAt"]) ?? .now)
    }

    var data: [String: Any] { ["name": name, "symbol": symbol, "createdAt": createdAt] }
}

// MARK: - Spot
/// A specific place inside an area, such as "Shelf 2" or "Under stairs".
struct Spot: Identifiable, Hashable {
    var id: String
    var areaId: String
    var name: String

    init(id: String, areaId: String, name: String) {
        self.id = id; self.areaId = areaId; self.name = name
    }

    init?(_ doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let name = d["name"] as? String, let areaId = d["areaId"] as? String else { return nil }
        self.init(id: doc.documentID, areaId: areaId, name: name)
    }

    var data: [String: Any] { ["name": name, "areaId": areaId] }
}

// MARK: - Bin
struct Bin: Identifiable, Hashable {
    var id: String
    /// Short ID hand-written on the box, e.g. "B7". Unique within the household.
    var code: String
    var name: String
    var notes: String
    var colorName: String
    var spotId: String?
    /// Categories this bin belongs to (a bin can be in several).
    var categoryIds: [String]
    var createdAt: Date
    var lastAccessed: Date?
    var accessCount: Int

    init(id: String, code: String, name: String = "", notes: String = "", colorName: String = "blue",
         spotId: String? = nil, categoryIds: [String] = [], createdAt: Date = .now,
         lastAccessed: Date? = nil, accessCount: Int = 0) {
        self.id = id; self.code = code; self.name = name; self.notes = notes
        self.colorName = colorName; self.spotId = spotId; self.categoryIds = categoryIds
        self.createdAt = createdAt; self.lastAccessed = lastAccessed; self.accessCount = accessCount
    }

    init?(_ doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let code = d["code"] as? String else { return nil }
        self.init(id: doc.documentID, code: code,
                  name: d["name"] as? String ?? "",
                  notes: d["notes"] as? String ?? "",
                  colorName: d["colorName"] as? String ?? "blue",
                  spotId: d["spotId"] as? String,
                  categoryIds: d["categoryIds"] as? [String] ?? [],
                  createdAt: fsDate(d["createdAt"]) ?? .now,
                  lastAccessed: fsDate(d["lastAccessed"]),
                  accessCount: d["accessCount"] as? Int ?? 0)
    }

    /// Fields the editor owns. Access stats are updated separately so edits never reset them.
    var editableData: [String: Any] {
        ["code": code, "name": name, "notes": notes, "colorName": colorName,
         "spotId": spotId.map { $0 as Any } ?? NSNull(), "categoryIds": categoryIds,
         "createdAt": createdAt]
    }

    var displayName: String { name.isEmpty ? "Untitled bin" : name }
}

// MARK: - Category
/// A household-wide label such as "Holiday" or "Camping". Bins can have any number of them.
struct BinCategory: Identifiable, Hashable {
    var id: String
    var name: String
    var colorName: String
    var createdAt: Date

    init(id: String, name: String, colorName: String = "blue", createdAt: Date = .now) {
        self.id = id; self.name = name; self.colorName = colorName; self.createdAt = createdAt
    }

    init?(_ doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let name = d["name"] as? String else { return nil }
        self.init(id: doc.documentID, name: name,
                  colorName: d["colorName"] as? String ?? "blue",
                  createdAt: fsDate(d["createdAt"]) ?? .now)
    }

    var data: [String: Any] { ["name": name, "colorName": colorName, "createdAt": createdAt] }
}

// MARK: - Item
struct Item: Identifiable, Hashable {
    var id: String
    var binId: String
    var name: String
    var quantity: Int
    var notes: String
    var updatedAt: Date

    init(id: String, binId: String, name: String, quantity: Int = 1, notes: String = "", updatedAt: Date = .now) {
        self.id = id; self.binId = binId; self.name = name
        self.quantity = quantity; self.notes = notes; self.updatedAt = updatedAt
    }

    init?(_ doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let name = d["name"] as? String, let binId = d["binId"] as? String else { return nil }
        self.init(id: doc.documentID, binId: binId, name: name,
                  quantity: d["quantity"] as? Int ?? 1,
                  notes: d["notes"] as? String ?? "",
                  updatedAt: fsDate(d["updatedAt"]) ?? .now)
    }

    var data: [String: Any] {
        ["binId": binId, "name": name, "quantity": quantity, "notes": notes, "updatedAt": updatedAt]
    }
}

// MARK: - AccessEvent
/// One record each time someone opens a bin's screen, marks it opened, or changes its contents.
struct AccessEvent: Identifiable, Hashable {
    var id: String
    var binId: String
    var kind: AccessKind
    var date: Date
    var by: String

    init?(_ doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let binId = d["binId"] as? String, let when = fsDate(d["date"]) else { return nil }
        id = doc.documentID
        self.binId = binId
        kind = AccessKind(rawValue: d["kind"] as? String ?? "") ?? .viewed
        self.date = when
        by = d["by"] as? String ?? ""
    }
}

enum AccessKind: String, CaseIterable {
    case viewed, edited, opened

    var label: String {
        switch self {
        case .viewed: "Viewed in app"
        case .edited: "Contents changed"
        case .opened: "Opened physically"
        }
    }

    var symbol: String {
        switch self {
        case .viewed: "eye"
        case .edited: "pencil"
        case .opened: "shippingbox.and.arrow.backward"
        }
    }
}

// MARK: - Bin codes
/// Codes are hand-written on boxes, so they stay short: B1, B2, B3…
/// GUESS: a single "B" prefix plus a number. Any short code can be typed instead
/// (e.g. "G4" for Garage), and lookups ignore case, spaces and dashes.
enum BinCode {
    static let prefix = "B"
    static let maxLength = 8

    static func next(after bins: [Bin]) -> String {
        let used = Set(bins.map { (bin: Bin) -> String in normalize(bin.code) })
        let numbers = bins.compactMap { (bin: Bin) -> Int? in
            let c = normalize(bin.code)
            guard c.hasPrefix(prefix) else { return nil }
            return Int(c.dropFirst(prefix.count))
        }
        var n = (numbers.max() ?? 0) + 1
        while used.contains(prefix + String(n)) { n += 1 }
        return prefix + String(n)
    }

    /// Uppercases and strips spaces/dashes so "b 12", "B-12" and "b12" all match.
    static func normalize(_ raw: String) -> String {
        raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    }

    /// A bare number like "12" is treated as "B12".
    static func lookupKey(_ raw: String) -> String {
        let n = normalize(raw)
        if !n.isEmpty, n.allSatisfy(\.isNumber) { return prefix + n }
        return n
    }
}

// MARK: - Bin label colours
enum BinColor: String, CaseIterable, Identifiable {
    case blue, green, orange, red, purple, yellow, gray
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .purple: .purple
        case .yellow: .yellow
        case .gray: .gray
        }
    }
    static func color(named name: String) -> Color { (BinColor(rawValue: name) ?? .blue).color }
}

enum AreaSymbol {
    static func guess(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("garage") { return "car" }
        if n.contains("basement") { return "stairs" }
        if n.contains("attic") { return "house.lodge" }
        if n.contains("closet") { return "cabinet" }
        if n.contains("bed") { return "bed.double" }
        if n.contains("kitchen") || n.contains("pantry") { return "refrigerator" }
        if n.contains("office") { return "desktopcomputer" }
        if n.contains("shed") || n.contains("yard") { return "tree" }
        if n.contains("bath") { return "bathtub" }
        return "square.grid.2x2"
    }
}

extension Date {
    var relativeDescription: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: self, relativeTo: .now)
    }
}

/// Navigation value for opening a bin by its document ID.
struct BinRef: Hashable { let id: String }
