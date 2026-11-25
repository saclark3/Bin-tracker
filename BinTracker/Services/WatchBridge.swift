import Foundation
import UIKit
import WatchConnectivity
import FirebaseCore
import FirebaseFirestore

/// The iPhone side of the Apple Watch link.
///
/// - Sends the watch a snapshot of bins, items and pick lists whenever they change, so the watch
///   has its own copy to use away from the phone.
/// - Receives check-offs and quick adds made on the watch and writes them to Firestore. iOS can wake
///   the app in the background for this, before anyone has opened it, so commands are written with
///   `HouseholdWrites` using the household saved here rather than the live store.
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private enum Key {
        static let householdId = "watch.householdId"
        static let userName = "watch.userName"
        static let applied = "watch.appliedCommandIds"
        static let waiting = "watch.waitingCommands"
    }

    /// Larger snapshots go as a file transfer (application context has a size limit).
    private static let contextLimit = 48_000
    private static let appliedKept = 300

    private let defaults = UserDefaults.standard
    private weak var store: HouseholdStore?
    private var lastPublished: WatchSnapshot?
    private var latestPayload: Data?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    /// Call once at launch, so commands that arrive while the app is in the background are received.
    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Household lifecycle (called by HouseholdStore)

    func householdDidStart(_ store: HouseholdStore) {
        self.store = store
        defaults.set(store.householdId, forKey: Key.householdId)
        defaults.set(store.userName, forKey: Key.userName)
        // Commands that arrived before we knew the household.
        let waiting = waitingCommands
        defaults.removeObject(forKey: Key.waiting)
        waiting.forEach { _ = handle($0) }
    }

    func householdDidStop(_ store: HouseholdStore) {
        guard self.store === store else { return }
        self.store = nil
        defaults.removeObject(forKey: Key.householdId)
        var signedOut = WatchSnapshot.empty
        signedOut.generatedAt = .now
        publish(signedOut)   // the watch shows "open Bins on your iPhone"
    }

    // MARK: - Sending snapshots

    var appliedCommandIds: [String] { defaults.stringArray(forKey: Key.applied) ?? [] }

    func publish(_ snapshot: WatchSnapshot) {
        var comparable = snapshot
        comparable.generatedAt = lastPublished?.generatedAt ?? snapshot.generatedAt
        if comparable == lastPublished { return }
        lastPublished = snapshot
        guard let data = try? WatchCoding.encode(snapshot, compress: true) else { return }
        latestPayload = data
        send(data)
    }

    private func send(_ data: Data) {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        if data.count <= Self.contextLimit,
           (try? session.updateApplicationContext([WatchKeys.snapshot: data])) != nil {
            return
        }
        // Too big for the application context: send a file instead, replacing any older one still queued.
        session.outstandingFileTransfers
            .filter { $0.file.metadata?[WatchKeys.snapshot] != nil }
            .forEach { $0.cancel() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-snapshot-\(UUID().uuidString).bin")
        do {
            try data.write(to: url)
            session.transferFile(url, metadata: [WatchKeys.snapshot: true])
        } catch {}
    }

    // MARK: - Receiving commands

    /// Writes one watch command to Firestore. Returns false if it has to wait for a household.
    @discardableResult
    private func handle(_ command: WatchCommand) -> Bool {
        var applied = appliedCommandIds
        if applied.contains(command.id) { return true }   // delivered twice (message + transfer)
        guard FirebaseApp.app() != nil, let hid = defaults.string(forKey: Key.householdId) else {
            var waiting = waitingCommands
            waiting.append(command)
            saveWaiting(waiting)
            return false
        }
        let root = Firestore.firestore().collection("households").document(hid)
        let userName = defaults.string(forKey: Key.userName) ?? ""
        let report: HouseholdWrites.Completion = { error in
            if let error { print("Watch command failed: \(error.localizedDescription)") }
        }

        switch command.action {
        case let .setBinPicked(listId, binId, picked, logOpened):
            HouseholdWrites.setBinPicked(listId: listId, binId: binId, picked: picked, root: root, completion: report)
            if logOpened { HouseholdWrites.logAccess(.opened, binId: binId, by: userName, root: root, completion: report) }
        case let .setItemPicked(listId, itemId, binId, picked, logOpened):
            HouseholdWrites.setItemPicked(listId: listId, itemId: itemId, picked: picked, root: root, completion: report)
            if logOpened { HouseholdWrites.logAccess(.opened, binId: binId, by: userName, root: root, completion: report) }
        case let .addItem(binId, name, itemId):
            HouseholdWrites.addItem(id: itemId, named: name, binId: binId, root: root, completion: report)
            HouseholdWrites.logAccess(.edited, binId: binId, by: userName, root: root, completion: report)
        }

        applied.append(command.id)
        defaults.set(Array(applied.suffix(Self.appliedKept)), forKey: Key.applied)
        keepRunningBriefly()
        return true
    }

    /// If iOS woke the app in the background, ask for a little time so Firestore can upload the change.
    private func keepRunningBriefly() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Watch sync") { [weak self] in
            self?.endBackgroundTask()
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private var waitingCommands: [WatchCommand] {
        guard let data = defaults.data(forKey: Key.waiting) else { return [] }
        return (try? WatchCoding.decode([WatchCommand].self, from: data)) ?? []
    }

    private func saveWaiting(_ commands: [WatchCommand]) {
        defaults.set(try? WatchCoding.encode(Array(commands.suffix(200))), forKey: Key.waiting)
    }

    // MARK: - WCSessionDelegate (called on a background queue)

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let data = self.latestPayload { self.send(data) }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched to another watch.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            if let data = self.latestPayload { self.send(data) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let command = (message[WatchKeys.command] as? Data).flatMap { try? WatchCoding.decode(WatchCommand.self, from: $0) }
        let wantsSnapshot = message[WatchKeys.requestSnapshot] != nil
        let reply = UncheckedBox(replyHandler)
        Task { @MainActor in
            var response: [String: Any] = [:]
            if let command, self.handle(command) {
                response[WatchKeys.ack] = [command.id]
            }
            if wantsSnapshot {
                if let store = self.store { self.publish(store.watchSnapshot()) }
                if let data = self.latestPayload, data.count <= Self.contextLimit {
                    response[WatchKeys.snapshot] = data
                } else if let data = self.latestPayload {
                    self.send(data)
                }
            }
            reply.value(response)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchKeys.command] as? Data,
              let command = try? WatchCoding.decode(WatchCommand.self, from: data) else { return }
        Task { @MainActor in self.handle(command) }
    }
}

/// Carries a non-Sendable value (WatchConnectivity's reply handler) onto the main actor.
private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
