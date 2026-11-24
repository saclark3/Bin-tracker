import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

/// Tracks who is signed in and which household they belong to.
///
/// Firestore layout:
///   users/{uid}                 { name, householdId }
///   households/{hid}            { name, members: [uid], memberNames: {uid: name}, inviteCode }
///   households/{hid}/areas|spots|bins|items|events/{id}
///   invites/{code}              { householdId }
@Observable
@MainActor
final class AppSession {
    enum Phase {
        case loading
        case signedOut
        case needsHousehold
        case ready(HouseholdStore)
    }

    private(set) var phase: Phase = .loading
    private(set) var userName = ""

    @ObservationIgnored private let db = Firestore.firestore()
    @ObservationIgnored private var authHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var userListener: ListenerRegistration?

    init() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            MainActor.assumeIsolated { self?.authChanged(user) }
        }
    }

    var uid: String? { Auth.auth().currentUser?.uid }

    private func authChanged(_ user: User?) {
        userListener?.remove()
        userListener = nil
        if case .ready(let store) = phase { store.stop() }
        guard let user else { phase = .signedOut; return }
        phase = .loading
        userName = user.displayName ?? user.email ?? "Me"
        userListener = db.collection("users").document(user.uid).addSnapshotListener { [weak self] snap, _ in
            MainActor.assumeIsolated { self?.userDocChanged(snap, uid: user.uid) }
        }
    }

    private func userDocChanged(_ snap: DocumentSnapshot?, uid: String) {
        let data = snap?.data() ?? [:]
        if let name = data["name"] as? String, !name.isEmpty { userName = name }
        guard let hid = data["householdId"] as? String, !hid.isEmpty else {
            if case .ready(let store) = phase { store.stop() }
            phase = .needsHousehold
            return
        }
        if case .ready(let store) = phase {
            if store.householdId == hid { return }
            store.stop()
        }
        phase = .ready(HouseholdStore(householdId: hid, uid: uid, userName: userName))
    }

    // MARK: - Account

    func signIn(email: String, password: String) async throws {
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func createAccount(name: String, email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let change = result.user.createProfileChangeRequest()
        change.displayName = name
        try? await change.commitChanges()
        userName = name
        try await db.collection("users").document(result.user.uid).setData(["name": name], merge: true)
    }

    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func signOut() {
        try? Auth.auth().signOut()
    }

    // MARK: - Household

    func createHousehold(name: String) async throws {
        guard let uid else { return }
        let household = db.collection("households").document()
        let code = Self.makeInviteCode()
        let batch = db.batch()
        batch.setData([
            "name": name,
            "members": [uid],
            "memberNames": [uid: userName],
            "inviteCode": code,
            "createdAt": Date.now,
        ], forDocument: household)
        batch.setData(["householdId": household.documentID], forDocument: db.collection("invites").document(code))
        batch.setData(["householdId": household.documentID, "name": userName],
                      forDocument: db.collection("users").document(uid), merge: true)
        try await batch.commit()
    }

    enum JoinError: LocalizedError {
        case notFound
        var errorDescription: String? { "No household uses that invite code. Check it and try again." }
    }

    func joinHousehold(code raw: String) async throws {
        guard let uid else { return }
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        let invite = try await db.collection("invites").document(code).getDocument()
        guard let hid = invite.data()?["householdId"] as? String else { throw JoinError.notFound }
        try await db.collection("households").document(hid).updateData([
            "members": FieldValue.arrayUnion([uid]),
            "memberNames.\(uid)": userName,
            "joinCode": code,
        ])
        try await db.collection("users").document(uid)
            .setData(["householdId": hid, "name": userName], merge: true)
    }

    func leaveHousehold() async throws {
        guard let uid, case .ready(let store) = phase else { return }
        try await db.collection("households").document(store.householdId).updateData([
            "members": FieldValue.arrayRemove([uid]),
            "memberNames.\(uid)": FieldValue.delete(),
        ])
        try await db.collection("users").document(uid).updateData(["householdId": FieldValue.delete()])
    }

    /// 6 characters without look-alikes (no 0/O, 1/I/L) so it's easy to read out loud.
    static func makeInviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}
