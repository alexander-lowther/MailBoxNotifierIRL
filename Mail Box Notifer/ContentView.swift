// ContentView.swift
/*
import SwiftUI
import Firebase
import AuthenticationServices
import CryptoKit
import UserNotifications
import FirebaseMessaging

struct ContentView: View {
    @AppStorage("userUID") var userUID: String = ""
    @State private var currentNonce: String?
    @State private var mailDetected = false
    @State private var errorMessage: String?

    let db = Firestore.firestore()

    var body: some View {
        VStack(spacing: 20) {
            if userUID.isEmpty {
                Text("\u{1F4EC} Mailbox Notifier IRL")
                    .font(.largeTitle)
                    .bold()
                Text("Sign in with Apple to link this device.")
                    .multilineTextAlignment(.center)

                SignInWithAppleButton(
                    onRequest: { request in
                        let nonce = randomNonceString()
                        currentNonce = nonce
                        request.requestedScopes = [.email]
                        request.nonce = sha256(nonce)
                    },
                    onCompletion: handleAppleSignIn
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
            } else {
                DeviceRegistrationView(userUID: userUID)

                if mailDetected {
                    Text("\u{1F4E9} Mail Detected!")
                        .foregroundColor(.green)
                } else {
                    Text("\u{1F4ED} Waiting for Mail...")
                        .foregroundColor(.gray)
                }

                Button("\u{1F4E6} Simulate Mail Detection") {
                    simulateMailDetection()
                }
                .buttonStyle(.borderedProminent)

                Button("\u{1F504} Reset Mail Status") {
                    resetMailFlag()
                }
                .foregroundColor(.red)
                .font(.caption)
            }

            if let error = errorMessage {
                Text(error).foregroundColor(.red)
            }
        }
        .padding()
        .onAppear {
            requestNotificationPermission()
            if !userUID.isEmpty {
                listenForMail()
            }
        }
    }

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authResults):
            guard let appleIDCredential = authResults.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce,
                  let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                self.errorMessage = "Apple credentials failed."
                return
            }

            let credential = OAuthProvider.credential(withProviderID: "apple.com", idToken: idTokenString, rawNonce: nonce)
            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    self.errorMessage = "Firebase Auth failed: \(error.localizedDescription)"
                    return
                }
                guard let user = authResult?.user else { return }
                self.userUID = user.uid
                listenForMail()
            }
        case .failure(let error):
            self.errorMessage = "Sign in failed: \(error.localizedDescription)"
        }
    }

    func simulateMailDetection() {
        guard let userUID = Auth.auth().currentUser?.uid else {
            print("❌ Not signed in")
            return
        }

        let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["userId": userUID]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Error calling function: \(error)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Function response status: \(httpResponse.statusCode)")
            }

            if let data = data {
                let responseText = String(data: data, encoding: .utf8) ?? "n/a"
                print("🔁 Response: \(responseText)")
            }
        }.resume()
    }


    func resetMailFlag() {
        db.collection("users")
            .document(userUID)
            .updateData(["mailDetected": false])
        self.mailDetected = false
    }

    func listenForMail() {
        db.collection("users")
            .document(userUID)
            .addSnapshotListener { snapshot, error in
                guard let data = snapshot?.data(),
                      let detected = data["mailDetected"] as? Bool else {
                    print("⚠️ Failed to parse mailDetected")
                    return
                }
                self.mailDetected = detected
                print("🔄 mailDetected updated to: \(detected)")
            }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
            } else {
                print("✅ Notification permission granted: \(granted)")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if status == errSecSuccess {
                    return random
                } else {
                    fatalError("Nonce generation failed.")
                }
            }

            for random in randoms where remainingLength > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

struct DeviceRegistrationView: View {
    @State private var isRegistered = false
    @State private var registrationStatus: String = ""

    let db = Firestore.firestore()
    let userUID: String
    let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

    var body: some View {
        VStack(spacing: 16) {
            Text("\u{1F4F1} Register This Device")
                .font(.title2)
                .bold()

            Text("Device ID:\n\(deviceID)")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)

            Button("Register for Notifications") {
                registerThisDevice()
            }
            .buttonStyle(.borderedProminent)

            if isRegistered {
                Text("\u{2705} This device is registered!")
                    .foregroundColor(.green)
            } else if !registrationStatus.isEmpty {
                Text(registrationStatus)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .onAppear {
            checkIfRegistered()
        }
    }

    func checkIfRegistered() {
        db.collection("users")
            .document(userUID)
            .collection("devices")
            .document(deviceID)
            .getDocument { docSnapshot, error in
                if let doc = docSnapshot, doc.exists {
                    self.isRegistered = true
                }
            }
    }

    func registerThisDevice() {
        Messaging.messaging().token { token, error in
            if let error = error {
                registrationStatus = "❌ Failed to get token: \(error.localizedDescription)"
                return
            }

            guard let token = token else {
                registrationStatus = "❌ Token is nil"
                return
            }

            let deviceData: [String: Any] = [
                "token": token,
                "model": UIDevice.current.model,
                "isActive": true,
                "updatedAt": FieldValue.serverTimestamp()
            ]

            db.collection("users")
                .document(userUID)
                .collection("devices")
                .document(deviceID)
                .setData(deviceData, merge: true) { error in
                    if let error = error {
                        registrationStatus = "❌ Failed to register: \(error.localizedDescription)"
                    } else {
                        isRegistered = true
                        registrationStatus = ""
                        print("✅ Device registered with token: \(token)")
                    }
                }
        }
    }
}
*/

