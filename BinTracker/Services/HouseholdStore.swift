import Foundation
import Observation
import FirebaseFirestore

/// Live copy of one household's data. Firestore keeps an offline cache on the
/// device, so changes show instantly and sync to everyone else's devices when online.
@Observable
@MainActor
final class HouseholdStore {
    let householdId: String
    let uid: String
    let userName: String

    private(set) var householdName = ""
    private(set) var inviteCode = ""
    private(set) var memberNames: [String] = []

    private(set) var areas: [Area] = []
    private(set) var spots: [Spot] = []
    private(set) var bins: [Bin] = []
    private(set) var items: [Item] = []
    private(set) var categories: [BinCategory] = []
    private(set) var events: [AccessEvent] = []
    private(set) var pickLists: [PickList] = []
    private(set) var lastError: String?

    /// GUESS: plain "viewed" events within this window of the last access are skipped,
    /// so flipping back and forth between screens doesn't inflate counts.
    static let viewDedupeWindow: TimeInterval = 10 * 60
    /// Access history kept in memory (counts beyond this come from the bin's running total).
    static let historyDays = 90

    @ObservationIgnored private let db = Firestore.firestore()
    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var watchSyncTask: Task<Void, Never>?

    init(householdId: String, uid: String, userName: String) {
        self.householdId = householdId
        self.uid = uid
        self.userName = userName
        start()
        WatchBridge.shared.householdDidStart(self)
    }

    private var root: DocumentReference { db.collection("households").document(householdId) }
    private func col(_ name: String) -> CollectionReference { root.collection(name) }

    // MARK: - Listening

    private func start() {
        listeners.append(root.addSnapshotListener { [weak self] snap, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error { self.lastError = error.localizedDescription; return }
                let d = snap?.data() ?? [:]
                self.householdName = d["name"] as? String ?? "Household"
                self.inviteCode = d["inviteCode"] as? String ?? ""
                let names = d["memberNames"] as? [String: String] ?? [:]
                self.memberNames = names.values.sorted()
                self.scheduleWatchSync()
            }
        })
        listen("areas") { [weak self] docs in
            self?.areas = docs.compactMap(Area.init).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        listen("spots") { [weak self] docs in
            self?.spots = docs.compactMap(Spot.init).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        listen("bins") { [weak self] docs in self?.bins = docs.compactMap(Bin.init) }
        listen("items") { [weak self] docs in
            self?.items = docs.compactMap(Item.init).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        listen("categories") { [weak self] docs in
            self?.categories = docs.compactMap(BinCategory.init).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        listen("pickLists") { [weak self] docs in
            self?.pickLists = docs.compactMap(PickList.init).sorted { $0.createdAt > $1.createdAt }
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.historyDays, to: .now) ?? .distantPast
        listen("events", query: col("events").whereField("date", isGreaterThan: cutoff)) { [weak self] docs in
            self?.events = docs.compactMap(AccessEvent.init).sorted { $0.date > $1.date }
        }
    }

    private func listen(_ name: String, query: Query? = nil,
                        _ apply: @escaping @MainActor ([QueryDocumentSnapshot]) -> Void) {
        let q: Query = query ?? col(name)
        listeners.append(q.addSnapshotListener { [weak self] snap, error in
            MainActor.assumeIsolated {
                if let error { self?.lastError = error.localizedDescription; return }
                apply(snap?.documents ?? [])
                if name != "events" { self?.scheduleWatchSync() }
            }
        })
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        watchSyncTask?.cancel()
        WatchBridge.shared.householdDidStop(self)
    }

    // MARK: - Apple Watch

    /// Sends the watch a fresh copy shortly after changes settle (snapshots arrive in bursts).
    private func scheduleWatchSync() {
        watchSyncTask?.cancel()
        watchSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            WatchBridge.shared.publish(self.watchSnapshot())
        }
    }

    /// What the watch needs: every bin with its items, and every pick list in walking order.
    func watchSnapshot() -> WatchSnapshot {
        let watchBins = bins
            .sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }
            .map { bin in
                WatchBin(id: bin.id, code: bin.code, name: bin.name, colorName: bin.colorName,
                         location: locationPath(of: bin), lastAccessed: bin.lastAccessed,
                         items: items(in: bin).map { WatchItem(id: $0.id, name: $0.name, quantity: $0.quantity) })
            }
        let lists = pickLists.map { list in
            WatchPickList(id: list.id, name: list.name, createdAt: list.createdAt,
                          entries: bins(in: list).map { bin in
                              WatchPickEntry(binId: bin.id, code: bin.code, name: bin.name, colorName: bin.colorName,
                                             location: locationPath(of: bin), picked: list.isPicked(bin),
                                             items: chosenItems(in: list, bin: bin).map {
                                                 WatchPickItem(id: $0.id, name: $0.name, quantity: $0.quantity,
                                                               picked: list.isPicked($0))
                                             })
                          })
        }
        return WatchSnapshot(householdName: householdName.isEmpty ? "Household" : householdName,
                             generatedAt: .now, bins: watchBins, pickLists: lists,
                             appliedCommandIds: WatchBridge.shared.appliedCommandIds)
    }

    nonisolated private func report(_ error: Error?) {
        guard let error else { return }
        let message = error.localizedDescription
        Task { @MainActor in self.lastError = message }
    }

    func clearError() { lastError = nil }

    // MARK: - Lookups

    func area(_ id: String?) -> Area? { areas.first { $0.id == id } }
    func spot(_ id: String?) -> Spot? { spots.first { $0.id == id } }
    func bin(_ id: String?) -> Bin? { bins.first { $0.id == id } }

    func spots(in area: Area) -> [Spot] { spots.filter { $0.areaId == area.id } }
    func bins(at spot: Spot) -> [Bin] {
        bins.filter { $0.spotId == spot.id }.sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }
    }
    func binCount(in area: Area) -> Int {
        let ids = Set(spots(in: area).map(\.id))
        return bins.filter { ids.contains($0.spotId ?? "") }.count
    }
    var unplacedBins: [Bin] { bins.filter { spot($0.spotId) == nil } }

