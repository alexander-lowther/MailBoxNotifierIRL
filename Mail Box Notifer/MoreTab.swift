

//
//  MoreTab.swift
//  Mailbox Notifier IRL
//
//  Production-ready "More" tab.
//  - Permission status + one-tap link to Settings (Notifications/Camera/Mic)
//  - About/Privacy/Support placeholders
//  - Safe drop-in: no external dependencies
//
/*
import SwiftUI
import UserNotifications
import AVFoundation
import UIKit

struct MoreTab: View {
    let uid: String
    let deviceID: String

    var body: some View {
        AppNavigationContainer {
            List {
                Section {
                    CompatNavigationLink {
                        PermissionsView(uid: uid, deviceID: deviceID)
                    } label: {
                        Label("Permissions", systemImage: "checkmark.shield")
                    }
                } header: {
                    Text("Settings")
                }

                Section {
                    CompatNavigationLink { AboutView() } label: {
                        Label("About Mailbox Notifier IRL", systemImage: "info.circle")
                    }
                    CompatNavigationLink { PrivacyView() } label: {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                    CompatNavigationLink { SupportView() } label: {
                        Label("Help & Support", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("About")
                }

                Section {
                    CompatNavigationLink { UpcomingView() } label: {
                        Label("Roadmap", systemImage: "map")
                    }
                    CompatNavigationLink { UpcomingView() } label: {
                        Label("Beta Features", systemImage: "sparkles")
                    }
                    CompatNavigationLink { UpcomingView() } label: {
                        Label("Changelog", systemImage: "list.bullet.rectangle")
                    }
                } header: {
                    Text("Upcoming")
                }
            }
            .navigationTitle("More")
        }
    }
}

// MARK: - Permissions

private struct PermissionsView: View {
    let uid: String
    let deviceID: String

    @State private var notifStatus: PermissionStatus = .loading
    @State private var cameraStatus: PermissionStatus = .loading
    @State private var micStatus: PermissionStatus = .loading

    var body: some View {
        List {
            Section {
                PermissionRow(
                    title: "Notifications",
                    systemImage: "bell.badge",
                    status: notifStatus,
                    primaryActionTitle: primaryNotifActionTitle,
                    primaryAction: primaryNotifAction,
                    secondaryActionTitle: "Open Settings",
                    secondaryAction: openAppSettings
                )

                PermissionRow(
                    title: "Camera",
                    systemImage: "camera",
                    status: cameraStatus,
                    primaryActionTitle: "Open Settings",
                    primaryAction: openAppSettings
                )

                PermissionRow(
                    title: "Microphone",
                    systemImage: "mic",
                    status: micStatus,
                    primaryActionTitle: "Open Settings",
                    primaryAction: openAppSettings
                )

                Text("iOS permissions are managed in Settings. If something is disabled, tap Open Settings to enable it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } header: {
                Text("Permissions")
            }

            Section("Device") {
                LabeledContent("Signed-in UID", value: uid)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LabeledContent("Device ID", value: deviceID)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshStatuses() }
    }

    private var primaryNotifActionTitle: String {
        switch notifStatus {
        case .notDetermined: return "Allow Notifications"
        case .denied: return "Open Settings"
        case .authorized: return "Open Settings"
        case .limited: return "Open Settings"
        case .loading: return "…"
        }
    }

    private var primaryNotifAction: () -> Void {
        switch notifStatus {
        case .notDetermined:
            return requestNotifications
        case .denied, .authorized, .limited:
            return openAppSettings
        case .loading:
            return {}
        }
    }

    private func refreshStatuses() {
        fetchNotificationStatus { notifStatus = $0 }
        fetchCameraStatus { cameraStatus = $0 }
        fetchMicStatus { micStatus = $0 }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async {
                refreshStatuses()
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Permission utilities

private enum PermissionStatus: String {
    case loading
    case notDetermined
    case denied
    case authorized
    case limited

    var pillText: String {
        switch self {
        case .loading: return "Checking…"
        case .notDetermined: return "Not set"
        case .denied: return "Denied"
        case .authorized: return "Allowed"
        case .limited: return "Limited"
        }
    }

    var pillSystemImage: String {
        switch self {
        case .loading: return "clock"
        case .notDetermined: return "questionmark.circle"
        case .denied: return "xmark.circle"
        case .authorized: return "checkmark.circle"
        case .limited: return "exclamationmark.circle"
        }
    }
}

private func fetchNotificationStatus(_ completion: @escaping (PermissionStatus) -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
        let status: PermissionStatus
        switch settings.authorizationStatus {
        case .notDetermined:
            status = .notDetermined
        case .denied:
            status = .denied
        case .authorized:
            status = .authorized
        case .provisional, .ephemeral:
            status = .limited
        @unknown default:
            status = .limited
        }
        DispatchQueue.main.async { completion(status) }
    }
}

private func fetchCameraStatus(_ completion: @escaping (PermissionStatus) -> Void) {
    let auth = AVCaptureDevice.authorizationStatus(for: .video)
    let status: PermissionStatus
    switch auth {
    case .notDetermined: status = .notDetermined
    case .restricted: status = .limited
    case .denied: status = .denied
    case .authorized: status = .authorized
    @unknown default: status = .limited
    }
    DispatchQueue.main.async { completion(status) }
}

private func fetchMicStatus(_ completion: @escaping (PermissionStatus) -> Void) {
    let auth = AVCaptureDevice.authorizationStatus(for: .audio)
    let status: PermissionStatus
    switch auth {
    case .notDetermined: status = .notDetermined
    case .restricted: status = .limited
    case .denied: status = .denied
    case .authorized: status = .authorized
    @unknown default: status = .limited
    }
    DispatchQueue.main.async { completion(status) }
}

// MARK: - UI Row

private struct PermissionRow: View {
    let title: String
    let systemImage: String
    let status: PermissionStatus

    var primaryActionTitle: String
    var primaryAction: () -> Void

    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                HStack(spacing: 6) {
                    Image(systemName: status.pillSystemImage)
                    Text(status.pillText)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Button(primaryActionTitle) { primaryAction() }
                    .buttonStyle(.bordered)

                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle) { secondaryAction() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - About / Privacy / Support / Upcoming (placeholders)

private struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Mailbox Notifier IRL")
                    .font(.title2.bold())

                Text("Use multiple signed-in devices to detect events and notify your other devices.")
                    .foregroundStyle(.secondary)

                Divider()

                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }
            .padding()
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy")
                    .font(.title2.bold())
                Text("Add your privacy details here (what you collect, what you store, and why).")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SupportView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Help & Support")
                    .font(.title2.bold())
                Text("Add your support instructions, troubleshooting steps, and contact method here.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct UpcomingView: View {
    var body: some View {
        List {
            Section("Upcoming") {
                Text("• Improved task reliability")
                Text("• Better cross-device visibility")
                Text("• Additional sensors and automations")
            }
        }
        .navigationTitle("Upcoming")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview {
    MoreTab(uid: "demoUID", deviceID: "demoDeviceID")
}
*/


