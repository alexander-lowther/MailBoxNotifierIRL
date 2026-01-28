

import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit
import UIKit

// MARK: - Task Model

struct TaskDoc: Identifiable {
    let id: String
    let name: String
    let deviceID: String
    let startedAt: Date
    let endedAt: Date?
    let endedBy: String?
    let notificationTitle: String?
    let notificationBody: String?
    let hasSamples: Bool
    let deviceName: String

    init?(id: String, data: [String: Any]) {
        guard
            let name = data["name"] as? String,
            let deviceID = data["deviceID"] as? String,
            let startedAt = (data["startedAt"] as? Timestamp)?.dateValue(),
            let deviceName = data["deviceName"] as? String
        else { return nil }

        self.id = id
        self.name = name
        self.deviceID = deviceID
        self.startedAt = startedAt
        self.deviceName = deviceName
        self.endedAt = (data["endedAt"] as? Timestamp)?.dateValue()
        self.endedBy = data["endedBy"] as? String
        self.notificationTitle = data["notificationTitle"] as? String
        self.notificationBody = data["notificationBody"] as? String

        if let samples = data["samples"] as? [[String: Any]] {
            self.hasSamples = !samples.isEmpty
        } else {
            self.hasSamples = false
        }
    }
}

// MARK: - TaskLog (NO realtime listener; manual refresh only)
import Foundation
import FirebaseFirestore

final class TaskLog: ObservableObject {
    @Published var previousTasks: [TaskDoc] = []
    @Published var activeTasks: [TaskDoc] = []   // ✅ ADDED

    func refresh(userUID: String, completion: ((Error?) -> Void)? = nil) {
        guard !userUID.isEmpty else {
            previousTasks = []
            activeTasks = []                     // ✅ ADDED
            completion?(NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in."]))
            return
        }

        Firestore.firestore()
            .collection("users")
            .document(userUID)
            .collection("tasks")
            .order(by: "startedAt", descending: true)
            .limit(to: 100)
            .getDocuments { [weak self] snap, err in
                if let err = err {
                    completion?(err)
                    return
                }

                let docs = snap?.documents ?? []
                let all = docs.compactMap { TaskDoc(id: $0.documentID, data: $0.data()) }

                // ✅ ADDED: active = endedAt missing OR null OR not set (all map to endedAt == nil)
                let active = all
                    .filter { $0.endedAt == nil }
                    .sorted { $0.startedAt > $1.startedAt }

                // We only ever want ONE active task (most recent)
                self?.activeTasks = active.first.map { [$0] } ?? []

                // Existing previous task logic (unchanged)
                let closed = all.filter { $0.endedAt != nil }

                self?.previousTasks = closed.sorted { a, b in
                    switch (a.endedAt, b.endedAt) {
                    case let (da?, db?): return da > db
                    case (_?, nil): return true
                    case (nil, _?): return false
                    default: return a.startedAt > b.startedAt
                    }
                }

                completion?(nil)
            }
    }
}

// MARK: - AuthGate

struct AuthGate: View {
    @Binding var currentNonce: String?
    @Binding var errorMessage: String?

