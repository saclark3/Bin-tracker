import Foundation
import SwiftData
import SwiftUI

// MARK: - Access logging
enum AccessLogger {
    /// GUESS: plain "viewed" events within this window of the last event are
    /// skipped, so flipping back and forth between screens doesn't inflate counts.
    static let viewDedupeWindow: TimeInterval = 10 * 60

    static func log(_ kind: AccessKind, for bin: Bin, in context: ModelContext) {
        if kind == .viewed, let last = bin.lastAccessed,
           Date.now.timeIntervalSince(last) < viewDedupeWindow {
            return
        }
        let event = AccessEvent(kind: kind)
        context.insert(event)
        bin.accessEvents.append(event)
    }
}

// MARK: - Bin codes
/// Codes are meant to be hand-written on boxes, so they stay short: B1, B2, B3…
/// GUESS: a single "B" prefix plus a number. Any short code can be typed instead
/// (e.g. "G4" for Garage), and lookups ignore case, spaces and dashes.
enum BinCode {
    static let prefix = "B"
    static let maxLength = 8

    /// Next free code in the form B1, B2, …
    static func next(in context: ModelContext) -> String {
        let bins = (try? context.fetch(FetchDescriptor<Bin>())) ?? []
        let used = Set(bins.map { normalize($0.code) })
        let numbers = bins.compactMap { code -> Int? in
            let c = normalize(code)
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

    static func isTaken(_ code: String, excluding bin: Bin? = nil, in context: ModelContext) -> Bool {
        let target = normalize(code)
        let bins = (try? context.fetch(FetchDescriptor<Bin>())) ?? []
        return bins.contains { normalize($0.code) == target && $0 !== bin }
    }

    static func find(_ raw: String, in context: ModelContext) -> Bin? {
        let bins = (try? context.fetch(FetchDescriptor<Bin>())) ?? []
        let exact = normalize(raw)
        let key = lookupKey(raw)
        return bins.first { normalize($0.code) == exact } ?? bins.first { normalize($0.code) == key }
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

// MARK: - Date formatting helper
extension Date {
    var relativeDescription: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: self, relativeTo: .now)
    }
}