    func category(_ id: String?) -> BinCategory? { categories.first { $0.id == id } }
    /// The bin's categories in alphabetical order (ids of deleted categories are skipped).
    func categories(of bin: Bin) -> [BinCategory] {
        let ids = Set(bin.categoryIds)
        return categories.filter { ids.contains($0.id) }
    }
    func bins(in category: BinCategory) -> [Bin] {
        bins.filter { $0.categoryIds.contains(category.id) }
            .sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }
    }
    func categoryNameTaken(_ name: String, excluding id: String? = nil) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return categories.contains { $0.id != id && $0.name.compare(n, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    func items(in bin: Bin) -> [Item] { items.filter { $0.binId == bin.id } }
    func events(for bin: Bin) -> [AccessEvent] { events.filter { $0.binId == bin.id } }

    func pickList(_ id: String?) -> PickList? { pickLists.first { $0.id == id } }

    /// Bins on the list (plus the current bin of any chosen item that has since moved),
    /// sorted by location so the list reads in the order you'd walk to them.
    func bins(in list: PickList) -> [Bin] {
        var ids = list.binIds
        for item in items where list.itemIds.contains(item.id) && !ids.contains(item.binId) { ids.append(item.binId) }
        return ids.compactMap { bin($0) }.sorted {
            let a = locationPath(of: $0), b = locationPath(of: $1)
            if a != b {
                // Bins without a location go last.
                if spot($0.spotId) == nil { return false }
                if spot($1.spotId) == nil { return true }
                return a.localizedStandardCompare(b) == .orderedAscending
            }
            return $0.code.localizedStandardCompare($1.code) == .orderedAscending
        }
    }

    /// Specific items to pull from this bin (empty means "grab the whole bin").
    func chosenItems(in list: PickList, bin: Bin) -> [Item] {
        items.filter { $0.binId == bin.id && list.itemIds.contains($0.id) }
    }

    /// (checked off, total). Each bin counts once and each chosen item counts once.
    func progress(of list: PickList) -> (done: Int, total: Int) {
        var done = 0, total = 0
        for bin in bins(in: list) {
            total += 1; if list.isPicked(bin) { done += 1 }
            for item in chosenItems(in: list, bin: bin) { total += 1; if list.isPicked(item) { done += 1 } }
        }
        return (done, total)
    }

    func pickLists(containing bin: Bin) -> [PickList] { pickLists.filter { bins(in: $0).contains(bin) } }

    func accessCount(_ bin: Bin, days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        return events.filter { $0.binId == bin.id && $0.date >= cutoff }.count
    }

    /// "Garage › Shelf 2"
    func path(of spot: Spot) -> String {
        if let area = area(spot.areaId) { return "\(area.name) › \(spot.name)" }
        return spot.name
    }
    func locationPath(of bin: Bin) -> String {
        spot(bin.spotId).map(path(of:)) ?? "No location set"
    }

    func find(code raw: String) -> Bin? {
        let exact = BinCode.normalize(raw)
        let key = BinCode.lookupKey(raw)
        return bins.first { BinCode.normalize($0.code) == exact } ?? bins.first { BinCode.normalize($0.code) == key }
    }

    func isTaken(_ code: String, excluding binId: String?) -> Bool {
        let target = BinCode.normalize(code)
        return bins.contains { BinCode.normalize($0.code) == target && $0.id != binId }
    }

    var nextCode: String { BinCode.next(after: bins) }

    // MARK: - Areas & spots

    func addArea(_ name: String) {
        col("areas").addDocument(data: Area(id: "", name: name, symbol: AreaSymbol.guess(for: name)).data, completion: report)
    }

    func renameArea(_ area: Area, to name: String) {
        col("areas").document(area.id).updateData(["name": name], completion: report)
    }

    /// Deletes the area and its spots. Bins in those spots are kept, with no location.
    func deleteArea(_ area: Area) {
        let batch = db.batch()
        for spot in spots(in: area) { unplaceBins(at: spot, batch: batch); batch.deleteDocument(col("spots").document(spot.id)) }
        batch.deleteDocument(col("areas").document(area.id))
        batch.commit(completion: report)
    }

    func addSpot(_ name: String, in area: Area) {
        col("spots").addDocument(data: Spot(id: "", areaId: area.id, name: name).data, completion: report)
    }

    func deleteSpot(_ spot: Spot) {
        let batch = db.batch()
        unplaceBins(at: spot, batch: batch)
        batch.deleteDocument(col("spots").document(spot.id))
        batch.commit(completion: report)
    }

    private func unplaceBins(at spot: Spot, batch: WriteBatch) {
        for bin in bins where bin.spotId == spot.id {
            batch.updateData(["spotId": NSNull()], forDocument: col("bins").document(bin.id))
        }
    }

    // MARK: - Categories

    /// Creates a category and returns its ID (usable right away, even offline).
    /// If one with the same name exists, returns that one instead.
    @discardableResult
    func addCategory(_ name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = categories.first(where: { $0.name.compare(n, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return existing.id
        }
        let colours = BinColor.allCases
        let colour = colours[categories.count % colours.count].rawValue
        let ref = col("categories").document()
        ref.setData(BinCategory(id: ref.documentID, name: n, colorName: colour).data, completion: report)
        return ref.documentID
    }

    func updateCategory(_ category: BinCategory) {
        col("categories").document(category.id)
            .updateData(["name": category.name, "colorName": category.colorName], completion: report)
    }

    /// Deletes the category and takes it off every bin. The bins themselves are kept.
    func deleteCategory(_ category: BinCategory) {
        let batch = db.batch()
        for bin in bins where bin.categoryIds.contains(category.id) {
            batch.updateData(["categoryIds": FieldValue.arrayRemove([category.id])],
                             forDocument: col("bins").document(bin.id))
        }
        batch.deleteDocument(col("categories").document(category.id))
        batch.commit(completion: report)
    }

    /// Adds or removes one bin from a category without touching its other fields.
    func setBin(_ bin: Bin, in category: BinCategory, _ included: Bool) {
        let value: FieldValue = included ? FieldValue.arrayUnion([category.id]) : FieldValue.arrayRemove([category.id])
        col("bins").document(bin.id).updateData(["categoryIds": value], completion: report)
    }

    // MARK: - Bins

    /// Creates a new bin and returns its ID.
    @discardableResult
    func createBin(_ bin: Bin) -> String {
        let ref = col("bins").document()
        var data = bin.editableData
        data["accessCount"] = 0
        ref.setData(data, completion: report)
        return ref.documentID
    }

    func updateBin(_ bin: Bin) {
        col("bins").document(bin.id).updateData(bin.editableData, completion: report)
    }

    /// Deletes the bin with its items. Its access history is left (it ages out of view).
    func deleteBin(_ bin: Bin) {
        let batch = db.batch()
        for item in items(in: bin) { batch.deleteDocument(col("items").document(item.id)) }
        batch.deleteDocument(col("bins").document(bin.id))
        batch.commit(completion: report)
    }

    // MARK: - Items

    func addItem(named name: String, to bin: Bin) {
        col("items").addDocument(data: Item(id: "", binId: bin.id, name: name).data, completion: report)
        logAccess(.edited, for: bin)
    }

    func updateItem(_ item: Item, previousBinId: String) {
        var updated = item
        updated.updatedAt = .now
        col("items").document(item.id).setData(updated.data, completion: report)
        if let old = bin(previousBinId) { logAccess(.edited, for: old) }
        if previousBinId != item.binId, let new = bin(item.binId) { logAccess(.edited, for: new) }
    }

    func deleteItem(_ item: Item) {
        col("items").document(item.id).delete(completion: report)
        if let b = bin(item.binId) { logAccess(.edited, for: b) }
    }

    // MARK: - Pick lists

    /// Creates a pick list and returns its ID.
    @discardableResult
    func createPickList(name: String, binIds: [String], itemIds: [String]) -> String {
        let ref = col("pickLists").document()
        let list = PickList(id: ref.documentID, name: name, createdBy: userName, binIds: binIds, itemIds: itemIds)
        ref.setData(list.data, completion: report)
        return ref.documentID
    }

    /// Saves the name and contents. Check-offs for bins and items no longer on the list are dropped.
    func updatePickList(_ list: PickList, name: String, binIds: [String], itemIds: [String]) {
        var update: [String: Any] = ["name": name, "binIds": binIds, "itemIds": itemIds]
        let removedBins = list.pickedBinIds.filter { !binIds.contains($0) }
        let removedItems = list.pickedItemIds.filter { !itemIds.contains($0) }
        if !removedBins.isEmpty { update["pickedBinIds"] = FieldValue.arrayRemove(removedBins) }
        if !removedItems.isEmpty { update["pickedItemIds"] = FieldValue.arrayRemove(removedItems) }
        col("pickLists").document(list.id).updateData(update, completion: report)
    }

    func deletePickList(_ list: PickList) {
        col("pickLists").document(list.id).delete(completion: report)
    }

    /// Unchecks everything so the list can be used again.
    func resetPickList(_ list: PickList) {
        col("pickLists").document(list.id).updateData(["pickedBinIds": [String](), "pickedItemIds": [String]()], completion: report)
    }

    func add(_ bin: Bin, to list: PickList) {
        col("pickLists").document(list.id).updateData(["binIds": FieldValue.arrayUnion([bin.id])], completion: report)
    }

    /// Adds one item (and its bin) to a list.
    func add(_ item: Item, to list: PickList) {
        col("pickLists").document(list.id).updateData(["binIds": FieldValue.arrayUnion([item.binId]),
                                                       "itemIds": FieldValue.arrayUnion([item.id])],
                                                      completion: report)
    }

    func setPicked(_ bin: Bin, in list: PickList, _ picked: Bool) {
        HouseholdWrites.setBinPicked(listId: list.id, binId: bin.id, picked: picked, root: root, completion: report)
        if picked && !anythingPicked(from: bin, in: list) { logAccess(.opened, for: bin) }
    }

    func setPicked(_ item: Item, in list: PickList, _ picked: Bool) {
        HouseholdWrites.setItemPicked(listId: list.id, itemId: item.id, picked: picked, root: root, completion: report)
        if picked, let bin = bin(item.binId), !anythingPicked(from: bin, in: list) { logAccess(.opened, for: bin) }
    }

    /// True once the bin or any of its chosen items has been checked off (so it was already opened).
    private func anythingPicked(from bin: Bin, in list: PickList) -> Bool {
        list.isPicked(bin) || chosenItems(in: list, bin: bin).contains(where: list.isPicked)
    }

    // MARK: - Access tracking

    func logAccess(_ kind: AccessKind, for bin: Bin) {
        let current = self.bin(bin.id) ?? bin
        if kind == .viewed, let last = current.lastAccessed,
           Date.now.timeIntervalSince(last) < Self.viewDedupeWindow {
            return
        }
        HouseholdWrites.logAccess(kind, binId: bin.id, by: userName, root: root, completion: report)
    }
}