    @AppStorage("userUID") private var userUID: String = ""

    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var r: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &r)
                return r
            }
            for r in randoms where remaining > 0 {
                if r < charset.count {
                    result.append(charset[Int(r)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 20)

            Text("Mailbox Notifier IRL")
                .font(.largeTitle.bold())

            Text("Sign in with Apple to link this device.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.surface)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            SignInWithAppleButton { req in
                let nonce = randomNonceString()
                currentNonce = nonce
                req.requestedScopes = [.email]
                req.nonce = sha256(nonce)
            } onCompletion: { result in
                switch result {
                case .success(let auth):
                    guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                          let nonce = currentNonce,
                          let tokenData = cred.identityToken,
                          let idToken = String(data: tokenData, encoding: .utf8)
                    else {
                        errorMessage = "Apple credentials failed."
                        return
                    }

                    let credential = OAuthProvider.credential(
                        withProviderID: "apple.com",
                        idToken: idToken,
                        rawNonce: nonce
                    )

                    Auth.auth().signIn(with: credential) { res, err in
                        if let err = err {
                            errorMessage = "Firebase Auth failed: \(err.localizedDescription)"
                            return
                        }
                        userUID = res?.user.uid ?? ""
                    }

                case .failure(let err):
                    errorMessage = "Sign in failed: \(err.localizedDescription)"
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            if let e = errorMessage {
                Text(e)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Spacer()
        }
    }
}

// MARK: - Optional Loading Gate (simple countdown)

private struct LoadingGate: View {
    let seconds: Int
    let onFinish: () -> Void

    @State private var remaining: Int

    init(seconds: Int = 2, onFinish: @escaping () -> Void) {
        self.seconds = max(0, seconds)
        self.onFinish = onFinish
        _remaining = State(initialValue: max(0, seconds))
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
            Text(remaining > 0 ? "Loading… \(remaining)" : "Loading…")
                .foregroundStyle(.secondary)
                .font(.footnote)
            Spacer()
        }
        .onAppear {
            guard seconds > 0 else {
                onFinish()
                return
            }
            tick()
        }
    }

    private func tick() {
        if remaining <= 0 {
            onFinish()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            remaining -= 1
            tick()
        }
    }
}

// MARK: - Root View

struct ContentView: View {
    @AppStorage("userUID") private var userUID: String = ""
    @State private var currentNonce: String?
    @State private var errorMessage: String?

    @StateObject private var taskLog = TaskLog()

    @State private var showLoadingGate: Bool = true

    // NEW: drive UI off Firebase auth changes
    @State private var authUID: String = ""
    @State private var didBootstrap: Bool = false
    @State private var authListenerHandle: AuthStateDidChangeListenerHandle?

    // IMPORTANT: must match DevicesView stable device id behavior
    private let deviceID: String = {
        if let existing = UserDefaults.standard.string(forKey: "stable_device_id"), !existing.isEmpty {
            return existing
        }
        let newID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(newID, forKey: "stable_device_id")
        return newID
    }()

    var body: some View {
        Group {
            if authUID.isEmpty {
                AuthGate(currentNonce: $currentNonce, errorMessage: $errorMessage)
            } else if showLoadingGate {
                LoadingGate(seconds: 2) {
                    showLoadingGate = false
                }
                .onAppear {
                    bootstrapAfterAuth()
                }
            } else {
                NavigationStack {
                    TabView {
                        HomeTab(userUID: userUID, deviceID: deviceID)
                            .tabItem { Label("Home", systemImage: "house.fill") }

                        TasksTab(userUID: userUID, deviceID: deviceID)
                            .tabItem { Label("Tasks", systemImage: AppSymbols.best(["square.grid.2x2.fill","square.grid.2x2"])) }

                        DevicesView(userUID: userUID)
                            .tabItem { Label("Devices", systemImage: AppSymbols.best(["iphone.gen3","iphone"])) }

                        MeView(userUID: userUID)
                            .tabItem { Label("Me", systemImage: "person.crop.circle") }

                        MoreTab(uid: userUID, deviceID: deviceID)
                            .tabItem { Label("More", systemImage: "ellipsis.circle") }
                    }
                }
                .environmentObject(taskLog)
                .alert("Error", isPresented: Binding(
                    get: { errorMessage != nil && !(errorMessage ?? "").isEmpty },
                    set: { newValue in if !newValue { errorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
            }
        }
        .onAppear {
            attachAuthListenerIfNeeded()
        }
        .onDisappear {
            detachAuthListenerIfNeeded()
        }
    }

    // MARK: - Auth Listener (makes UI reactive)

    private func attachAuthListenerIfNeeded() {
        if authListenerHandle != nil { return }

        authUID = Auth.auth().currentUser?.uid ?? ""

        authListenerHandle = Auth.auth().addStateDidChangeListener { _, user in
            let newUID = user?.uid ?? ""

            // Drive UI updates
            authUID = newUID

            if newUID.isEmpty {
                // Signed out / token invalid
                userUID = ""
                didBootstrap = false
                showLoadingGate = true
            } else {
                // Keep AppStorage consistent
                if userUID != newUID {
                    userUID = newUID
                }
                // Ensure we show loading gate once after auth becomes valid
                showLoadingGate = true
                didBootstrap = false
            }
        }
    }

    private func detachAuthListenerIfNeeded() {
        if let h = authListenerHandle {
            Auth.auth().removeStateDidChangeListener(h)
            authListenerHandle = nil
        }
    }

    // MARK: - Bootstrap after auth (no realtime; one-time actions)

    private func bootstrapAfterAuth() {
        // Prevent repeated bootstrap runs while still allowing re-run after sign out/in
        if didBootstrap { return }
        didBootstrap = true

        // Hard assert AppStorage matches Auth
        let auth = Auth.auth().currentUser?.uid ?? ""
        guard !auth.isEmpty else {
            userUID = ""
            authUID = ""
            didBootstrap = false
            return
        }
        if userUID != auth { userUID = auth }

        // 1) Ensure device doc exists
        registerDeviceBaseOnceIfNeeded(userUID: userUID, deviceID: deviceID) { err in
            if let err = err {
                errorMessage = "Device registration failed: \(err.localizedDescription)"
            }
        }

        // 2) End orphan tasks for THIS device (app-load cleanup)
        forceEndOpenTasksForDevice(deviceID: deviceID, endedBy: "App Load") { err in
            if let err = err {
                errorMessage = "Task cleanup failed: \(err.localizedDescription)"
            }
        }

        // 3) Token write (if available)
        let cached = (UserDefaults.standard.string(forKey: "cached_fcm_token") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cached.isEmpty {
            upsertDeviceFCMToken(userUID: userUID, deviceID: deviceID, token: cached) { err in
                if let err = err {
                    errorMessage = "Saving push token failed: \(err.localizedDescription)"
                }
            }
        }

        // 4) Initial fetch (manual)
        taskLog.refresh(userUID: userUID) { err in
            if let err = err {
                errorMessage = "Loading previous tasks failed: \(err.localizedDescription)"
            }
        }
    }
}

// MARK: - Device writes (NO swallowed errors)

private func upsertDeviceFCMToken(
    userUID: String,
    deviceID: String,
    token: String,
    completion: ((Error?) -> Void)? = nil
) {
    let authUID = Auth.auth().currentUser?.uid ?? ""
    guard !authUID.isEmpty else {
        completion?(NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated."]))
        return
    }

    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        completion?(nil)
        return
    }

    Firestore.firestore()
        .collection("users")
        .document(authUID)
        .collection("devices")
        .document(deviceID)
        .setData([
            "fcmToken": trimmed,
            "fcmTokenUpdatedAt": Timestamp(date: Date())
        ], merge: true) { err in
            completion?(err)
        }
}

private func registerDeviceBaseOnceIfNeeded(
    userUID: String,
    deviceID: String,
    completion: ((Error?) -> Void)? = nil
) {
    let authUID = Auth.auth().currentUser?.uid ?? ""
    guard !authUID.isEmpty else {
        completion?(NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated."]))
        return
    }

    let key = "did_register_device_base_\(authUID)_\(deviceID)"
    if UserDefaults.standard.bool(forKey: key) {
        completion?(nil)
        return
    }

    let payload: [String: Any] = [
        "name": UIDevice.current.name,
        "model": UIDevice.current.model,
        "systemVersion": UIDevice.current.systemVersion,
        "createdAt": Timestamp(date: Date())
    ]

    Firestore.firestore()
        .collection("users")
        .document(authUID)
        .collection("devices")
        .document(deviceID)
        .setData(payload, merge: true) { err in
            if err == nil {
                UserDefaults.standard.set(true, forKey: key)
            }
            completion?(err)
        }
}