import SwiftUI
import Firebase
import FirebaseMessaging
import UserNotifications
import AuthenticationServices
import CryptoKit

// MARK: - Single-file App Entry

// MARK: - AppDelegate (APNs/FCM wiring)

// MARK: - Root Content
struct ContentView: View {
    @AppStorage("userUID") private var userUID: String = ""
    @State private var currentNonce: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if userUID.isEmpty {
                AuthGate(currentNonce: $currentNonce, errorMessage: $errorMessage)
            } else {
                MainShell(userUID: userUID)
            }
        }
        .onAppear {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
    }
}

// MARK: - Auth Gate (Sign in with Apple)
struct AuthGate: View {
    @Binding var currentNonce: String?
    @Binding var errorMessage: String?
    @AppStorage("userUID") private var userUID: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 20)
            Text("📮 Mailbox Notifier IRL").font(.largeTitle.bold())
            Text("Sign in with Apple to link this device.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)

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
                          let idToken = String(data: tokenData, encoding: .utf8) else {
                        errorMessage = "Apple credentials failed."; return
                    }
                    let credential = OAuthProvider.credential(withProviderID: "apple.com", idToken: idToken, rawNonce: nonce)
                    Auth.auth().signIn(with: credential) { res, err in
                        if let err = err { errorMessage = "Firebase Auth failed: \(err.localizedDescription)"; return }
                        userUID = res?.user.uid ?? ""
                    }
                case .failure(let err):
                    errorMessage = "Sign in failed: \(err.localizedDescription)"
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52).clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            if let e = errorMessage {
                Text(e).font(.footnote).foregroundStyle(.red).padding(.horizontal)
            }
            Spacer()
        }
        .background(
            LinearGradient(colors: [.blue.opacity(0.08), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

// MARK: - Main Shell (Tabs + Bell)
struct MainShell: View {
    let userUID: String
    @State private var showNotifications = false

    var body: some View {
        NavigationStack {
            TabView {
                HomeView(userUID: userUID)
                    .tabItem { Label("Home", systemImage: "house.fill") }

                DevicesView(userUID: userUID)
                    .tabItem { Label("Devices", systemImage: "iphone.gen3") }

                MeView(userUID: userUID)
                    .tabItem { Label("Me", systemImage: "person.crop.circle") }

                SettingsView(userUID: userUID)
                    .tabItem { Label("Settings", systemImage: "gearshape") }

                AboutView()
                    .tabItem { Label("About", systemImage: "info.circle") }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNotifications = true } label: {
                        Image(systemName: "bell.fill").imageScale(.large)
                    }
                    .accessibilityLabel("Notifications")
                }
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsView(userUID: userUID)
            }
        }
    }
}

// MARK: - Home
struct HomeView: View {
    let userUID: String
    @State private var mailDetected = false
    @State private var errorMessage: String?
    private let db = Firestore.firestore()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: mailDetected ? "envelope.badge.fill" : "envelope.open")
                        .font(.system(size: 44, weight: .semibold))
                    Text(mailDetected ? "Mail Detected!" : "Waiting for Mail…")
                        .font(.title3.bold())
                        .foregroundStyle(mailDetected ? .green : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)

                VStack(spacing: 12) {
                    Button {
                        simulateMailDetection()
                    } label: {
                        Label("Simulate Mail Detection", systemImage: "shippingbox.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                    Button(role: .destructive) {
                        resetMailFlag()
                    } label: {
                        Label("Reset Mail Status", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                }

                if let err = errorMessage {
                    Text(err).foregroundStyle(.red).font(.footnote)
                }
                Spacer(minLength: 24)
            }
            .padding(.top, 16)
        }
        .navigationTitle("Home")
        .onAppear { listenForMail() }
    }

    func simulateMailDetection() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["userId": uid])
        URLSession.shared.dataTask(with: req).resume()
    }

    func resetMailFlag() {
        db.collection("users").document(userUID).updateData(["mailDetected": false])
        mailDetected = false
    }

    func listenForMail() {
        db.collection("users").document(userUID).addSnapshotListener { snap, _ in
            guard let data = snap?.data(), let detected = data["mailDetected"] as? Bool else { return }
            mailDetected = detected
        }
    }
}

