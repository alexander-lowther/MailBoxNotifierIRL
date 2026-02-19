
//
//  NotificationService.swift
//  Mail Box Notifer
//
//  Push only. This app never schedules local notifications.
//  Uses a Firebase Callable Cloud Function to send push notifications to user devices.
//

import Foundation
import UserNotifications
import FirebaseAuth
import FirebaseFunctions

final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    // MARK: - Config

    /// Cloud Function name (Callable).
    /// Keep this in one place so you can rename the function server-side later without touching call sites.
    private let callableName = "sendTaskNotification"

    // MARK: - Permission (Remote Push display permission)

    /// Requests permission to display REMOTE push notifications (banner/sound/badge).
    /// This does not schedule or deliver local notifications.
    func requestAuthorizationIfNeeded(completion: ((Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                completion?(true)
            case .denied:
                completion?(false)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    completion?(granted)
                }
            default:
                completion?(false)
            }
        }
    }

    // MARK: - Public API (Fire-and-forget, but optionally observable later)

    /// Sends a push notification by calling a Firebase Callable Cloud Function.
    ///
    /// - Important:
    ///   - This is intentionally "fire and forget" by default (ignores errors).
    ///   - You can pass `completion` later to observe failures/success without changing call sites.
    ///
    /// Suggested payload handling server-side:
    /// - Use `context.auth.uid` as the user scope.
    /// - Fan-out to all device tokens stored under that user.
    func sendPush(
        subject: String,
        body: String,
        taskId: String? = nil,
        eventType: String? = nil,
        sourceDeviceID: String? = nil,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        // Must be authenticated for callable context.auth to exist.
        guard let _ = Auth.auth().currentUser else {
            completion?(.failure(NSError(domain: "Auth", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "No authenticated user for push call."
            ])))
            return
        }

        // Minimal sanitization to avoid sending empty text.
        let safeSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Notification"
            : subject

        let safeBody = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Event occurred."
            : body

        var payload: [String: Any] = [
            "subject": safeSubject,
            "body": safeBody
        ]

        // Optional metadata for routing, dedupe, and future analytics.
        if let taskId, !taskId.isEmpty { payload["taskId"] = taskId }
        if let eventType, !eventType.isEmpty { payload["eventType"] = eventType }
        if let sourceDeviceID, !sourceDeviceID.isEmpty { payload["sourceDeviceID"] = sourceDeviceID }

        let functions = Functions.functions()
        functions.httpsCallable(callableName).call(payload) { result, error in
            if let error = error {
                // By default: ignore. But allow optional completion for later observability.
                completion?(.failure(error))
                return
            }

            // If you later want structured results, parse `result?.data` here.
            completion?(.success(()))
        }
    }
}