import SwiftUI
import UserNotifications
import AVFoundation
import UIKit

struct MoreTab: View {
    let uid: String
    let deviceID: String

    var body: some View {
        AppNavigationContainer {
            List {
                Section {
                    CompatNavigationLink {
                        ContactOrReviewUsView()
                    } label: {
                        Label("Contact or Review Us", systemImage: "envelope.badge")
                    }
                } header: {
                    Text("Support")
                }

                Section {
                    CompatNavigationLink {
                        PermissionsView(uid: uid, deviceID: deviceID)
                    } label: {
                        Label("Permissions", systemImage: "checkmark.shield")
                    }
                } header: {
                    Text("Settings")
                }

                Section {
                    CompatNavigationLink { AboutView() } label: {
                        Label("About Mailbox Notifier IRL", systemImage: "info.circle")
                    }
                    CompatNavigationLink { PrivacyView() } label: {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                    CompatNavigationLink { SupportView() } label: {
                        Label("Help & Support", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("About")
                }

                Section {
                    CompatNavigationLink { UpcomingView() } label: {
                        Label("Roadmap", systemImage: "map")
                    }
                    CompatNavigationLink { UpcomingView() } label: {
                        Label("Beta Features", systemImage: "sparkles")
                    }
                    CompatNavigationLink { UpcomingView() } label: {
                        Label("Changelog", systemImage: "list.bullet.rectangle")
                    }
                } header: {
                    Text("Upcoming")
                }
            }
            .navigationTitle("More")
        }
    }
}

// MARK: - Contact / Review

private struct ContactOrReviewUsView: View {

    @State private var didCopyEmail = false

    private var developerEmail: String {
        // Optional: set in Info.plist as DEVELOPER_EMAIL
        (Bundle.main.object(forInfoDictionaryKey: "DEVELOPER_EMAIL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        ?? "support@yourdomain.com"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        List {
            Section {
                Button {
                    // Best practice: in-app prompt on explicit user action.
                    RateUs.requestReview()
                } label: {
                    Label("Rate in App", systemImage: "star.bubble")
                }

                Button {
                    // Stronger fallback if Apple suppresses the prompt.
                    RateUs.openAppStoreReviewPage()
                } label: {
                    Label("Write a Review in the App Store", systemImage: "square.and.pencil")
                }

                Text("Apple may not show the in-app rating prompt every time. If it doesn’t appear, use the App Store review button.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } header: {
                Text("Review")
            }

            Section {
                Button {
                    openMail(to: developerEmail)
                } label: {
                    Label("Email Developer", systemImage: "envelope")
                }

                Button {
                    UIPasteboard.general.string = developerEmail
                    didCopyEmail = true
                } label: {
                    Label("Copy Email Address", systemImage: "doc.on.doc")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Email")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(developerEmail)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Include this in your message")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

            } header: {
                Text("Contact")
            } footer: {
                Text("If you’re reporting a bug, please include what you expected, what happened, and whether the issue happens on more than one device.")
            }
        }
        .navigationTitle("Contact or Review Us")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Copied", isPresented: $didCopyEmail) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(developerEmail) copied to clipboard.")
        }
    }

    private func openMail(to email: String) {
        let subject = "Mailbox Notifier IRL Support"
        let body = "Hi!\n\nMy issue / feedback:\n\n(please describe)\n\nApp Version: \(appVersion) (\(buildNumber))\n"

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let urlString = "mailto:\(email)?subject=\(encodedSubject)&body=\(encodedBody)"
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

private extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Permissions

private struct PermissionsView: View {
    let uid: String
    let deviceID: String

    @State private var notifStatus: PermissionStatus = .loading
    @State private var cameraStatus: PermissionStatus = .loading
    @State private var micStatus: PermissionStatus = .loading

    var body: some View {
        List {
            Section {
                PermissionRow(
                    title: "Notifications",
                    systemImage: "bell.badge",
                    status: notifStatus,
                    primaryActionTitle: primaryNotifActionTitle,
                    primaryAction: primaryNotifAction,
                    secondaryActionTitle: "Open Settings",
                    secondaryAction: openAppSettings
                )

                PermissionRow(
                    title: "Camera",
                    systemImage: "camera",
                    status: cameraStatus,
                    primaryActionTitle: "Open Settings",
                    primaryAction: openAppSettings
                )

                PermissionRow(
                    title: "Microphone",
                    systemImage: "mic",
                    status: micStatus,
                    primaryActionTitle: "Open Settings",
                    primaryAction: openAppSettings
                )

                Text("iOS permissions are managed in Settings. If something is disabled, tap Open Settings to enable it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } header: {
                Text("Permissions")
            }

            Section("Device") {
                LabeledContent("Signed-in UID", value: uid)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LabeledContent("Device ID", value: deviceID)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshStatuses() }
    }

    private var primaryNotifActionTitle: String {
        switch notifStatus {
        case .notDetermined: return "Allow Notifications"
        case .denied: return "Open Settings"
        case .authorized: return "Open Settings"
        case .limited: return "Open Settings"
        case .loading: return "…"
        }
    }

    private var primaryNotifAction: () -> Void {
        switch notifStatus {
        case .notDetermined:
            return requestNotifications
        case .denied, .authorized, .limited:
            return openAppSettings
        case .loading:
            return {}
        }
    }

    private func refreshStatuses() {
        fetchNotificationStatus { notifStatus = $0 }
        fetchCameraStatus { cameraStatus = $0 }
        fetchMicStatus { micStatus = $0 }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async {
                refreshStatuses()
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Permission utilities

private enum PermissionStatus: String {
    case loading
    case notDetermined
    case denied
    case authorized
    case limited

    var pillText: String {
        switch self {
        case .loading: return "Checking…"
        case .notDetermined: return "Not set"
        case .denied: return "Denied"
        case .authorized: return "Allowed"
        case .limited: return "Limited"
        }
    }

    var pillSystemImage: String {
        switch self {
        case .loading: return "clock"
        case .notDetermined: return "questionmark.circle"
        case .denied: return "xmark.circle"
        case .authorized: return "checkmark.circle"
        case .limited: return "exclamationmark.circle"
        }
    }
}

private func fetchNotificationStatus(_ completion: @escaping (PermissionStatus) -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
        let status: PermissionStatus
        switch settings.authorizationStatus {
        case .notDetermined:
            status = .notDetermined
        case .denied:
            status = .denied
        case .authorized:
            status = .authorized
        case .provisional, .ephemeral:
            status = .limited
        @unknown default:
            status = .limited
        }
        DispatchQueue.main.async { completion(status) }
    }
}

private func fetchCameraStatus(_ completion: @escaping (PermissionStatus) -> Void) {
    let auth = AVCaptureDevice.authorizationStatus(for: .video)
    let status: PermissionStatus
    switch auth {
    case .notDetermined: status = .notDetermined
    case .restricted: status = .limited
    case .denied: status = .denied
    case .authorized: status = .authorized
    @unknown default: status = .limited
    }
    DispatchQueue.main.async { completion(status) }
}

private func fetchMicStatus(_ completion: @escaping (PermissionStatus) -> Void) {
    let auth = AVCaptureDevice.authorizationStatus(for: .audio)
    let status: PermissionStatus
    switch auth {
    case .notDetermined: status = .notDetermined
    case .restricted: status = .limited
    case .denied: status = .denied
    case .authorized: status = .authorized
    @unknown default: status = .limited
    }
    DispatchQueue.main.async { completion(status) }
}

// MARK: - UI Row

private struct PermissionRow: View {
    let title: String
    let systemImage: String
    let status: PermissionStatus

    var primaryActionTitle: String
    var primaryAction: () -> Void

    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                HStack(spacing: 6) {
                    Image(systemName: status.pillSystemImage)
                    Text(status.pillText)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Button(primaryActionTitle) { primaryAction() }
                    .buttonStyle(.bordered)

                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle) { secondaryAction() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - About / Privacy / Support / Upcoming (placeholders)

private struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Mailbox Notifier IRL")
                    .font(.title2.bold())

                Text("Use multiple signed-in devices to detect events and notify your other devices.")
                    .foregroundStyle(.secondary)

                Divider()

                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }
            .padding()
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy")
                    .font(.title2.bold())
                Text("Add your privacy details here (what you collect, what you store, and why).")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SupportView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Help & Support")
                    .font(.title2.bold())
                Text("Add your support instructions, troubleshooting steps, and contact method here.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct UpcomingView: View {
    var body: some View {
        List {
            Section("Upcoming") {
                Text("• Improved task reliability")
                Text("• Better cross-device visibility")
                Text("• Additional sensors and automations")
            }
        }
        .navigationTitle("Upcoming")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    MoreTab(uid: "demoUID", deviceID: "demoDeviceID")
}
