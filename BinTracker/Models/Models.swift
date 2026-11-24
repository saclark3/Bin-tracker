import Foundation
import SwiftData

// MARK: - Area
/// A part of the home, such as "Garage" or "Basement".
@Model
final class Area {
    var name: String
    var symbol: String          // SF Symbol name shown in lists
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StorageLocation.area)
    var locations: [StorageLocation] = []

    init(name: String, symbol: String = "house") {
        self.name = name
        self.symbol = symbol
        self.createdAt = .now
    }

    var sortedLocations: [StorageLocation] {
        locations.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var binCount: Int { locations.reduce(0) { $0 + $1.bins.count } }
}

// MARK: - StorageLocation
/// A specific spot inside an area, such as "Shelf 2" or "Under stairs".
/// (Named StorageLocation to avoid clashing with CoreLocation.)
@Model
final class StorageLocation {
    var name: String
    var area: Area?
    var createdAt: Date

    // Deleting a location keeps its bins; they just become "unplaced".
    @Relationship(deleteRule: .nullify, inverse: \Bin.location)
    var bins: [Bin] = []

    init(name: String, area: Area? = nil) {
        self.name = name
        self.area = area
        self.createdAt = .now
    }

    /// "Garage › Shelf 2"
    var fullPath: String {
        if let area { return "\(area.name) › \(name)" }
        return name
    }
}

// MARK: - Bin
@Model
final class Bin {
    /// Short human-readable tag printed on the box, e.g. "B7". Unique.
    @Attribute(.unique) var code: String
    var name: String
    var notes: String
    var colorName: String       // label colour for quick visual ID
    var createdAt: Date
    var location: StorageLocation?

    @Relationship(deleteRule: .cascade, inverse: \Item.bin)
    var items: [Item] = []

    @Relationship(deleteRule: .cascade, inverse: \AccessEvent.bin)
    var accessEvents: [AccessEvent] = []

    init(code: String, name: String, notes: String = "", colorName: String = "blue", location: StorageLocation? = nil) {
        self.code = code
        self.name = name
        self.notes = notes
        self.colorName = colorName
        self.location = location
        self.createdAt = .now
    }

    var locationPath: String { location?.fullPath ?? "No location set" }

    var sortedItems: [Item] {
        items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var totalItemCount: Int { items.reduce(0) { $0 + $1.quantity } }

    var totalAccessCount: Int { accessEvents.count }

    var lastAccessed: Date? { accessEvents.map(\.date).max() }

    func accessCount(sinceDaysAgo days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        return accessEvents.filter { $0.date >= cutoff }.count
    }

    var recentEvents: [AccessEvent] {
        accessEvents.sorted { $0.date > $1.date }
    }
}

// MARK: - Item
@Model
final class Item {
    var name: String
    var quantity: Int
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var bin: Bin?

    init(name: String, quantity: Int = 1, notes: String = "", bin: Bin? = nil) {
        self.name = name
        self.quantity = quantity
        self.notes = notes
        self.bin = bin
        self.createdAt = .now
        self.updatedAt = .now
    }
}

// MARK: - AccessEvent
/// One record each time a bin is opened in the app, marked as physically opened, or its contents changed.
@Model
final class AccessEvent {
    var date: Date
    var kindRaw: String
    var bin: Bin?

    init(kind: AccessKind, bin: Bin? = nil, date: Date = .now) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.bin = bin
    }

    var kind: AccessKind { AccessKind(rawValue: kindRaw) ?? .viewed }
}

enum AccessKind: String, CaseIterable, Codable {
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
