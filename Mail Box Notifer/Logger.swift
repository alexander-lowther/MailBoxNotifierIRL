
import Foundation
import FirebaseAuth
import FirebaseFirestore

enum Logger {

    private static let db = Firestore.firestore()

    /// Inserts a log entry into the top-level `logs` collection.
    ///
    /// - Parameters:
    ///   - event: Short event name (e.g. "device_upsert")
    ///   - keyInfo: Free-form info or identifier
    ///   - clientTime: Local time on device (for debugging / correlation)
    static func insertLog(
        _ event: String,
        _ keyInfo: String,
        _ clientTime: Date
    ) {
        var data: [String: Any] = [
            "event": event,
            "keyInfo": keyInfo,
            "updatedAt": FieldValue.serverTimestamp(),
            "clientTime": Timestamp(date: clientTime)
        ]

        if let uid = Auth.auth().currentUser?.uid {
            data["updatedBy"] = uid
        }

        db.collection("logs").addDocument(data: data)
    }
}
