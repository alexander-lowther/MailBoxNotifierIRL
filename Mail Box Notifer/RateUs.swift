//
//  RateUs.swift
//  Mail Box Notifer
//
//  Created by user281046 on 2/7/26.
//

import StoreKit
import UIKit

/// Centralized rating / review helper.
///
/// Important:
/// - Apple does *not* guarantee the in-app review prompt will appear every time.
/// - This helper tries the in-app prompt first, then you can optionally send users to the App Store
///   review page as a fallback.
///
/// Setup for App Store fallback:
/// - Preferred: add `APP_STORE_ID` (String) to Info.plist.
/// - Or set `RateUs.appStoreIDOverride` at runtime.
enum RateUs {

    /// Optional override (e.g., set this once at app launch).
    static var appStoreIDOverride: String?

    /// Info.plist key used for App Store ID.
    private static let infoPlistKey = "APP_STORE_ID"

    /// Requests an in-app review prompt if possible.
    ///
    /// If you're calling this from SwiftUI, it's best to call it as a result of an explicit user action
    /// (button tap) to maximize the chance iOS will show the prompt.
    static func requestReview() {
        DispatchQueue.main.async {
            guard let scene = activeForegroundScene() else {
                // No active scene (rare). Can't present in-app prompt.
                return
            }
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    /// Opens the App Store "Write a Review" page for this app.
    ///
    /// This is the only way to truly *force* showing something review-related, but it requires the App Store ID.
    static func openAppStoreReviewPage() {
        guard let appID = resolvedAppStoreID(), !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Missing App Store ID.
            return
        }

        // "write-review" deep link
        // iOS will handle the itms-apps scheme.
        let urlString = "itms-apps://itunes.apple.com/app/id\(appID)?action=write-review"
        guard let url = URL(string: urlString) else { return }

        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    /// Convenience: try in-app prompt, and if you want, you can also offer a button
    /// that opens the App Store review page.
    static func promptThenOfferStoreFallback() {
        requestReview()
    }

    // MARK: - Private

    private static func resolvedAppStoreID() -> String? {
        if let override = appStoreIDOverride { return override }
        if let val = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String {
            return val
        }
        return nil
    }

    private static func activeForegroundScene() -> UIWindowScene? {
        // Find the active foreground scene.
        let scenes = UIApplication.shared.connectedScenes
        for s in scenes {
            guard let ws = s as? UIWindowScene else { continue }
            if ws.activationState == .foregroundActive {
                return ws
            }
        }
        // Fallback: any window scene
        return scenes.compactMap { $0 as? UIWindowScene }.first
    }
}
