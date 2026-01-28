import Firebase




import UIKit
import Firebase
import FirebaseMessaging
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

        FirebaseApp.configure()

        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        // Permission to DISPLAY remote pushes (this app never schedules local notifications).
        NotificationService.shared.requestAuthorizationIfNeeded { granted in
            print("✅ Push display permission granted: \(granted)")
        }

        DispatchQueue.main.async {
            application.registerForRemoteNotifications()
        }

        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for APNs: \(error.localizedDescription)")
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken, !token.isEmpty else { return }

        // Cache locally; device doc is written once after sign-in.
        UserDefaults.standard.set(token, forKey: "cached_fcm_token")
        NotificationCenter.default.post(name: .fcmTokenDidUpdate, object: nil)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

extension Notification.Name {
    static let fcmTokenDidUpdate = Notification.Name("fcmTokenDidUpdate")
}


final class PushTokenCoordinator {

    private var lastToken: String?
    private var lastAuthUID: String?
    private var apnsError: Error?

    private let db = Firestore.firestore()

    func start() {
        // Track auth changes; whenever auth becomes available, attempt persistence
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.lastAuthUID = user?.uid
            if user != nil {
                self.fetchAndPersistToken(reason: "auth_state_changed")
            }
        }
    }

    @MainActor
    func bootstrapNotificationsAndToken(application: UIApplication) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        // Register even if user denied; APNs token can still exist in some flows,
        // but if denied, you should treat pushes as unavailable for UX.
        application.registerForRemoteNotifications()

        // Proactively fetch (covers cases where delegate callback doesn’t fire)
        fetchAndPersistToken(reason: "bootstrap")
    }

    func setAPNSError(_ error: Error) {
        apnsError = error
        // You can surface this in UI if desired; it’s a hard blocker for pushes.
    }

    func didReceiveFCMToken(_ token: String?) {
        guard let token, !token.isEmpty else {
            // Don’t accept empty; schedule a retry.
            scheduleRetry(reason: "didReceiveRegistrationToken_empty")
            return
        }
        lastToken = token
        persistTokenIfPossible(reason: "didReceiveRegistrationToken")
    }

    func fetchAndPersistToken(reason: String) {
        Messaging.messaging().token { [weak self] token, error in
            guard let self else { return }

            if let token, !token.isEmpty {
                self.lastToken = token
                self.persistTokenIfPossible(reason: "token() \(reason)")
            } else {
                self.scheduleRetry(reason: "token() nil \(reason) \(error?.localizedDescription ?? "")")
            }
        }
    }

    private func scheduleRetry(reason: String) {
        // Short bounded backoff — not “constant activity”
        // 0.5s, 1s, 2s, 4s, 8s (then stop)
        let delays: [TimeInterval] = [0.5, 1, 2, 4, 8]
        for (i, d) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in
                guard let self else { return }
                // Stop retrying if we already have a token
                if self.lastToken != nil { return }
                self.fetchAndPersistToken(reason: "retry\(i+1) \(reason)")
            }
        }
    }

    private func persistTokenIfPossible(reason: String) {
        guard let uid = lastAuthUID ?? Auth.auth().currentUser?.uid else {
            // Token exists but no auth yet; will persist on auth listener callback.
            return
        }
        guard let token = lastToken, !token.isEmpty else { return }

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"

        let ref = db.collection("users").document(uid).collection("devices").document(deviceId)
        ref.setData([
            "fcmToken": token,
            "fcmTokenUpdatedAt": Timestamp(date: Date()),
            "platform": "iOS",
            "reason": reason
        ], merge: true)
    }
}