// MARK: - Devices
struct Device: Identifiable {
    let id: String
    let model: String
    let name: String
    let bundleID: String
    let systemVersion: String
    let isActive: Bool
    let updatedAt: Date?
    let token: String?

    init(id: String, data: [String: Any]) {
        self.id = id
        self.model = data["model"] as? String ?? "Unknown"
        self.name = data["name"] as? String ?? ""
        self.bundleID = data["bundleID"] as? String ?? ""
        self.systemVersion = data["systemVersion"] as? String ?? ""
        self.isActive = data["isActive"] as? Bool ?? false
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        self.token = data["token"] as? String
    }
}

struct DevicesView: View {
    let userUID: String
    @State private var devices: [Device] = []
    private let db = Firestore.firestore()

    var body: some View {
        List(devices) { device in
            DeviceRow(device: device)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Devices")
        .onAppear { subscribe() }
    }

    func subscribe() {
        db.collection("users").document(userUID).collection("devices")
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                devices = docs.map { Device(id: $0.documentID, data: $0.data()) }
            }
    }
}

struct DeviceRow: View {
    let device: Device
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 28))
                .foregroundStyle(device.isActive ? .green : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name.isEmpty ? device.model : device.name)
                    .font(.headline)
                Text(device.id).font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if !device.systemVersion.isEmpty {
                        Text("iOS \(device.systemVersion)").font(.caption).foregroundStyle(.secondary)
                    }
                    if !device.bundleID.isEmpty {
                        Text("· \(device.bundleID)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let updated = device.updatedAt {
                    Text(updated, style: .relative)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: device.isActive ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(device.isActive ? .green : .secondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Me
struct MeView: View {
    let userUID: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
                .padding(.top, 24)

            if let user = Auth.auth().currentUser {
                Text(user.email ?? "Signed in with Apple").font(.headline)
                Text("User ID: \(user.uid)").font(.caption).foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                try? Auth.auth().signOut()
                UserDefaults.standard.removeObject(forKey: "userUID")
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
        .navigationTitle("Me")
    }
}

// MARK: - Settings
struct SettingsView: View {
    let userUID: String
    @State private var playSound = true
    @State private var showBanner = true
    @State private var vibrate = true

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Show Banner", isOn: $showBanner)
                Toggle("Play Sound", isOn: $playSound)
                Toggle("Vibrate", isOn: $vibrate)
            }

            Section("Devices") {
                NavigationLink {
                    DevicesView(userUID: userUID)
                } label: {
                    Label("Manage Devices", systemImage: "iphone.and.arrow.forward")
                }
            }

            Section("Advanced") {
                NavigationLink("Notification Permissions") {
                    Text("Open iOS Settings → Notifications to adjust system-level options.")
                        .padding()
                }
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - About
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("About Mailbox Notifier IRL").font(.title.bold())
                Text("""
Our mission is to make real-world mail detection simple and reliable using the devices you already own. Every signed-in device can detect mail and receive notifications—no hubs, no wiring.
""")
                VStack(alignment: .leading, spacing: 8) {
                    Label("Private by design", systemImage: "lock.fill")
                    Label("Fast push notifications", systemImage: "bolt.fill")
                    Label("Works on multiple devices", systemImage: "iphone.gen3")
                }
                .font(.subheadline)
                Spacer(minLength: 24)
            }
            .padding()
        }
        .navigationTitle("About")
    }
}

// MARK: - Notifications (sheet opened by bell)
struct NotifItem: Identifiable {
    let id: String
    let title: String
    let body: String
    let createdAt: Date
    init(id: String, data: [String: Any]) {
        self.id = id
        self.title = data["title"] as? String ?? "Notification"
        self.body = data["body"] as? String ?? ""
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
    }
}

struct NotificationsView: View {
    let userUID: String
    @Environment(\.dismiss) private var dismiss
    @State private var items: [NotifItem] = []
    private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            List(items) { n in
                VStack(alignment: .leading, spacing: 4) {
                    Text(n.title).font(.headline)
                    Text(n.body).font(.subheadline).foregroundStyle(.secondary)
                    Text(n.createdAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Notifications")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
            .onAppear { subscribe() }
        }
    }

    func subscribe() {
        db.collection("users").document(userUID).collection("notifications")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { snap, _ in
                guard let docs = snap?.documents else { return }
                items = docs.map { NotifItem(id: $0.documentID, data: $0.data()) }
            }
    }
}

// MARK: - Helpers (nonce/hash)
func randomNonceString(length: Int = 32) -> String {
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""; var remaining = length
    while remaining > 0 {
        let randoms: [UInt8] = (0..<16).map { _ in
            var r: UInt8 = 0; _ = SecRandomCopyBytes(kSecRandomDefault, 1, &r); return r
        }
        for r in randoms where remaining > 0 {
            if r < charset.count { result.append(charset[Int(r)]); remaining -= 1 }
        }
    }
    return result
}

func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashed = SHA256.hash(data: inputData)
    return hashed.map { String(format: "%02x", $0) }.joined()
}

