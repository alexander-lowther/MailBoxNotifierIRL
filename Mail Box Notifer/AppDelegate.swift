// AppDelegate.swift
import UIKit
import Firebase
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()

        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
            } else {
                print("✅ Notification permission granted: \(granted)")
            }
        }

        DispatchQueue.main.async {
            application.registerForRemoteNotifications()
        }

        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { String(format: "%02.2hhx", $0) }
        let token = tokenParts.joined()
        print("📦 APNs token received: \(token)")
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for APNs: \(error.localizedDescription)")
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else {
            print("❌ FCM token is nil")
            return
        }
        print("🔥 FCM Token received: \(token)")

        guard let userID = Auth.auth().currentUser?.uid else {
            print("⚠️ User not signed in, skipping token upload")
            return
        }

        let db = Firestore.firestore()
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let deviceRef = db.collection("users").document(userID).collection("devices").document(deviceID)

        deviceRef.setData([
            "token": token,
            "isActive": true,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true) { error in
            if let error = error {
                print("❌ Failed to register device token in Firestore: \(error.localizedDescription)")
            } else {
                print("✅ Token saved to Firestore for user \(userID), device \(deviceID)")
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("🔔 Foreground push received: \(notification.request.content.body)")
        completionHandler([.banner, .list, .sound])
    }
}
