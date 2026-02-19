
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
    let threshold: Double?
    let type: String
    init?(id: String, data: [String: Any]) {
        guard
            let name = data["name"] as? String,
            let dbDeviceID = data["deviceID"] as? String,
            let startedAt = (data["startedAt"] as? Timestamp)?.dateValue(),
            let deviceName = data["deviceName"] as? String
        else { return nil }

        self.id = id
        self.name = name
        self.deviceID = dbDeviceID
        self.startedAt = startedAt
        self.deviceName = deviceName
        self.endedAt = (data["endedAt"] as? Timestamp)?.dateValue()
        self.endedBy = data["endedBy"] as? String
        self.notificationTitle = data["notificationTitle"] as? String
        self.notificationBody = data["notificationBody"] as? String
        self.threshold = data["threshold"] as? Double
        self.type = data["type"] as? String ?? "default"
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


import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import UIKit
import FirebaseMessaging
import FirebaseFirestore

func syncFCMTokenAfterLogin(uid: String, deviceID: String) {
    Messaging.messaging().token { token, error in
        guard let token = token, error == nil else { return }

        let db = Firestore.firestore()
        upsertDeviceFCMToken(uid: uid, deviceID: deviceID, token: token)
    }
}
struct AuthGate: View {
    @Binding var currentNonce: String?
    @Binding var errorMessage: String?

    @AppStorage("userUID") private var userUID: String = ""

    let deviceID = DeviceIdentity.id();

    // MARK: - Nonce helpers

    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var random: UInt8 = 0
            SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - Firestore writes (STRICT + SAFE)

    /// Creates/updates user info.
    /// Only `signedInAt` ever changes.
    private func writeUserInfo(uid: String, email: String?) {
        var data: [String: Any] = [
            "signedInAt": FieldValue.serverTimestamp()
        ]

        // Email written once (Apple only returns it first sign-in)
        if let email, !email.isEmpty {
            data["email"] = email
        }

        Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("info")
            .document("main")
            .setData(data, merge: true)
    }


    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.secondarySystemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                // Brand / Header
                VStack(spacing: 10) {
                    Image(systemName: "bolt.badge.clock")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("WatchTool")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Sign in to sync tasks across your devices.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 12)

                // Sign-in Card
                VStack(spacing: 14) {
                    SignInWithAppleButton { req in
                        let nonce = randomNonceString()
                        currentNonce = nonce
                        req.requestedScopes = [.email]
                        req.nonce = sha256(nonce)
                    } onCompletion: { result in
                        switch result {
                        case .success(let auth):
                            guard
                                let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                                let nonce = currentNonce,
                                let tokenData = cred.identityToken,
                                let idToken = String(data: tokenData, encoding: .utf8)
                            else {
                                errorMessage = "Apple sign-in failed."
                                return
                            }

                            let credential = OAuthProvider.credential(
                                withProviderID: "apple.com",
                                idToken: idToken,
                                rawNonce: nonce
                            )

                            Auth.auth().signIn(with: credential) { res, err in
                                if let err {
                                    errorMessage = err.localizedDescription
                                    return
                                }

                                guard let user = res?.user else { return }

                                // Persist auth state
                                userUID = user.uid
                                if let pending = UserDefaults.standard.string(forKey: "pendingFCMToken"),
                                   !pending.isEmpty {
                                    upsertDeviceFCMToken(uid: user.uid, deviceID: deviceID, token: pending)
                                    UserDefaults.standard.removeObject(forKey: "pendingFCMToken")
                                }

                                upsertDeviceBaseline(uid: user.uid, deviceID: deviceID)
                                syncFCMTokenAfterLogin(uid: user.uid, deviceID: deviceID)
                            }

                        case .failure(let err):
                            errorMessage = err.localizedDescription
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)
                )
                .padding(.horizontal, 18)

                // Error message (clean, card-like)
                if let errorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 14, weight: .semibold))

                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.red.opacity(0.08))
                    )
                    .padding(.horizontal, 18)
                    .transition(.opacity)
                }

                Spacer()

                // Footer
                Text("Apple Sign-In is used only to create your account and sync devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 14)
            }
        }
        .onAppear {
            // no logic changes
        }
    }

    
}

// MARK: - Optional Loading Gate (simple countdown)
private struct LottieLoadingGate: View {
    let seconds: Double
    let onFinish: () -> Void

    init(seconds: Double = 3.0, onFinish: @escaping () -> Void) {
        self.seconds = max(0, seconds)
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            // Keep your splash background color here
            Color(red: 61/255, green: 99/255, blue: 68/255).ignoresSafeArea()

            LottieLoaderView(name: "loadingLogo 2")
                .frame(width: 240, height: 240)
        }
        .onAppear {
            guard seconds > 0 else { onFinish(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                onFinish()
            }
        }
    }
}
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
    let deviceID = DeviceIdentity.id()
    
    var body: some View {
        Group {
            if authUID.isEmpty {
                AuthGate(currentNonce: $currentNonce, errorMessage: $errorMessage)
            }
            
            
            
            else if showLoadingGate {
                LottieLoadingGate(seconds: 3.0) {
                    showLoadingGate = false
                }
                .onAppear {
                    bootstrapAfterAuth()
                }
                
            } else {
                AppNavigationContainer {
                    TabView {
                        HomeTab(userUID: userUID, deviceID: deviceID)
                            .tabItem { Label("Home", systemImage: "house.fill") }
                        
                        TasksTab(deviceID: deviceID)
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
        
        
        
        // 2) End orphan tasks for THIS device (app-load cleanup)
        forceEndOpenTasksForDevice(deviceID: deviceID, endedBy: "App Load") { err in
            if let err = err {
             //   errorMessage = "Task cleanup failed: \(err.localizedDescription)"
            }
        }
        
        // 3) Initial fetch (manual)
        taskLog.refresh(userUID: userUID) { err in
            if let err = err {
               // errorMessage = "Loading previous tasks failed: \(err.localizedDescription)"
            }
        }
    }
}

func upsertDeviceBaseline(uid: String, deviceID: String) {
    
 //   Logger.insertLog("supsertDeviceBS", "started", Date())
    Firestore.firestore()
        .collection("users")
        .document(uid)
        .collection("devices")
        .document(deviceID)
        .setData([
            "name": UIDevice.current.name,
            "model": UIDevice.current.model,
            "systemVersion": UIDevice.current.systemVersion,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": "upsertDeviceBaseline"
            // keep createdAt stable-ish by only setting if missing is hard without a transaction;
            // if you truly care, use Option B below.
    
        ], merge: true)
    
  //  Logger.insertLog("supsertDeviceBS", "sexit", Date())

}


