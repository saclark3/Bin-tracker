import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// The watch's own copy of the household, saved on the watch so it works away from the iPhone.
/// Check-offs are applied here immediately and queued until the phone has written them.
@Observable
@MainActor
final class WatchStore {
    private(set) var snapshot: WatchSnapshot = .empty
    /// Changes made on the watch that the phone hasn't confirmed yet.
    private(set) var pending: [WatchCommand] = []
    private(set) var phoneReachable = false

    @ObservationIgnored private let link = WatchLink()

    private static var folder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private static let snapshotURL = folder.appendingPathComponent("snapshot.json")
    private static let pendingURL = folder.appendingPathComponent("pending.json")

    init() {
        if let data = try? Data(contentsOf: Self.snapshotURL),
           let saved = try? WatchCoding.decode(WatchSnapshot.self, from: data) {
            snapshot = saved
        }
        if let data = try? Data(contentsOf: Self.pendingURL),
           let saved = try? WatchCoding.decode([WatchCommand].self, from: data) {
            pending = saved
        }
        link.store = self
        link.activate()
    }

    // MARK: - Lookups

    var recentBins: [WatchBin] {
        snapshot.bins.sorted { ($0.lastAccessed ?? .distantPast) > ($1.lastAccessed ?? .distantPast) }
    }

    func search(_ raw: String) -> [WatchBin] {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return snapshot.bins }
        var results = snapshot.bins.filter {
            $0.code.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q)
                || $0.items.contains { $0.name.localizedCaseInsensitiveContains(q) }
        }
        if let exact = snapshot.find(code: q) {
            results.removeAll { $0.id == exact.id }
            results.insert(exact, at: 0)
        }
        return results
    }

    // MARK: - Actions

    func toggle(_ entry: WatchPickEntry, in list: WatchPickList) {
        let picked = !entry.picked
        let firstForBin = picked && !entry.items.contains(where: \.picked)
        run(.setBinPicked(listId: list.id, binId: entry.binId, picked: picked, logOpened: firstForBin))
    }

    func toggle(_ item: WatchPickItem, of entry: WatchPickEntry, in list: WatchPickList) {
        let picked = !item.picked
        let firstForBin = picked && !entry.picked && !entry.items.contains(where: \.picked)
        run(.setItemPicked(listId: list.id, itemId: item.id, binId: entry.binId, picked: picked, logOpened: firstForBin))
    }

    func addItem(named raw: String, to bin: WatchBin) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        run(.addItem(binId: bin.id, name: name, itemId: UUID().uuidString))
    }

    private func run(_ action: WatchCommand.Action) {
        let command = WatchCommand(action: action)
        snapshot.apply(command)
        pending.append(command)
        save()
        WKInterfaceDevice.current().play(.click)
        link.send(command)
    }

    // MARK: - From the phone

    func received(_ incoming: WatchSnapshot) {
        // Context updates and file transfers can arrive out of order; keep the newest.
        guard incoming.generatedAt >= snapshot.generatedAt else { return }
        var next = incoming
        let applied = Set(incoming.appliedCommandIds)
        pending.removeAll { applied.contains($0.id) }
        // Keep showing watch changes the phone hasn't written yet.
        for command in pending { next.apply(command) }
        snapshot = next
        save()
    }

    func acknowledged(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        pending.removeAll { ids.contains($0.id) }
        save()
    }

    func reachabilityChanged(_ reachable: Bool) {
        phoneReachable = reachable
        if reachable { link.requestSnapshot() }
    }

    /// Re-queues changes WatchConnectivity no longer has (e.g. made before the link was ready).
    func linkActivated(outstanding: Set<String>) {
        for command in pending where !outstanding.contains(command.id) { link.send(command) }
        link.requestSnapshot()
    }

    private func save() {
        if let data = try? WatchCoding.encode(snapshot) { try? data.write(to: Self.snapshotURL, options: .atomic) }
        if let data = try? WatchCoding.encode(pending) { try? data.write(to: Self.pendingURL, options: .atomic) }
    }
}

/// WatchConnectivity plumbing. Its callbacks arrive on a background queue.
final class WatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    @MainActor weak var store: WatchStore?

    private var session: WCSession { WCSession.default }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func send(_ command: WatchCommand) {
        guard session.activationState == .activated,
              let data = try? WatchCoding.encode(command) else { return }   // re-sent on activation
        let message = [WatchKeys.command: data]
        if session.isReachable {
            // Immediate path; also wakes the iPhone app. Falls back to the queued path on failure.
            session.sendMessage(message, replyHandler: { [weak self] reply in
                self?.handleReply(reply)
            }, errorHandler: { [weak self] _ in
                self?.session.transferUserInfo(message)
            })
        } else {
            // Queued by watchOS and delivered when the phone is back in range, even if this app is closed.
            session.transferUserInfo(message)
        }
    }

    func requestSnapshot() {
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([WatchKeys.requestSnapshot: true], replyHandler: { [weak self] reply in
            self?.handleReply(reply)
        }, errorHandler: nil)
    }

    private func handleReply(_ reply: [String: Any]) {
        let ids = reply[WatchKeys.ack] as? [String] ?? []
        let snapshot = (reply[WatchKeys.snapshot] as? Data).flatMap(Self.decodeSnapshot)
        Task { @MainActor in
            self.store?.acknowledged(ids)
            if let snapshot { self.store?.received(snapshot) }
        }
    }

    private static func decodeSnapshot(_ data: Data) -> WatchSnapshot? {
        try? WatchCoding.decode(WatchSnapshot.self, from: data, compressed: true)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        let outstanding = Set(session.outstandingUserInfoTransfers.compactMap { transfer -> String? in
            guard let data = transfer.userInfo[WatchKeys.command] as? Data else { return nil }
            return (try? WatchCoding.decode(WatchCommand.self, from: data))?.id
        })
        let context = (session.receivedApplicationContext[WatchKeys.snapshot] as? Data).flatMap(Self.decodeSnapshot)
        let reachable = session.isReachable
        Task { @MainActor in
            if let context, context.generatedAt > (self.store?.snapshot.generatedAt ?? .distantPast) {
                self.store?.received(context)
            }
            self.store?.reachabilityChanged(reachable)
            self.store?.linkActivated(outstanding: outstanding)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.store?.reachabilityChanged(reachable) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snapshot = (applicationContext[WatchKeys.snapshot] as? Data).flatMap(Self.decodeSnapshot) else { return }
        Task { @MainActor in self.store?.received(snapshot) }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is deleted when this returns, so read it now.
        guard let data = try? Data(contentsOf: file.fileURL),
              let snapshot = Self.decodeSnapshot(data) else { return }
        Task { @MainActor in self.store?.received(snapshot) }
    }
}
