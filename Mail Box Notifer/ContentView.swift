import SwiftUI
import Firebase
import FirebaseMessaging
import UserNotifications
import AuthenticationServices
import CryptoKit
import UIKit
import CoreMotion

// MARK: - Single-file App Entry

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

                // NEW: Functions tab replaces the former Sensor tab
                FunctionsView(userUID: userUID)
                    .tabItem { Label("Functions", systemImage: "square.grid.2x2.fill") }

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

// MARK: - NEW: Functions (formerly Sensor)
struct FunctionsView: View {
    let userUID: String

    struct FunctionItem: Identifiable {
        enum Status { case available, planned, accessory }
        let id = UUID()
        let title: String
        let subtitle: String
        let systemImage: String
        let status: Status
        let info: String
    }

    private var items: [FunctionItem] {
        [
            .init(title: "Mailbox Notifier", subtitle: "Detect mail + push alerts", systemImage: "envelope.badge", status: .available, info: "Uses camera or motion heuristics near the mailbox to detect openings. Sends push to all signed-in devices via FCM."),
            .init(title: "Dryer Notifier", subtitle: "Know when laundry finishes", systemImage: "washer", status: .available, info: "Place this phone on the dryer. It detects vibration, lets you know when the dryer starts, and notifies you again when your clothes are done."),
            .init(title: "Camera", subtitle: "Live view / snapshots", systemImage: "camera.viewfinder", status: .available, info: "Turns your old phone into a simple IP-style viewer within the app (no background server). Supports periodic snapshots to Firestore Storage (future)."),
            .init(title: "Motion Sensor", subtitle: "Device motion / vibration", systemImage: "waveform.path.ecg", status: .available, info: "Uses CoreMotion accelerometer/gyroscope to detect movement, bumps, or door openings. Triggers on-threshold push notifications."),
            .init(title: "Sound Detector", subtitle: "Noise/knock detection", systemImage: "ear.badge.waveform", status: .available, info: "Microphone-based knock/clang/bark threshold detection. All processing on-device; only events are uploaded."),
            .init(title: "Time-lapse", subtitle: "Interval photos", systemImage: "timer", status: .planned, info: "Capture frames on an interval and build a time-lapse locally. Option to sync to cloud later."),
            .init(title: "QR / Barcode", subtitle: "Scan & log", systemImage: "qrcode.viewfinder", status: .available, info: "Use the camera to scan codes and log events (arrivals, packages)."),
            .init(title: "Dashcam", subtitle: "Auto-record while moving", systemImage: "car.rear.fill", status: .planned, info: "Records when motion exceeds threshold and device is powered. Overwrites oldest clips (ring buffer)."),
            .init(title: "Baby Monitor", subtitle: "Low-latency audio", systemImage: "figure.2.and.child.holdinghands", status: .planned, info: "One-tap audio streaming to another device in the app. Local network preferred."),
            .init(title: "Pet Watcher", subtitle: "Motion + barks", systemImage: "pawprint.fill", status: .planned, info: "Detects motion in a zone and higher SPL spikes suggestive of barks; sends a clip and alert."),
            .init(title: "Doorbell / Knock", subtitle: "Detect door knocks", systemImage: "bell.circle.fill", status: .available, info: "Use sound + motion combo near door to detect knocks/rings and push an alert with timestamp."),
            .init(title: "Presence", subtitle: "Near-phone presence", systemImage: "dot.radiowaves.up.forward", status: .planned, info: "Estimates presence using on-device signals. Background Bluetooth/Wi-Fi scanning is limited on iOS; will work while app is active."),
            .init(title: "Light Level", subtitle: "Via camera analysis", systemImage: "lightbulb.fill", status: .available, info: "Approximates ambient light using the camera feed (iOS does not expose the ambient light sensor directly to apps).")
        ]
    }

    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                searchBar
                grid
            }
            .padding(.horizontal)
            .padding(.top, 16)
        }
        .navigationTitle("Functions")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Put Your Old Phone to Work")
                .font(.title2.bold())
            Text("Choose a function below to set up this device as a sensor, camera, or notifier. More coming soon.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search functions", text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var grid: some View {
        let filtered = items.filter { query.isEmpty ? true : ($0.title + $0.subtitle + $0.info).localizedCaseInsensitiveContains(query) }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(filtered) { item in
                NavigationLink {
                    FunctionDetailView(userUID: userUID, item: item)
                } label: {
                    FunctionCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FunctionCard: View {
    let item: FunctionsView.FunctionItem
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.systemImage)
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                statusBadge
            }
            Text(item.title)
                .font(.headline)
            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private var statusBadge: some View {
        switch item.status {
        case .available:
            Label("Available", systemImage: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green)
        case .planned:
            Label("Planned", systemImage: "clock.badge.checkmark")
                .font(.caption2).foregroundStyle(.orange)
        case .accessory:
            Label("Accessory", systemImage: "bolt.shield.fill")
                .font(.caption2).foregroundStyle(.blue)
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
    let battery: Int?
    let isListening: Bool
    let task: String?

    init(id: String, data: [String: Any]) {
        self.id = id
        self.model = data["model"] as? String ?? "Unknown"
        self.name = data["name"] as? String ?? ""
        self.bundleID = data["bundleID"] as? String ?? ""
        self.systemVersion = data["systemVersion"] as? String ?? ""
        self.isActive = data["isActive"] as? Bool ?? false
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        self.token = data["token"] as? String
        self.battery = data["battery"] as? Int
        self.isListening = data["isListening"] as? Bool ?? false
        self.task = data["task"] as? String
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
                HStack(spacing: 8) {
                    if let pct = device.battery {
                        Label("\(pct)%", systemImage: "battery.100")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if device.isListening, let t = device.task, !t.isEmpty {
                        Label(t, systemImage: "waveform.path.ecg")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
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

// MARK: - Function Detail + Mailbox + Dryer

struct FunctionDetailView: View {
    let userUID: String
    let item: FunctionsView.FunctionItem
    @State private var isEnabling = false
    @State private var enabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: item.systemImage).font(.system(size: 34, weight: .bold))
                    VStack(alignment: .leading) {
                        Text(item.title).font(.title2.bold())
                        Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Text(item.info)
                    .font(.body)

                Divider()

                // Generic enable flow
                VStack(alignment: .leading, spacing: 8) {
                    Text("Setup Preview").font(.headline)
                    Text("Tapping Enable will create a config document for \(item.title) under your user profile. You can wire the actual sensor/stream implementation later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    enableFunction()
                } label: {
                    if isEnabling {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label(enabled ? "Enabled" : "Enable \(item.title)", systemImage: enabled ? "checkmark.circle" : "play.circle")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isEnabling)

                // Mailbox specific UI
                if item.title == "Mailbox Notifier" {
                    Divider().padding(.top, 8)
                    MailboxNotifierSetupView()
                }

                // NEW: Dryer specific UI
                if item.title == "Dryer Notifier" {
                    Divider().padding(.top, 8)
                    DryerNotifierSetupView(userUID: userUID)
                }
            }
            .padding()
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func enableFunction() {
        guard !isEnabling, let uid = Auth.auth().currentUser?.uid else { return }
        isEnabling = true
        let db = Firestore.firestore()
        let doc = db.collection("users").document(uid).collection("functions").document(item.title)
        let payload: [String: Any] = [
            "title": item.title,
            "subtitle": item.subtitle,
            "status": "enabled",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        doc.setData(payload, merge: true) { _ in
            isEnabling = false
            enabled = true
        }
    }
}

// MARK: - Mailbox Notifier: manual settings + 30s placement timer
struct MailboxNotifierSetupView: View {
    // User confirms they’ve manually done these in iOS Settings / physically
    @State private var allowNotifications = false
    @State private var disableAutoLock = false
    @State private var keepPluggedIn = false
    @State private var placePhoneFaceUp = false

    // Timer & state
    @State private var hasStartedTimer = false
    @State private var countdown = 30
    @State private var isArmed = false

    // One-second ticker for countdown
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before You Begin")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                ChecklistRow(isOn: $allowNotifications,
                             title: "Allow Notifications",
                             subtitle: "Settings → Notifications → Allow for this app.")
                ChecklistRow(isOn: $disableAutoLock,
                             title: "Disable Auto-Lock (Temporarily)",
                             subtitle: "Settings → Display & Brightness → Auto-Lock → set to a longer duration while testing.")
                ChecklistRow(isOn: $keepPluggedIn,
                             title: "Keep Device Plugged In",
                             subtitle: "Recommended for longer sessions.")
                ChecklistRow(isOn: $placePhoneFaceUp,
                             title: "Place Phone Face-Up in Mailbox",
                             subtitle: "Stable position, not touching moving parts.")
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Start timer
            if !hasStartedTimer && !isArmed {
                Button {
                    hasStartedTimer = true
                    countdown = 30
                } label: {
                    Label("I'm ready — start 30s placement timer", systemImage: "timer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allRequiredChecks)
                .animation(.easeInOut, value: allRequiredChecks)
            }

            // Countdown view
            if hasStartedTimer && !isArmed {
                VStack(spacing: 8) {
                    Text("Place the phone in the mailbox now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(countdown)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Listening will begin after the timer finishes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .onReceive(ticker) { _ in
                    guard hasStartedTimer, countdown > 0 else { return }
                    countdown -= 1
                    if countdown == 0 {
                        // No backend call here—just flip UI state to “armed”
                        isArmed = true
                        hasStartedTimer = false
                    }
                }
            }

            // Armed state
            if isArmed {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Mailbox Notifier armed", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("You can leave this phone in the mailbox. (No detection logic here yet—just UI state.)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(role: .destructive) {
                            isArmed = false
                        } label: {
                            Label("Stop Listening", systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var allRequiredChecks: Bool {
        // Keep this minimal & manual; add/remove requirements as you like
        allowNotifications && disableAutoLock && keepPluggedIn && placePhoneFaceUp
    }
}

// MARK: - Dryer Notifier (CoreMotion-based vibration detection)

/// Lightweight vibration detector using the accelerometer.
/// Battery-friendly: low rate, no camera, no screen requirement.
final class DryerVibrationDetector: ObservableObject {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    // Config
    private let updateInterval = 0.2       // 5 Hz
    private let alpha = 0.05               // EMA smoothing
    private let runningVarThreshold = 0.02 // "how shaky" = running
    private let startConfirmSeconds: TimeInterval = 4
    private let stopConfirmSeconds: TimeInterval = 25

    // State
    @Published var status: String = "idle"
    @Published var variance: Double = 0
    private var meanMag: Double = 1.0
    private var varMag: Double = 0
    private var initialized = false
    private var isRunningDryer = false
    private var lastAboveThreshold: Date?
    private var lastBelowThreshold: Date?

    var onDryerStarted: (() -> Void)?
    var onDryerStopped: (() -> Void)?

    func start() {
        guard motion.isAccelerometerAvailable else {
            status = "no accelerometer"
            return
        }
        if motion.isAccelerometerActive { return }

        status = "listening…"
        initialized = false
        isRunningDryer = false
        meanMag = 1.0
        varMag = 0
        variance = 0
        lastAboveThreshold = nil
        lastBelowThreshold = nil

        motion.accelerometerUpdateInterval = updateInterval
        queue.qualityOfService = .utility

        motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let d = data else { return }

            let x = d.acceleration.x
            let y = d.acceleration.y
            let z = d.acceleration.z
            let mag = sqrt(x*x + y*y + z*z) // includes gravity, we just look at shake around mean

            if !self.initialized {
                self.initialized = true
                self.meanMag = mag
                self.varMag = 0
            }

            // Exponential moving averages
            let diff = mag - self.meanMag
            self.meanMag += self.alpha * diff
            self.varMag += self.alpha * (diff * diff - self.varMag)

            let v = max(self.varMag, 0)
            DispatchQueue.main.async {
                self.variance = v
            }

            let threshold = self.runningVarThreshold
            let now = Date()

            if v >= threshold {
                self.lastAboveThreshold = now
            } else {
                self.lastBelowThreshold = now
            }

            if !self.isRunningDryer,
               let since = self.lastAboveThreshold,
               now.timeIntervalSince(since) >= self.startConfirmSeconds {
                self.isRunningDryer = true
                DispatchQueue.main.async {
                    self.status = "dryer running"
                    self.onDryerStarted?()
                }
            }

            if self.isRunningDryer,
               let since = self.lastBelowThreshold,
               now.timeIntervalSince(since) >= self.stopConfirmSeconds {
                self.isRunningDryer = false
                DispatchQueue.main.async {
                    self.status = "dryer stopped"
                    self.onDryerStopped?()
                }
                // we can optionally stop updates here for even more battery savings:
                // self.stop()
            }
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
        DispatchQueue.main.async {
            self.status = "stopped"
        }
    }
}

struct DryerNotifierSetupView: View {
    let userUID: String
    @StateObject private var detector = DryerVibrationDetector()

    @State private var allowNotifications = true
    @State private var disableAutoLock = true
    @State private var keepPluggedIn = true
    @State private var placeOnDryer = true

    @State private var isListening = false
    @State private var didDetectStart = false

    private let db = Firestore.firestore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dryer Setup")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                ChecklistRow(isOn: $allowNotifications,
                             title: "Allow Notifications",
                             subtitle: "Settings → Notifications → Allow for this app.")
                ChecklistRow(isOn: $disableAutoLock,
                             title: "Disable Auto-Lock (Temporarily)",
                             subtitle: "Settings → Display & Brightness → Auto-Lock → longer duration while testing.")
                ChecklistRow(isOn: $keepPluggedIn,
                             title: "Keep Device Plugged In",
                             subtitle: "Recommended for an entire dryer cycle.")
                ChecklistRow(isOn: $placeOnDryer,
                             title: "Place Phone Firmly on Dryer",
                             subtitle: "Flat, secure surface; doesn’t slide during vibration.")
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !isListening {
                Button {
                    startListening()
                } label: {
                    Label("I'm ready — start Dryer Notifier", systemImage: "washer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allChecks)
                .animation(.easeInOut, value: allChecks)
            }

            if isListening {
                VStack(alignment: .leading, spacing: 8) {
                    Label(didDetectStart ? "Dryer is on — listening for it to finish…" : "Waiting for dryer to start…",
                          systemImage: didDetectStart ? "waveform.badge.mic" : "washer")
                        .font(.headline)
                    Text("Variance: \(String(format: "%.4f", detector.variance))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Status: \(detector.status)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button(role: .destructive) {
                            stopListening()
                        } label: {
                            Label("Stop Listening", systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .onDisappear {
            if isListening {
                stopListening()
            }
        }
    }

    private var allChecks: Bool {
        allowNotifications && disableAutoLock && keepPluggedIn && placeOnDryer
    }

    private func startListening() {
        guard let authUID = Auth.auth().currentUser?.uid else { return }

        isListening = true
        didDetectStart = false
        UIApplication.shared.isIdleTimerDisabled = true

        // Mark this device as listening for "Dryer Notifier"
        DeviceHeartbeat.shared.setListening(true, task: "Dryer Notifier")

        detector.onDryerStarted = {
            if !didDetectStart {
                didDetectStart = true
                fireDryerNotification(uid: authUID, event: "started")
            }
        }

        detector.onDryerStopped = {
            fireDryerNotification(uid: authUID, event: "finished")
            stopListening()
        }

        detector.start()

        // Optional: record a Firestore flag that dryer listener is active for this user
        db.collection("users").document(authUID)
            .setData(["dryerListening": true], merge: true)
    }

    private func stopListening() {
        isListening = false
        UIApplication.shared.isIdleTimerDisabled = false
        detector.stop()
        DeviceHeartbeat.shared.setListening(false, task: nil)

        if let authUID = Auth.auth().currentUser?.uid {
            db.collection("users").document(authUID)
                .setData(["dryerListening": false], merge: true)
        }
    }

    private func fireDryerNotification(uid: String, event: String) {
        // Update Firestore state (e.g. for a Home view card later)
        let fields: [String: Any] = [
            "dryerRunning": (event == "started"),
            "dryerLastEvent": event,
            "dryerLastUpdatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid).setData(fields, merge: true)

        // Hit the unified Cloud Function to fan out FCM notifications.
        guard let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification") else { return }

        var title = ""
        var body = ""

        if event == "started" {
            title = "Dryer Notifier"
            body = "Your dryer is on — phone is listening."
        } else {
            title = "Dryer Notifier"
            body = "Your clothes are done. Dryer has stopped."
        }

        let payload: [String: Any] = [
            "userId": uid,
            "type": "dryer",
            "event": event,
            "title": title,
            "body": body
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req).resume()
    }
}

// MARK: - Device Heartbeat + ChecklistRow

final class DeviceHeartbeat {
    static let shared = DeviceHeartbeat()
    private init() {}
    private var timer: Timer?
    private var userUID: String = ""
    private var deviceID: String = ""
    private var isListening = false

    func start(userUID: String, deviceID: String) {
        self.userUID = userUID
        self.deviceID = deviceID

        UIDevice.current.isBatteryMonitoringEnabled = true
        postHeartbeat()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.postHeartbeat()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    func setListening(_ listening: Bool, task: String? = nil) {
        isListening = listening
        postHeartbeat(task: task)
    }

    private func postHeartbeat(task: String? = nil) {
        guard !userUID.isEmpty, !deviceID.isEmpty else { return }
        let db = Firestore.firestore()

        let level = max(0, min(1, UIDevice.current.batteryLevel)) // 0.0...1.0 (can be -1 if unknown)
        let batteryPct = level < 0 ? nil : Int((level * 100).rounded())

        var payload: [String: Any] = [
            "isActive": true,
            "updatedAt": FieldValue.serverTimestamp(),
            "isListening": isListening
        ]
        if let pct = batteryPct { payload["battery"] = pct }
        if let task = task { payload["task"] = task }

        db.collection("users").document(userUID)
          .collection("devices").document(deviceID)
          .setData(payload, merge: true)
    }
}

// Small reusable checklist row
private struct ChecklistRow: View {
    @Binding var isOn: Bool
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                isOn.toggle()
            } label: {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}
/*
import SwiftUI
import Firebase
import FirebaseMessaging
import UserNotifications
import AuthenticationServices
import CryptoKit

// MARK: - Single-file App Entry

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

                // NEW: Functions tab replaces the former Sensor tab
                FunctionsView(userUID: userUID)
                    .tabItem { Label("Functions", systemImage: "square.grid.2x2.fill") }

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

// MARK: - NEW: Functions (formerly Sensor)
struct FunctionsView: View {
    let userUID: String

    struct FunctionItem: Identifiable {
        enum Status { case available, planned, accessory }
        let id = UUID()
        let title: String
        let subtitle: String
        let systemImage: String
        let status: Status
        let info: String
    }

    private var items: [FunctionItem] {
        [
            .init(title: "Mailbox Notifier", subtitle: "Detect mail + push alerts", systemImage: "envelope.badge", status: .available, info: "Uses camera or motion heuristics near the mailbox to detect openings. Sends push to all signed-in devices via FCM."),
            .init(title: "Dryer Notifier", subtitle: "Know when laundry finishes", systemImage: "washer", status: .available, info: "Place this phone on the dryer. It detects vibration, lets you know when the dryer starts, and notifies you again when your clothes are done."),
            .init(title: "Camera", subtitle: "Live view / snapshots", systemImage: "camera.viewfinder", status: .available, info: "Turns your old phone into a simple IP-style viewer within the app (no background server). Supports periodic snapshots to Firestore Storage (future)."),
            .init(title: "Motion Sensor", subtitle: "Device motion / vibration", systemImage: "waveform.path.ecg", status: .available, info: "Uses CoreMotion accelerometer/gyroscope to detect movement, bumps, or door openings. Triggers on-threshold push notifications."),
            .init(title: "Sound Detector", subtitle: "Noise/knock detection", systemImage: "ear.badge.waveform", status: .available, info: "Microphone-based knock/clang/bark threshold detection. All processing on-device; only events are uploaded."),
            .init(title: "Time-lapse", subtitle: "Interval photos", systemImage: "timer", status: .planned, info: "Capture frames on an interval and build a time-lapse locally. Option to sync to cloud later."),
            .init(title: "QR / Barcode", subtitle: "Scan & log", systemImage: "qrcode.viewfinder", status: .available, info: "Use the camera to scan codes and log events (arrivals, packages)."),
            .init(title: "Dashcam", subtitle: "Auto-record while moving", systemImage: "car.rear.fill", status: .planned, info: "Records when motion exceeds threshold and device is powered. Overwrites oldest clips (ring buffer)."),
            .init(title: "Baby Monitor", subtitle: "Low-latency audio", systemImage: "figure.2.and.child.holdinghands", status: .planned, info: "One-tap audio streaming to another device in the app. Local network preferred."),
            .init(title: "Pet Watcher", subtitle: "Motion + barks", systemImage: "pawprint.fill", status: .planned, info: "Detects motion in a zone and higher SPL spikes suggestive of barks; sends a clip and alert."),
            .init(title: "Doorbell / Knock", subtitle: "Detect door knocks", systemImage: "bell.circle.fill", status: .available, info: "Use sound + motion combo near door to detect knocks/rings and push an alert with timestamp."),
            .init(title: "Presence", subtitle: "Near-phone presence", systemImage: "dot.radiowaves.up.forward", status: .planned, info: "Estimates presence using on-device signals. Background Bluetooth/Wi-Fi scanning is limited on iOS; will work while app is active."),
            .init(title: "Light Level", subtitle: "Via camera analysis", systemImage: "lightbulb.fill", status: .available, info: "Approximates ambient light using the camera feed (iOS does not expose the ambient light sensor directly to apps).")
        ]
    }

    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                searchBar
                grid
            }
            .padding(.horizontal)
            .padding(.top, 16)
        }
        .navigationTitle("Functions")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Put Your Old Phone to Work")
                .font(.title2.bold())
            Text("Choose a function below to set up this device as a sensor, camera, or notifier. More coming soon.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search functions", text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var grid: some View {
        let filtered = items.filter { query.isEmpty ? true : ($0.title + $0.subtitle + $0.info).localizedCaseInsensitiveContains(query) }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(filtered) { item in
                NavigationLink {
                    FunctionDetailView(userUID: userUID, item: item)
                } label: {
                    FunctionCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FunctionCard: View {
    let item: FunctionsView.FunctionItem
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.systemImage)
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                statusBadge
            }
            Text(item.title)
                .font(.headline)
            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private var statusBadge: some View {
        switch item.status {
        case .available:
            Label("Available", systemImage: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green)
        case .planned:
            Label("Planned", systemImage: "clock.badge.checkmark")
                .font(.caption2).foregroundStyle(.orange)
        case .accessory:
            Label("Accessory", systemImage: "bolt.shield.fill")
                .font(.caption2).foregroundStyle(.blue)
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
    let battery: Int?
    let isListening: Bool
    let task: String?

    init(id: String, data: [String: Any]) {
        self.id = id
        self.model = data["model"] as? String ?? "Unknown"
        self.name = data["name"] as? String ?? ""
        self.bundleID = data["bundleID"] as? String ?? ""
        self.systemVersion = data["systemVersion"] as? String ?? ""
        self.isActive = data["isActive"] as? Bool ?? false
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        self.token = data["token"] as? String
        self.battery = data["battery"] as? Int
        self.isListening = data["isListening"] as? Bool ?? false
        self.task = data["task"] as? String
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
                HStack(spacing: 8) {
                    if let pct = device.battery {
                        Label("\(pct)%", systemImage: "battery.100")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if device.isListening, let t = device.task, !t.isEmpty {
                        Label(t, systemImage: "waveform.path.ecg")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
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

// MARK: - Function Detail + Mailbox + Dryer

struct FunctionDetailView: View {
    let userUID: String
    let item: FunctionsView.FunctionItem
    @State private var isEnabling = false
    @State private var enabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: item.systemImage).font(.system(size: 34, weight: .bold))
                    VStack(alignment: .leading) {
                        Text(item.title).font(.title2.bold())
                        Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Text(item.info)
                    .font(.body)

                Divider()

                // Generic enable flow
                VStack(alignment: .leading, spacing: 8) {
                    Text("Setup Preview").font(.headline)
                    Text("Tapping Enable will create a config document for \(item.title) under your user profile. You can wire the actual sensor/stream implementation later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    enableFunction()
                } label: {
                    if isEnabling {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label(enabled ? "Enabled" : "Enable \(item.title)", systemImage: enabled ? "checkmark.circle" : "play.circle")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isEnabling)

                // Mailbox specific UI
                if item.title == "Mailbox Notifier" {
                    Divider().padding(.top, 8)
                    MailboxNotifierSetupView()
                }

                // NEW: Dryer specific UI
                if item.title == "Dryer Notifier" {
                    Divider().padding(.top, 8)
                    DryerNotifierSetupView(userUID: userUID)
                }
            }
            .padding()
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func enableFunction() {
        guard !isEnabling, let uid = Auth.auth().currentUser?.uid else { return }
        isEnabling = true
        let db = Firestore.firestore()
        let doc = db.collection("users").document(uid).collection("functions").document(item.title)
        let payload: [String: Any] = [
            "title": item.title,
            "subtitle": item.subtitle,
            "status": "enabled",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        doc.setData(payload, merge: true) { _ in
            isEnabling = false
            enabled = true
        }
    }
}

// MARK: - Mailbox Notifier: manual settings + 30s placement timer
struct MailboxNotifierSetupView: View {
    // User confirms they’ve manually done these in iOS Settings / physically
    @State private var allowNotifications = false
    @State private var disableAutoLock = false
    @State private var keepPluggedIn = false
    @State private var placePhoneFaceUp = false

    // Timer & state
    @State private var hasStartedTimer = false
    @State private var countdown = 30
    @State private var isArmed = false

    // One-second ticker for countdown
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before You Begin")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                ChecklistRow(isOn: $allowNotifications,
                             title: "Allow Notifications",
                             subtitle: "Settings → Notifications → Allow for this app.")
                ChecklistRow(isOn: $disableAutoLock,
                             title: "Disable Auto-Lock (Temporarily)",
                             subtitle: "Settings → Display & Brightness → Auto-Lock → set to a longer duration while testing.")
                ChecklistRow(isOn: $keepPluggedIn,
                             title: "Keep Device Plugged In",
                             subtitle: "Recommended for longer sessions.")
                ChecklistRow(isOn: $placePhoneFaceUp,
                             title: "Place Phone Face-Up in Mailbox",
                             subtitle: "Stable position, not touching moving parts.")
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Start timer
            if !hasStartedTimer && !isArmed {
                Button {
                    hasStartedTimer = true
                    countdown = 30
                } label: {
                    Label("I'm ready — start 30s placement timer", systemImage: "timer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allRequiredChecks)
                .animation(.easeInOut, value: allRequiredChecks)
            }

            // Countdown view
            if hasStartedTimer && !isArmed {
                VStack(spacing: 8) {
                    Text("Place the phone in the mailbox now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(countdown)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Listening will begin after the timer finishes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .onReceive(ticker) { _ in
                    guard hasStartedTimer, countdown > 0 else { return }
                    countdown -= 1
                    if countdown == 0 {
                        // No backend call here—just flip UI state to “armed”
                        isArmed = true
                        hasStartedTimer = false
                    }
                }
            }

            // Armed state
            if isArmed {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Mailbox Notifier armed", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("You can leave this phone in the mailbox. (No detection logic here yet—just UI state.)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(role: .destructive) {
                            isArmed = false
                        } label: {
                            Label("Stop Listening", systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var allRequiredChecks: Bool {
        // Keep this minimal & manual; add/remove requirements as you like
        allowNotifications && disableAutoLock && keepPluggedIn && placePhoneFaceUp
    }
}

// MARK: - Dryer Notifier (CoreMotion-based vibration detection)

import UIKit
import CoreMotion

/// Lightweight vibration detector using the accelerometer.
/// Battery-friendly: low rate, no camera, no screen requirement.
final class DryerVibrationDetector: ObservableObject {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    // Config
    private let updateInterval = 0.2       // 5 Hz
    private let alpha = 0.05               // EMA smoothing
    private let runningVarThreshold = 0.02 // "how shaky" = running
    private let startConfirmSeconds: TimeInterval = 4
    private let stopConfirmSeconds: TimeInterval = 25

    // State
    @Published var status: String = "idle"
    @Published var variance: Double = 0
    private var meanMag: Double = 1.0
    private var varMag: Double = 0
    private var initialized = false
    private var isRunningDryer = false
    private var lastAboveThreshold: Date?
    private var lastBelowThreshold: Date?

    var onDryerStarted: (() -> Void)?
    var onDryerStopped: (() -> Void)?

    func start() {
        guard motion.isAccelerometerAvailable else {
            status = "no accelerometer"
            return
        }
        if motion.isAccelerometerActive { return }

        status = "listening…"
        initialized = false
        isRunningDryer = false
        meanMag = 1.0
        varMag = 0
        variance = 0
        lastAboveThreshold = nil
        lastBelowThreshold = nil

        motion.accelerometerUpdateInterval = updateInterval
        queue.qualityOfService = .utility

        motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let d = data else { return }

            let x = d.acceleration.x
            let y = d.acceleration.y
            let z = d.acceleration.z
            let mag = sqrt(x*x + y*y + z*z) // includes gravity, we just look at shake around mean

            if !self.initialized {
                self.initialized = true
                self.meanMag = mag
                self.varMag = 0
            }

            // Exponential moving averages
            let diff = mag - self.meanMag
            self.meanMag += self.alpha * diff
            self.varMag += self.alpha * (diff * diff - self.varMag)

            let v = max(self.varMag, 0)
            DispatchQueue.main.async {
                self.variance = v
            }

            let threshold = self.runningVarThreshold
            let now = Date()

            if v >= threshold {
                self.lastAboveThreshold = now
            } else {
                self.lastBelowThreshold = now
            }

            if !self.isRunningDryer,
               let since = self.lastAboveThreshold,
               now.timeIntervalSince(since) >= self.startConfirmSeconds {
                self.isRunningDryer = true
                DispatchQueue.main.async {
                    self.status = "dryer running"
                    self.onDryerStarted?()
                }
            }

            if self.isRunningDryer,
               let since = self.lastBelowThreshold,
               now.timeIntervalSince(since) >= self.stopConfirmSeconds {
                self.isRunningDryer = false
                DispatchQueue.main.async {
                    self.status = "dryer stopped"
                    self.onDryerStopped?()
                }
                // we can optionally stop updates here for even more battery savings:
                // self.stop()
            }
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
        DispatchQueue.main.async {
            self.status = "stopped"
        }
    }
}

struct DryerNotifierSetupView: View {
    let userUID: String
    @StateObject private var detector = DryerVibrationDetector()

    @State private var allowNotifications = true
    @State private var disableAutoLock = true
    @State private var keepPluggedIn = true
    @State private var placeOnDryer = true

    @State private var isListening = false
    @State private var didDetectStart = false

    private let db = Firestore.firestore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dryer Setup")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                ChecklistRow(isOn: $allowNotifications,
                             title: "Allow Notifications",
                             subtitle: "Settings → Notifications → Allow for this app.")
                ChecklistRow(isOn: $disableAutoLock,
                             title: "Disable Auto-Lock (Temporarily)",
                             subtitle: "Settings → Display & Brightness → Auto-Lock → longer duration while testing.")
                ChecklistRow(isOn: $keepPluggedIn,
                             title: "Keep Device Plugged In",
                             subtitle: "Recommended for an entire dryer cycle.")
                ChecklistRow(isOn: $placeOnDryer,
                             title: "Place Phone Firmly on Dryer",
                             subtitle: "Flat, secure surface; doesn’t slide during vibration.")
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !isListening {
                Button {
                    startListening()
                } label: {
                    Label("I'm ready — start Dryer Notifier", systemImage: "washer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allChecks)
                .animation(.easeInOut, value: allChecks)
            }

            if isListening {
                VStack(alignment: .leading, spacing: 8) {
                    Label(didDetectStart ? "Dryer is on — listening for it to finish…" : "Waiting for dryer to start…",
                          systemImage: didDetectStart ? "waveform.badge.mic" : "washer")
                        .font(.headline)
                    Text("Variance: \(String(format: "%.4f", detector.variance))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Status: \(detector.status)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button(role: .destructive) {
                            stopListening()
                        } label: {
                            Label("Stop Listening", systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .onDisappear {
            if isListening {
                stopListening()
            }
        }
    }

    private var allChecks: Bool {
        allowNotifications && disableAutoLock && keepPluggedIn && placeOnDryer
    }

    private func startListening() {
        guard let authUID = Auth.auth().currentUser?.uid else { return }

        isListening = true
        didDetectStart = false
        UIApplication.shared.isIdleTimerDisabled = true

        // Mark this device as listening for "Dryer Notifier"
        DeviceHeartbeat.shared.setListening(true, task: "Dryer Notifier")

        detector.onDryerStarted = {
            if !didDetectStart {
                didDetectStart = true
                fireDryerNotification(uid: authUID, event: "started")
            }
        }

        detector.onDryerStopped = {
            fireDryerNotification(uid: authUID, event: "finished")
            stopListening()
        }

        detector.start()

        // Optional: record a Firestore flag that dryer listener is active for this user
        db.collection("users").document(authUID)
            .setData(["dryerListening": true], merge: true)
    }

    private func stopListening() {
        isListening = false
        UIApplication.shared.isIdleTimerDisabled = false
        detector.stop()
        DeviceHeartbeat.shared.setListening(false, task: nil)

        if let authUID = Auth.auth().currentUser?.uid {
            db.collection("users").document(authUID)
                .setData(["dryerListening": false], merge: true)
        }
    }

    private func fireDryerNotification(uid: String, event: String) {
        // Update Firestore state (e.g. for a Home view card later)
        let fields: [String: Any] = [
            "dryerRunning": (event == "started"),
            "dryerLastEvent": event,
            "dryerLastUpdatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid).setData(fields, merge: true)

        // Hit a Cloud Function to fan out FCM notifications.
        // Implement this in your backend similar to sendMailNotification.
        guard let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendDryerNotification") else { return }

        var title = ""
        var body = ""

        if event == "started" {
            title = "Dryer Notifier"
            body = "Your dryer is on — phone is listening."
        } else {
            title = "Dryer Notifier"
            body = "Your clothes are done. Dryer has stopped."
        }

        let payload: [String: Any] = [
            "userId": uid,
            "event": event,
            "title": title,
            "body": body
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req).resume()
    }
}

// MARK: - Device Heartbeat + ChecklistRow

final class DeviceHeartbeat {
    static let shared = DeviceHeartbeat()
    private init() {}
    private var timer: Timer?
    private var userUID: String = ""
    private var deviceID: String = ""
    private var isListening = false

    func start(userUID: String, deviceID: String) {
        self.userUID = userUID
        self.deviceID = deviceID

        UIDevice.current.isBatteryMonitoringEnabled = true
        postHeartbeat()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.postHeartbeat()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    func setListening(_ listening: Bool, task: String? = nil) {
        isListening = listening
        postHeartbeat(task: task)
    }

    private func postHeartbeat(task: String? = nil) {
        guard !userUID.isEmpty, !deviceID.isEmpty else { return }
        let db = Firestore.firestore()

        let level = max(0, min(1, UIDevice.current.batteryLevel)) // 0.0...1.0 (can be -1 if unknown)
        let batteryPct = level < 0 ? nil : Int((level * 100).rounded())

        var payload: [String: Any] = [
            "isActive": true,
            "updatedAt": FieldValue.serverTimestamp(),
            "isListening": isListening
        ]
        if let pct = batteryPct { payload["battery"] = pct }
        if let task = task { payload["task"] = task }

        db.collection("users").document(userUID)
          .collection("devices").document(deviceID)
          .setData(payload, merge: true)
    }
}

// Small reusable checklist row
private struct ChecklistRow: View {
    @Binding var isOn: Bool
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                isOn.toggle()
            } label: {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

*/
/*
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
 
 // NEW: Functions tab replaces the former Sensor tab
 FunctionsView(userUID: userUID)
 .tabItem { Label("Functions", systemImage: "square.grid.2x2.fill") }
 
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
 
 // MARK: - NEW: Functions (formerly Sensor)
 struct FunctionsView: View {
 let userUID: String
 
 struct FunctionItem: Identifiable {
 enum Status { case available, planned, accessory }
 let id = UUID()
 let title: String
 let subtitle: String
 let systemImage: String
 let status: Status
 let info: String
 }
 
 private var items: [FunctionItem] {
 [
 .init(title: "Mailbox Notifier", subtitle: "Detect mail + push alerts", systemImage: "envelope.badge", status: .available, info: "Uses camera or motion heuristics near the mailbox to detect openings. Sends push to all signed-in devices via FCM."),
 .init(title: "Camera", subtitle: "Live view / snapshots", systemImage: "camera.viewfinder", status: .available, info: "Turns your old phone into a simple IP-style viewer within the app (no background server). Supports periodic snapshots to Firestore Storage (future)."),
 .init(title: "Motion Sensor", subtitle: "Device motion / vibration", systemImage: "waveform.path.ecg", status: .available, info: "Uses CoreMotion accelerometer/gyroscope to detect movement, bumps, or door openings. Triggers on-threshold push notifications."),
 .init(title: "Sound Detector", subtitle: "Noise/knock detection", systemImage: "ear.badge.waveform", status: .available, info: "Microphone-based knock/clang/bark threshold detection. All processing on-device; only events are uploaded."),
 .init(title: "Time‑lapse", subtitle: "Interval photos", systemImage: "timer", status: .planned, info: "Capture frames on an interval and build a time‑lapse locally. Option to sync to cloud later."),
 .init(title: "QR / Barcode", subtitle: "Scan & log", systemImage: "qrcode.viewfinder", status: .available, info: "Use the camera to scan codes and log events (arrivals, packages)."),
 .init(title: "Dashcam", subtitle: "Auto‑record while moving", systemImage: "car.rear.fill", status: .planned, info: "Records when motion exceeds threshold and device is powered. Overwrites oldest clips (ring buffer)."),
 .init(title: "Baby Monitor", subtitle: "Low‑latency audio", systemImage: "figure.2.and.child.holdinghands", status: .planned, info: "One‑tap audio streaming to another device in the app. Local network preferred."),
 .init(title: "Pet Watcher", subtitle: "Motion + barks", systemImage: "pawprint.fill", status: .planned, info: "Detects motion in a zone and higher SPL spikes suggestive of barks; sends a clip and alert."),
 .init(title: "Doorbell / Knock", subtitle: "Detect door knocks", systemImage: "bell.circle.fill", status: .available, info: "Use sound + motion combo near door to detect knocks/rings and push an alert with timestamp."),
 .init(title: "Presence", subtitle: "Near‑phone presence", systemImage: "dot.radiowaves.up.forward", status: .planned, info: "Estimates presence using on‑device signals. Background Bluetooth/Wi‑Fi scanning is limited on iOS; will work while app is active."),
 .init(title: "Light Level", subtitle: "Via camera analysis", systemImage: "lightbulb.fill", status: .available, info: "Approximates ambient light using the camera feed (iOS does not expose the ambient light sensor directly to apps).")
 ]
 }
 
 @State private var query = ""
 
 var body: some View {
 ScrollView {
 VStack(alignment: .leading, spacing: 16) {
 header
 searchBar
 grid
 }
 .padding(.horizontal)
 .padding(.top, 16)
 }
 .navigationTitle("Functions")
 }
 
 private var header: some View {
 VStack(alignment: .leading, spacing: 6) {
 Text("Put Your Old Phone to Work")
 .font(.title2.bold())
 Text("Choose a function below to set up this device as a sensor, camera, or notifier. More coming soon.")
 .font(.subheadline)
 .foregroundStyle(.secondary)
 }
 }
 
 private var searchBar: some View {
 HStack {
 Image(systemName: "magnifyingglass")
 TextField("Search functions", text: $query)
 .textInputAutocapitalization(.never)
 .disableAutocorrection(true)
 }
 .padding(10)
 .background(.ultraThinMaterial)
 .clipShape(RoundedRectangle(cornerRadius: 12))
 }
 
 private var grid: some View {
 let filtered = items.filter { query.isEmpty ? true : ($0.title + $0.subtitle + $0.info).localizedCaseInsensitiveContains(query) }
 return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
 ForEach(filtered) { item in
 NavigationLink {
 FunctionDetailView(userUID: userUID, item: item)
 } label: {
 FunctionCard(item: item)
 }
 .buttonStyle(.plain)
 }
 }
 }
 }
 
 struct FunctionCard: View {
 let item: FunctionsView.FunctionItem
 var body: some View {
 VStack(alignment: .leading, spacing: 10) {
 HStack {
 Image(systemName: item.systemImage)
 .font(.system(size: 28, weight: .semibold))
 Spacer()
 statusBadge
 }
 Text(item.title)
 .font(.headline)
 Text(item.subtitle)
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 .padding(14)
 .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
 .background(.thinMaterial)
 .clipShape(RoundedRectangle(cornerRadius: 16))
 }
 
 @ViewBuilder private var statusBadge: some View {
 switch item.status {
 case .available:
 Label("Available", systemImage: "checkmark.circle.fill")
 .font(.caption2).foregroundStyle(.green)
 case .planned:
 Label("Planned", systemImage: "clock.badge.checkmark")
 .font(.caption2).foregroundStyle(.orange)
 case .accessory:
 Label("Accessory", systemImage: "bolt.shield.fill")
 .font(.caption2).foregroundStyle(.blue)
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
 
 
 
 
 struct FunctionDetailView: View {
 let userUID: String
 let item: FunctionsView.FunctionItem
 @State private var isEnabling = false
 @State private var enabled = false
 
 var body: some View {
 ScrollView {
 VStack(alignment: .leading, spacing: 16) {
 HStack(spacing: 12) {
 Image(systemName: item.systemImage).font(.system(size: 34, weight: .bold))
 VStack(alignment: .leading) {
 Text(item.title).font(.title2.bold())
 Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary)
 }
 Spacer()
 }
 
 Text(item.info)
 .font(.body)
 
 Divider()
 
 // Keep the generic enable flow (unchanged)
 VStack(alignment: .leading, spacing: 8) {
 Text("Setup Preview").font(.headline)
 Text("Tapping Enable will create a config document for \(item.title) under your user profile. You can wire the actual sensor/stream implementation later.")
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 
 Button {
 enableFunction()
 } label: {
 if isEnabling {
 ProgressView().frame(maxWidth: .infinity)
 } else {
 Label(enabled ? "Enabled" : "Enable \(item.title)", systemImage: enabled ? "checkmark.circle" : "play.circle")
 .frame(maxWidth: .infinity)
 }
 }
 .buttonStyle(.borderedProminent)
 .disabled(isEnabling)
 
 // NEW: Mailbox-specific UI (non-invasive; appears only for this item)
 if item.title == "Mailbox Notifier" {
 Divider().padding(.top, 8)
 MailboxNotifierSetupView()
 }
 }
 .padding()
 }
 .navigationTitle(item.title)
 .navigationBarTitleDisplayMode(.inline)
 }
 
 private func enableFunction() {
 guard !isEnabling, let uid = Auth.auth().currentUser?.uid else { return }
 isEnabling = true
 let db = Firestore.firestore()
 let doc = db.collection("users").document(uid).collection("functions").document(item.title)
 let payload: [String: Any] = [
 "title": item.title,
 "subtitle": item.subtitle,
 "status": "enabled",
 "updatedAt": FieldValue.serverTimestamp()
 ]
 doc.setData(payload, merge: true) { _ in
 isEnabling = false
 enabled = true
 }
 }
 }
 
 // MARK: - Mailbox Notifier: manual settings + 30s placement timer
 struct MailboxNotifierSetupView: View {
 // User confirms they’ve manually done these in iOS Settings / physically
 @State private var allowNotifications = false
 @State private var disableAutoLock = false
 @State private var keepPluggedIn = false
 @State private var placePhoneFaceUp = false
 
 // Timer & state
 @State private var hasStartedTimer = false
 @State private var countdown = 30
 @State private var isArmed = false
 
 // One-second ticker for countdown
 private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
 
 var body: some View {
 VStack(alignment: .leading, spacing: 16) {
 Text("Before You Begin")
 .font(.headline)
 
 VStack(alignment: .leading, spacing: 10) {
 ChecklistRow(isOn: $allowNotifications,
 title: "Allow Notifications",
 subtitle: "Settings → Notifications → Allow for this app.")
 ChecklistRow(isOn: $disableAutoLock,
 title: "Disable Auto-Lock (Temporarily)",
 subtitle: "Settings → Display & Brightness → Auto-Lock → set to a longer duration while testing.")
 ChecklistRow(isOn: $keepPluggedIn,
 title: "Keep Device Plugged In",
 subtitle: "Recommended for longer sessions.")
 ChecklistRow(isOn: $placePhoneFaceUp,
 title: "Place Phone Face-Up in Mailbox",
 subtitle: "Stable position, not touching moving parts.")
 }
 .padding(12)
 .background(.ultraThinMaterial)
 .clipShape(RoundedRectangle(cornerRadius: 12))
 
 // Start timer
 if !hasStartedTimer && !isArmed {
 Button {
 hasStartedTimer = true
 countdown = 30
 } label: {
 Label("I'm ready — start 30s placement timer", systemImage: "timer")
 .frame(maxWidth: .infinity)
 }
 .buttonStyle(.borderedProminent)
 .disabled(!allRequiredChecks)
 .animation(.easeInOut, value: allRequiredChecks)
 }
 
 // Countdown view
 if hasStartedTimer && !isArmed {
 VStack(spacing: 8) {
 Text("Place the phone in the mailbox now.")
 .font(.subheadline)
 .foregroundStyle(.secondary)
 Text("\(countdown)")
 .font(.system(size: 48, weight: .bold, design: .rounded))
 .monospacedDigit()
 Text("Listening will begin after the timer finishes.")
 .font(.footnote)
 .foregroundStyle(.secondary)
 }
 .frame(maxWidth: .infinity)
 .padding()
 .background(.thinMaterial)
 .clipShape(RoundedRectangle(cornerRadius: 14))
 .onReceive(ticker) { _ in
 guard hasStartedTimer, countdown > 0 else { return }
 countdown -= 1
 if countdown == 0 {
 // No backend call here—just flip UI state to “armed”
 isArmed = true
 hasStartedTimer = false
 }
 }
 }
 
 // Armed state
 if isArmed {
 VStack(alignment: .leading, spacing: 8) {
 Label("Mailbox Notifier armed", systemImage: "checkmark.seal.fill")
 .font(.headline)
 .foregroundStyle(.green)
 Text("You can leave this phone in the mailbox. (No detection logic here yet—just UI state.)")
 .font(.footnote)
 .foregroundStyle(.secondary)
 HStack {
 Button(role: .destructive) {
 isArmed = false
 } label: {
 Label("Stop Listening", systemImage: "stop.circle")
 }
 .buttonStyle(.bordered)
 
 Spacer()
 }
 }
 .padding()
 .background(.thinMaterial)
 .clipShape(RoundedRectangle(cornerRadius: 14))
 }
 }
 }
 
 private var allRequiredChecks: Bool {
 // Keep this minimal & manual; add/remove requirements as you like
 allowNotifications && disableAutoLock && keepPluggedIn && placePhoneFaceUp
 }
 }
 
 // Small reusable checklist row
 private struct ChecklistRow: View {
 @Binding var isOn: Bool
 let title: String
 let subtitle: String
 
 var body: some View {
 HStack(alignment: .top, spacing: 10) {
 Button {
 isOn.toggle()
 } label: {
 Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
 .font(.title3)
 .foregroundStyle(isOn ? .green : .secondary)
 }
 .buttonStyle(.plain)
 
 VStack(alignment: .leading, spacing: 2) {
 Text(title).font(.subheadline.weight(.semibold))
 Text(subtitle).font(.caption).foregroundStyle(.secondary)
 }
 Spacer()
 }
 .contentShape(Rectangle())
 .onTapGesture { isOn.toggle() }
 }
 }
 */

