import Foundation
import FirebaseFirestore

/// Firestore writes that need only the household's document reference, not the live store.
/// Shared by `HouseholdStore` and by `WatchBridge`, which applies check-offs from the
/// Apple Watch even when the iPhone app was woken in the background and has no store yet.
enum HouseholdWrites {
    typealias Completion = ((Error?) -> Void)?

    /// Records that a bin was physically opened (counts toward its usage stats).
    static func logAccess(_ kind: AccessKind, binId: String, by userName: String,
                          root: DocumentReference, completion: Completion = nil) {
        let now = Date.now
        let batch = root.firestore.batch()
        batch.setData(["binId": binId, "kind": kind.rawValue, "date": now, "by": userName],
                      forDocument: root.collection("events").document())
        batch.updateData(["lastAccessed": now, "accessCount": FieldValue.increment(Int64(1))],
                         forDocument: root.collection("bins").document(binId))
        batch.commit(completion: completion)
    }

    static func setBinPicked(listId: String, binId: String, picked: Bool,
                             root: DocumentReference, completion: Completion = nil) {
        let value = picked ? FieldValue.arrayUnion([binId]) : FieldValue.arrayRemove([binId])
        root.collection("pickLists").document(listId).updateData(["pickedBinIds": value], completion: completion)
    }

    static func setItemPicked(listId: String, itemId: String, picked: Bool,
                              root: DocumentReference, completion: Completion = nil) {
        let value = picked ? FieldValue.arrayUnion([itemId]) : FieldValue.arrayRemove([itemId])
        root.collection("pickLists").document(listId).updateData(["pickedItemIds": value], completion: completion)
    }

    /// Adds an item to a bin. `id` lets the watch pick the document ID up front, so a retried
    /// message can't create the item twice.
    static func addItem(id: String? = nil, named name: String, binId: String,
                        root: DocumentReference, completion: Completion = nil) {
        let ref = id.map { root.collection("items").document($0) } ?? root.collection("items").document()
        ref.setData(Item(id: ref.documentID, binId: binId, name: name).data, completion: completion)
    }
}
