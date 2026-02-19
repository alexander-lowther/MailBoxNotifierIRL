
import UIKit
import Firebase
import FirebaseMessaging
import UserNotifications
import FirebaseAuth

final class AppDelegate: NSObject,
                         UIApplicationDelegate,
                         UNUserNotificationCenterDelegate,
                         MessagingDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        FirebaseApp.configure()

        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        // Permission to DISPLAY remote pushes (not local notifications)
        NotificationService.shared.requestAuthorizationIfNeeded { granted in
            print("✅ Push display permission granted: \(granted)")
        }

        DispatchQueue.main.async {
            application.registerForRemoteNotifications()
        }

        return true
    }

    // APNs → Firebase bridge
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for APNs: \(error.localizedDescription)")
    }

    // 🔑 FCM token lifecycle (THIS IS THE ONLY PLACE)
    func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken fcmToken: String?
    ) {
        guard let token = fcmToken else { return }

        guard let uid = Auth.auth().currentUser?.uid else {
            UserDefaults.standard.set(token, forKey: "pendingFCMToken")
            return
        }

        let deviceID = DeviceIdentity.id()

        upsertDeviceFCMToken(
            uid: uid,
            deviceID: deviceID,
            token: token
        )
    }

    // Foreground notification display
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
import Foundation
import FirebaseFirestore

func upsertDeviceFCMToken(uid: String, deviceID: String, token: String) {
  //  Logger.insertLog("supsertDeviceTk", "started", Date())
    let trimmedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedDeviceID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedUID.isEmpty, !trimmedDeviceID.isEmpty, !trimmedToken.isEmpty else { return }

    // Always ensure baseline exists (prevents token-only docs permanently)
    upsertDeviceBaseline(uid: trimmedUID, deviceID: trimmedDeviceID)

    Firestore.firestore()
        .collection("users")
        .document(trimmedUID)
        .collection("devices")
        .document(trimmedDeviceID)
        .setData([
            "fcmToken": trimmedToken,
            "fcmTokenUpdatedAt": FieldValue.serverTimestamp(),
            "updatedBy": "upsertDeviceFCMTok"
        ], merge: true)
    
  //  Logger.insertLog("supsertDeviceTk", "exit", Date())
}
