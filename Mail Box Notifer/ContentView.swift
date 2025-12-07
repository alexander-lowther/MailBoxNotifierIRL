
 import SwiftUI
 import Firebase
 import FirebaseMessaging
 import UserNotifications
 import AuthenticationServices
 import CryptoKit
 import UIKit
 import CoreMotion
 import AVFoundation
 import FirebaseStorage
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
 .frame(height: 52).clipShape(RoundedRectangle(cornerRadius: 12))
 .padding(.horizontal)
 
 if let e = errorMessage {
 Text(e).font(.footnote).foregroundStyle(.red).padding(.horizontal)
 }
 Spacer()
 }
 .background(
 LinearGradient(colors: [.blue.opacity(0.08), .clear],
 startPoint: .top,
 endPoint: .bottom)
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
struct SecurityCameraViewerView: View {
    let cameraOwnerUID: String   // UID of the user whose camera this is (can be your own)
    let cameraDeviceID: String   // identifierForVendor() of the camera phone
    let title: String
    
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var lastError: String?
    
    // NEW: full-screen toggle
    @State private var showFullScreen = false
    
    // more frequent polling for a "live feed" feel
    private let refreshTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 8) {
            if let img = image {
                // tappable image to go full-screen
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .cornerRadius(12)
                    .overlay(alignment: .topLeading) {
                        if isLoading {
                            ProgressView()
                                .padding(8)
                        }
                    }
                    .onTapGesture {
                        showFullScreen = true
                    }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.9))
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Waiting for camera frames…")
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.footnote)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 260)
            }
            
            if let err = lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            // Explicit button for full-screen as well
            if image != nil {
                Button {
                    showFullScreen = true
                } label: {
                    Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadFrame()
        }
        .onReceive(refreshTimer) { _ in
            loadFrame()
        }
        // FULL-SCREEN COVER
        .fullScreenCover(isPresented: $showFullScreen) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        .ignoresSafeArea()
                } else {
                    ProgressView()
                        .tint(.white)
                }
                
                Button {
                    showFullScreen = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .padding()
                }
            }
        }
    }
    
    private func loadFrame() {
        isLoading = true
        lastError = nil
        
        let path = "securityCameras/\(cameraOwnerUID)/\(cameraDeviceID)/latest.jpg"
        let ref = Storage.storage().reference().child(path)
        
        // limit size to keep things zippy
        ref.getData(maxSize: 2 * 1024 * 1024) { data, error in
            isLoading = false
            if let error = error as NSError? {
                // ignore "object not found" early on
                if error.domain == StorageErrorDomain,
                   StorageErrorCode(rawValue: error.code) == .objectNotFound {
                    return
                }
                lastError = error.localizedDescription
                return
            }
            guard let data = data, let img = UIImage(data: data) else { return }
            image = img
        }
    }
}
struct HomeView: View {
    let userUID: String
    @State private var mailDetected = false
    @State private var errorMessage: String?
    @State private var activeTasksSummary: String = ""
    @State private var activeCameraDeviceID: String?
    @State private var activeCameraDeviceName: String?
    private let db = Firestore.firestore()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                
                activeTaskSection
                
                if let err = errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
                
                Spacer(minLength: 24)
            }
            .padding(.top, 16)
        }
        .navigationTitle("Home")
        .onAppear {
            listenForMail()
            subscribeActiveTask()
        }
    }
    
    // MARK: - Active Task Card
    
    private var activeTaskSection: some View {
        Group {
            if let cameraID = activeCameraDeviceID {
                NavigationLink {
                    SecurityCameraViewerView(
                        cameraOwnerUID: userUID,
                        cameraDeviceID: cameraID,
                        title: activeCameraDeviceName ?? "Security Camera"
                    )
                } label: {
                    activeTaskCard
                }
                .buttonStyle(.plain)
            } else {
                activeTaskCard
            }
        }
    }
    
    private var activeTaskCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: activeTasksSummary.isEmpty ? "pause.circle" : "waveform")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(activeTasksSummary.isEmpty ? .secondary : .primary)
                Text(activeTasksSummary.isEmpty ? "No active tasks" : activeTasksSummary)
                    .font(.headline)
                Spacer()
            }
            if activeTasksSummary.isEmpty {
                Text("Start a function in the Functions tab (Light Change, Vibration, Sound, Presence, Power Loss, Security Camera) to begin listening.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if activeCameraDeviceID != nil {
                Text("Tap to view the live camera feed from this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("This device is currently listening. You can stop it from the active Function screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
    
    // MARK: - Firestore: Mail + Active Tasks
    
    func resetMailFlag() {
        db.collection("users").document(userUID)
            .updateData(["mailDetected": false]) { error in
                if let error = error {
                    errorMessage = "Failed to reset: \(error.localizedDescription)"
                } else {
                    mailDetected = false
                }
            }
    }
    
    func listenForMail() {
        db.collection("users").document(userUID)
            .addSnapshotListener { snap, _ in
                guard let data = snap?.data(),
                      let detected = data["mailDetected"] as? Bool else { return }
                mailDetected = detected
            }
    }
    
    func subscribeActiveTask() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(uid)
            .collection("devices")
            .whereField("isListening", isEqualTo: true)
            .addSnapshotListener { snap, _ in
                guard let docs = snap?.documents else {
                    activeTasksSummary = ""
                    activeCameraDeviceID = nil
                    activeCameraDeviceName = nil
                    return
                }
                
                if docs.isEmpty {
                    activeTasksSummary = ""
                    activeCameraDeviceID = nil
                    activeCameraDeviceName = nil
                    return
                }
                
                // Prefer a security camera task if one exists
                if let camDoc = docs.first(where: {
                    let task = $0.data()["task"] as? String ?? ""
                    return task.contains("Security Camera")
                }) {
                    let data = camDoc.data()
                    let task = data["task"] as? String ?? "Security Camera"
                    let name = data["name"] as? String ?? "a device"
                    activeTasksSummary = "Security Camera active on \(name)"
                    activeCameraDeviceID = camDoc.documentID
                    activeCameraDeviceName = name
                } else if let first = docs.first {
                    let data = first.data()
                    let task = data["task"] as? String ?? ""
                    if !task.isEmpty {
                        activeTasksSummary = "Listening: \(task)"
                    } else {
                        activeTasksSummary = ""
                    }
                    activeCameraDeviceID = nil
                    activeCameraDeviceName = nil
                } else {
                    activeTasksSummary = ""
                    activeCameraDeviceID = nil
                    activeCameraDeviceName = nil
                }
            }
    }
}

 // MARK: - Functions
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
            .init(
                title: "Mailbox Notifier",
                subtitle: "Detect mail / light change",
                systemImage: "envelope.badge",
                status: .available,
                info: "Uses screen auto-brightness change (no camera) to detect openings or light changes. Sends push to all signed-in devices via FCM."
            ),
            .init(
                title: "Air Pressure",
                subtitle: "Detect pressure changes",
                systemImage: "gauge",
                status: .available,
                info: "Uses the device’s barometer (when available) to detect air pressure changes. Useful for detecting doors/windows opening in a sealed space or other rapid environment changes."
            ),
            .init(
                title: "Camera",
                subtitle: "Live viewer between devices",
                systemImage: "camera.viewfinder",
                status: .available,
                info: "Turn this phone into a simple security camera. It uploads lightweight frames so other signed-in devices can view a live feed."
            ),

            .init(
                title: "Vibration Sensor",
                subtitle: "Detect motion / vibration",
                systemImage: "waveform.path.ecg",
                status: .available,
                info: "Use the accelerometer to detect vibration from appliances, tools, vehicles, footsteps, or other movement. Configure a custom notification for any spike."
            ),
            .init(
                title: "Sound Sensor",
                subtitle: "Noise / knock detection",
                systemImage: "ear.badge.waveform",
                status: .available,
                info: "Listen for sound spikes (knocks, alarms, machinery, etc.). All audio stays on-device; only events and alerts are sent."
            ),
            .init(
                title: "Presence",
                subtitle: "Sense nearby activity",
                systemImage: "dot.radiowaves.up.forward",
                status: .available,
                info: "Use subtle device motion to infer nearby activity while the app is active. Great for quick “someone is around this area” pings."
            ),
            .init(
                title: "Time-lapse",
                subtitle: "Interval photos",
                systemImage: "timer",
                status: .planned,
                info: "Capture frames on an interval and build a time-lapse locally. Option to sync to cloud later."
            ),
            .init(
                title: "Magnetism",
                subtitle: "Detect magnets / metal nearby",
                systemImage: "magnet.fill",
                status: .available,
                info: "Uses the device’s magnetometer to detect magnetic field changes. Useful for alerting when a magnet, metal object, or door with a magnet moves near this phone."
            ),
            .init(
                title: "Level Sensor",
                subtitle: "Notify on tilt angle",
                systemImage: "triangle.lefthalf.filled",
                status: .available,
                info: "Use the device’s motion sensors to trigger a notification when the phone tilts past a target angle (e.g. 45°)."
            ),
            .init(
                title: "Power Loss",
                subtitle: "Detect charger unplug / restore",
                systemImage: "bolt.slash.circle",
                status: .available,
                info: "Monitors this device’s charging state. Get notified when power is lost or restored, e.g., a tripped breaker or someone unplugging the phone."
            ),
            .init(
                title: "Multi Sense",
                subtitle: "Combine multiple sensors",
                systemImage: "waveform.badge.mic",
                status: .planned,
                info: "A combined mode that can run multiple sensors (sound, vibration, presence) at once on a single device. Logic coming in a future update."
            )
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
            Text("Choose a function to turn this device into a sensor or notifier. You can create your own use cases for each one.")
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
        let filtered = items.filter {
            query.isEmpty
            ? true
            : ($0.title + $0.subtitle + $0.info).localizedCaseInsensitiveContains(query)
        }
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
    
    // UI-only name so we don't change any underlying logic / Firestore keys.
    private var displayTitle: String {
        item.title == "Mailbox Notifier" ? "Light Change" : item.title
    }
    
    private var displaySubtitle: String {
        if item.title == "Mailbox Notifier" {
            return "Screen brightness / light change"
        }
        return item.subtitle
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.systemImage)
                    .font(.system(size: 28, weight: .semibold))
                Spacer()
                statusBadge
            }
            Text(displayTitle)
                .font(.headline)
            Text(displaySubtitle)
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
 /*
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
 */

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
    let batteryState: String?
    let isPluggedIn: Bool?
    let lowPowerMode: Bool?
    
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
        self.batteryState = data["batteryState"] as? String
        self.isPluggedIn = data["isPluggedIn"] as? Bool
        self.lowPowerMode = data["lowPowerMode"] as? Bool
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
 HStack {
 Text(device.name.isEmpty ? device.model : device.name)
 .font(.headline)
 if let pct = device.battery {
 Text("· \(pct)%")
 .font(.caption)
 .foregroundStyle(pct <= 15 ? .red : .secondary)
 }
 }
 Text(device.id).font(.caption2).foregroundStyle(.secondary)
     
     
     HStack(spacing: 6) {
         if !device.model.isEmpty && device.model != "Unknown" {
             Text(device.model)
                 .font(.caption)
                 .foregroundStyle(.secondary)
         }
         if !device.systemVersion.isEmpty {
             Text(device.model.isEmpty || device.model == "Unknown" ? "iOS \(device.systemVersion)" : "· iOS \(device.systemVersion)")
                 .font(.caption)
                 .foregroundStyle(.secondary)
         }
         if !device.bundleID.isEmpty {
             Text("· \(device.bundleID)")
                 .font(.caption)
                 .foregroundStyle(.secondary)
         }
     }

     
     
     
     
     
 if let updated = device.updatedAt {
 Text(updated, style: .relative)
 .font(.caption2).foregroundStyle(.secondary)
 }
 if device.isListening, let task = device.task, !task.isEmpty {
 Label("Listening: \(task)", systemImage: "ear.badge.waveform")
 .font(.caption).foregroundStyle(.green)
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
 Our mission is to make real-world detection simple and reliable using the devices you already own. Every signed-in device can detect events and receive notifications—no hubs, no wiring.
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
 Text(n.createdAt, style: .relative)
 .font(.caption2).foregroundStyle(.secondary)
 }.padding(.vertical, 4)
 }
 .listStyle(.insetGrouped)
 .navigationTitle("Notifications")
 .toolbar {
 ToolbarItem(placement: .navigationBarTrailing) {
 Button("Done") { dismiss() }
 }
 }
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
 
 func sha256(_ input: String) -> String {
 let inputData = Data(input.utf8)
 let hashed = SHA256.hash(data: inputData)
 return hashed.map { String(format: "%02x", $0) }.joined()
 }
 
 // MARK: - Function Config Models
struct MailboxNotifierConfig {
    var useCaseName: String
    var notificationTitle: String
    var notificationBody: String
}
 struct VibrationSensorConfig {
 let useCaseName: String
 let notificationTitle: String
 let notificationBody: String
 }
struct SecurityCameraConfig {
    var useCaseName: String
    var uploadIntervalSeconds: Double
}
struct AirPressureConfig {
    let useCaseName: String
    let notificationTitle: String
    let notificationBody: String
    let thresholdDelta: Double   // hPa (hectopascal) delta
}
struct LevelSensorConfig {
    let useCaseName: String
    let notificationTitle: String
    let notificationBody: String
    let targetAngle: Double
}
 struct SoundSensorConfig {
 let useCaseName: String
 let notificationTitle: String
 let notificationBody: String
 let threshold: Float
 }
struct MagnetSensorConfig {
    let useCaseName: String
    let notificationTitle: String
    let notificationBody: String
    let thresholdDelta: Double   // microtesla delta
}
struct PowerLossConfig {
    var useCaseName: String
    var pluggedInTitle: String
    var pluggedInBody: String
    var unpluggedTitle: String
    var unpluggedBody: String
}
 struct PresenceSensorConfig {
 let useCaseName: String
 let notificationTitle: String
 let notificationBody: String
 }
 
 // MARK: - Function Detail (Enable + Specialized Setup)
private struct Bullet: View {
    let title: String
    let detail: String?
    
    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let detail = detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
struct FunctionDetailView: View {
    let userUID: String
    let item: FunctionsView.FunctionItem
    
    
    // Renaming Mailbox Notifier → Light Change (UI only)
    private var displayTitle: String {
        item.title == "Mailbox Notifier" ? "Light Change" : item.title
    }
    
    private var displaySubtitle: String {
        if item.title == "Mailbox Notifier" {
            return "Detect changes in screen light"
        }
        return item.subtitle
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                // Header
                HStack(spacing: 12) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 34, weight: .bold))
                    VStack(alignment: .leading) {
                        Text(displayTitle).font(.title2.bold())
                        Text(displaySubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                
                Text(item.info)
                    .font(.body)
                
                Divider()
                /*
                 // Enable config document (same logic as before)
                 VStack(alignment: .leading, spacing: 8) {
                 Text("Setup Preview").font(.headline)
                 Text("Enabling creates or updates a configuration document for this function under your user profile.")
                 .font(.caption)
                 .foregroundStyle(.secondary)
                 }
                 
                 Button {
                 enableFunction()
                 } label: {
                 if isEnabling {
                 ProgressView().frame(maxWidth: .infinity)
                 } else {
                 Label(
                 enabled ? "Enabled" : "Enable \(displayTitle)",
                 systemImage: enabled ? "checkmark.circle" : "play.circle"
                 )
                 .frame(maxWidth: .infinity)
                 }
                 }
                 .buttonStyle(.borderedProminent)
                 .disabled(isEnabling)
                 */
                // MARK: — Correct Setup View Routing
                Divider().padding(.top, 8)
                
                if item.title == "Mailbox Notifier" {
                    MailboxNotifierSetupView()
                }
                else if item.title == "Vibration Sensor" {
                    VibrationSensorSetupView(functionTitle: item.title)
                }
                else if item.title == "Sound Sensor" {
                    SoundSensorSetupView(functionTitle: item.title)
                }
                else if item.title == "Presence" {
                    PresenceSensorSetupView(functionTitle: item.title)
                }
                else if item.title == "Power Loss" {
                    PowerLossSetupView(functionTitle: item.title)
                }
                
                else if item.title == "Camera" {
                    SecurityCameraSetupView(functionTitle: item.title)
                }
                else if item.title == "Level Sensor" {
                    LevelSensorSetupView(functionTitle: item.title)
                }
                else if item.title == "Magnetism" {
                    MagnetSensorSetupView(functionTitle: item.title)
                }
                else if item.title == "Air Pressure" {
                    AirPressureSensorSetupView(functionTitle: item.title)
                }
                // ❌ Removed unconditional PresenceSensorSetupView
                // This is what caused “Start Presence Sensor” to appear in multiple functions ☑ FIXED
            }
        }
        .padding()
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            registerFunctionDocument()
        }
    }
      
    
    
    
    
    
    private func registerFunctionDocument() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        let doc = db.collection("users").document(uid)
            .collection("functions").document(item.title)
        
        let payload: [String: Any] = [
            "title": item.title,
            "subtitle": item.subtitle,
            "status": "enabled", // or "activeDefinition" etc, up to you
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        doc.setData(payload, merge: true)
    }
}

struct AirPressureListeningView: View {
    let config: AirPressureConfig
    
    @State private var status: String = "calibrating…"
    @State private var baselinePressure: Double = 0   // hPa
    @State private var currentPressure: Double = 0    // hPa
    @State private var deltaPressure: Double = 0      // hPa
    @State private var lastTriggerAt: Date = .distantPast
    private let cooldown: TimeInterval = 10
    
    private let altimeter = CMAltimeter()
    
    private let db = Firestore.firestore()
    @AppStorage("userUID") private var userUID: String = ""
    private var deviceID: String { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "gauge")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(config.useCaseName)
                        .font(.title3.bold())
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            HStack(spacing: 12) {
                Tag("baseline: " + String(format: "%.1f hPa", baselinePressure))
                Tag("current: " + String(format: "%.1f hPa", currentPressure))
                Tag("Δ: " + String(format: "%.1f hPa", deltaPressure))
            }
            
            Text("This sensor uses the device’s barometer to detect air pressure changes. When the pressure shifts more than your threshold, we'll send your custom notification.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            
            Spacer()
            
            Button(role: .destructive) {
                stopListening()
            } label: {
                Label("Stop Listening", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Air Pressure")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            startSession()
        }
    }
    
    private func startSession() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            status = "barometer not available"
            return
        }
        
        if let uid = Auth.auth().currentUser?.uid {
            DeviceHeartbeat.shared.start(userUID: uid, deviceID: deviceID)
            DeviceHeartbeat.shared.setListening(true, task: config.useCaseName)
        }
        
        sendLifecycleNotification(starting: true)
        
        status = "calibrating…"
        baselinePressure = 0
        currentPressure = 0
        deltaPressure = 0
        
        altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { data, error in
            if let error = error {
                self.status = "error: \(error.localizedDescription)"
                return
            }
            guard let data = data else { return }
            
            // CMAltimeter pressure is in kilopascals (kPa). Convert to hPa (millibars) ×10.
            let kPa = data.pressure.doubleValue
            let hPa = kPa * 10.0
            
            if self.baselinePressure == 0 {
                self.baselinePressure = hPa
                self.currentPressure = hPa
                self.deltaPressure = 0
                self.status = "listening…"
            } else {
                self.currentPressure = hPa
                let delta = abs(hPa - self.baselinePressure)
                self.deltaPressure = delta
                
                let now = Date()
                if delta >= self.config.thresholdDelta,
                   now.timeIntervalSince(self.lastTriggerAt) >= self.cooldown {
                    self.lastTriggerAt = now
                    self.status = "pressure change detected"
                    self.firePressureEvent()
                } else {
                    self.status = "listening…"
                }
            }
        }
    }
    
    private func firePressureEvent() {
        guard !userUID.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(uid)
            .setData(["lastPressureEventAt": FieldValue.serverTimestamp()],
                     merge: true)
        
        if let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "userId": uid,
                "title": config.notificationTitle,
                "body": config.notificationBody
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: req).resume()
        }
    }
    
    private func sendLifecycleNotification(starting: Bool) {
        guard let uid = Auth.auth().currentUser?.uid,
              let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification")
        else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let title = starting
            ? "Started listening: \(config.useCaseName)"
            : "Stopped listening: \(config.useCaseName)"
        let body = starting
            ? "This device is now monitoring air pressure."
            : "This device stopped monitoring air pressure."
        
        let payload: [String: Any] = [
            "userId": uid,
            "title": title,
            "body": body
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: req).resume()
    }
    
    private func stopListening() {
        UIApplication.shared.isIdleTimerDisabled = false
        altimeter.stopRelativeAltitudeUpdates()
        if let uid = Auth.auth().currentUser?.uid {
            DeviceHeartbeat.shared.setListening(false)
            DeviceHeartbeat.shared.stop()
            Firestore.firestore()
                .collection("users").document(uid)
                .collection("devices").document(deviceID)
                .setData(["isListening": false], merge: true)
        }
        sendLifecycleNotification(starting: false)
        dismiss()
    }
}
struct SecurityCameraListeningView: View {
    let config: SecurityCameraConfig
    let functionTitle: String
    
    @StateObject private var streamer = SecurityCameraStreamer()
    @State private var status: String = "Starting…"
    
    private let db = Firestore.firestore()
    @AppStorage("userUID") private var userUID: String = ""
    private var deviceID: String { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(config.useCaseName)
                        .font(.title3.bold())
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            GeometryReader { geo in
                ZStack {
                    if let img = streamer.currentFrame {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .cornerRadius(16)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                        ProgressView()
                    }
                }
            }
            
            Text("Leave this screen open and the phone plugged in. Other signed-in devices will see this camera under Active Tasks and can open a live view.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Button(role: .destructive) {
                stopListening()
            } label: {
                Label("Stop Listening", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Security Camera")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            status = "Listening…"
            
            guard let uid = Auth.auth().currentUser?.uid else {
                status = "No user"
                return
            }
            
            // Mark this device as an active task (will show in Home / Devices)
            DeviceHeartbeat.shared.start(userUID: uid, deviceID: deviceID)
            DeviceHeartbeat.shared.setListening(true, task: "Security Camera: \(config.useCaseName)")
            
            let interval = max(1, min(10, config.uploadIntervalSeconds))
            streamer.start(userUID: uid, deviceID: deviceID, uploadInterval: interval)
            
            sendLifecycleNotification(starting: true, uid: uid)
        }
    }
    
    private func sendLifecycleNotification(starting: Bool, uid: String) {
        guard let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification")
        else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let title = starting
            ? "Started listening: \(config.useCaseName)"
            : "Stopped listening: \(config.useCaseName)"
        let body = starting
            ? "This device is now acting as a security camera."
            : "This device stopped acting as a security camera."
        
        let payload: [String: Any] = [
            "userId": uid,
            "title": title,
            "body": body
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: req).resume()
    }
    
    private func stopListening() {
        UIApplication.shared.isIdleTimerDisabled = false
        streamer.stop()
        if let uid = Auth.auth().currentUser?.uid {
            DeviceHeartbeat.shared.setListening(false)
            DeviceHeartbeat.shared.stop()
            Firestore.firestore()
                .collection("users").document(uid)
                .collection("devices").document(deviceID)
                .setData([
                    "isListening": false,
                    "task": FieldValue.delete()
                ], merge: true)
            sendLifecycleNotification(starting: false, uid: uid)
        }
        dismiss()
    }
}
struct MagnetListeningView: View {
    let config: MagnetSensorConfig
    
    @State private var status: String = "calibrating…"
    @State private var baselineMag: Double = 0
    @State private var currentMag: Double = 0
    @State private var deltaMag: Double = 0
    @State private var lastTriggerAt: Date = .distantPast
    private let cooldown: TimeInterval = 10
    
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private let updateInterval = 0.3
    
    private let db = Firestore.firestore()
    @AppStorage("userUID") private var userUID: String = ""
    private var deviceID: String { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "magnet.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.red)
                VStack(alignment: .leading) {
                    Text(config.useCaseName)
                        .font(.title3.bold())
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            HStack(spacing: 12) {
                Tag("baseline: " + String(format: "%.1f μT", baselineMag))
                Tag("current: " + String(format: "%.1f μT", currentMag))
                Tag("Δ: " + String(format: "%.1f μT", deltaMag))
            }
            
            Text("This sensor uses the device’s magnetometer to detect changes in the surrounding magnetic field. When the field changes more than your threshold, we'll send your custom notification.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            
            Spacer()
            
            Button(role: .destructive) {
                stopListening()
            } label: {
                Label("Stop Listening", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Magnetism")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            startSession()
        }
    }
    
    private func startSession() {
        guard motion.isMagnetometerAvailable else {
            status = "magnetometer not available"
            return
        }
        
        if let uid = Auth.auth().currentUser?.uid {
            DeviceHeartbeat.shared.start(userUID: uid, deviceID: deviceID)
            DeviceHeartbeat.shared.setListening(true, task: config.useCaseName)
        }
        
        sendLifecycleNotification(starting: true)
        
        status = "calibrating…"
        baselineMag = 0
        currentMag = 0
        deltaMag = 0
        
        queue.qualityOfService = .utility
        motion.magnetometerUpdateInterval = updateInterval
        
        motion.startMagnetometerUpdates(to: queue) { [self] data, _ in
            guard let d = data else { return }
            let x = d.magneticField.x
            let y = d.magneticField.y
            let z = d.magneticField.z
            let mag = sqrt(x * x + y * y + z * z) // μT
            
            DispatchQueue.main.async {
                currentMag = mag
                
                if baselineMag == 0 {
                    // initial calibration
                    baselineMag = mag
                    status = "listening…"
                    return
                }
                
                let delta = abs(mag - baselineMag)
                deltaMag = delta
                
                let now = Date()
                if delta >= config.thresholdDelta,
                   now.timeIntervalSince(lastTriggerAt) >= cooldown {
                    lastTriggerAt = now
                    status = "magnetic change detected"
                    fireMagnetEvent()
                } else {
                    status = "listening…"
                }
            }
        }
    }
    
    private func fireMagnetEvent() {
        guard !userUID.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(uid)
            .setData(["lastMagnetEventAt": FieldValue.serverTimestamp()],
                     merge: true)
        
        if let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "userId": uid,
                "title": config.notificationTitle,
                "body": config.notificationBody
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: req).resume()
        }
    }
    
    private func sendLifecycleNotification(starting: Bool) {
        guard let uid = Auth.auth().currentUser?.uid,
              let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification")
        else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let title = starting
            ? "Started listening: \(config.useCaseName)"
            : "Stopped listening: \(config.useCaseName)"
        let body = starting
            ? "This device is now monitoring magnetic changes."
            : "This device stopped monitoring magnetic changes."
        
        let payload: [String: Any] = [
            "userId": uid,
            "title": title,
            "body": body
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: req).resume()
    }
    
    private func stopListening() {
        UIApplication.shared.isIdleTimerDisabled = false
        motion.stopMagnetometerUpdates()
        if let uid = Auth.auth().currentUser?.uid {
            DeviceHeartbeat.shared.setListening(false)
            DeviceHeartbeat.shared.stop()
            Firestore.firestore()
                .collection("users").document(uid)
                .collection("devices").document(deviceID)
                .setData(["isListening": false], merge: true)
        }
        sendLifecycleNotification(starting: false)
        dismiss()
    }
}
struct LevelListeningView: View {
    let config: LevelSensorConfig
    
    @State private var status: String = "calibrating…"
    @State private var currentAngle: Double = 0
    @State private var lastTriggerAt: Date = .distantPast
    private let cooldown: TimeInterval = 10
    
    private let motionManager = CMMotionManager()
    private let updateInterval = 0.2
    
    private let db = Firestore.firestore()
    @AppStorage("userUID") private var userUID: String = ""
    private var deviceID: String { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "triangle.lefthalf.filled")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading) {
                    Text(config.useCaseName)
                        .font(.title3.bold())
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            HStack(spacing: 12) {
                Tag("angle: " + String(format: "%.0f°", currentAngle))
                Tag("target: " + String(format: "%.0f°", config.targetAngle))
            }
            
            Text("This sensor uses device motion to estimate tilt. When the phone tilts past your target angle (e.g. 45°), we'll send your custom notification.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            
            Spacer()
            
            Button(role: .destructive) {
                stopListening()
            } label: {
                Label("Stop Listening", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Level Sensor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            status = "listening…"
            
            if let uid = Auth.auth().currentUser?.uid {
                DeviceHeartbeat.shared.start(userUID: uid, deviceID: deviceID)
                DeviceHeartbeat.shared.setListening(true, task: config.useCaseName)
            }
            
            startMotion()
        }
        .onDisappear {
            stopListening()
        }
    }
    
    private func startMotion() {
        guard motionManager.isDeviceMotionAvailable else {
            status = "no motion data"
            return
        }
        
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let motion = motion else { return }
            
            // Use pitch magnitude as a simple "tilt" measure in degrees.
            let pitch = motion.attitude.pitch // radians
            let angle = abs(pitch) * 180 / .pi
            currentAngle = angle
            
            let now = Date()
            if angle >= config.targetAngle,
               now.timeIntervalSince(lastTriggerAt) >= cooldown {
                lastTriggerAt = now
                status = "tilt reached"
                fireLevelEvent(angle: angle)
            } else if angle < config.targetAngle {
                status = "listening…"
            }
        }
    }
    
    private func fireLevelEvent(angle: Double) {
        guard !userUID.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(uid)
            .setData(["lastLevelEventAt": FieldValue.serverTimestamp()],
                     merge: true)
        
        if let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "userId": uid,
                "title": config.notificationTitle,
                "body": config.notificationBody
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: req).resume()
        }
    }
    
    private func stopListening() {
        UIApplication.shared.isIdleTimerDisabled = false
        motionManager.stopDeviceMotionUpdates()
        if let uid = Auth.auth().currentUser?.uid {
            DeviceHeartbeat.shared.setListening(false)
            DeviceHeartbeat.shared.stop()
            Firestore.firestore()
                .collection("users").document(uid)
                .collection("devices").document(deviceID)
                .setData(["isListening": false], merge: true)
        }
    }
}
struct AirPressureSensorSetupView: View {
    let functionTitle: String
    
    @State private var useCaseName: String = ""
    @State private var notificationTitle: String = ""
    @State private var notificationBody: String = ""
    @State private var thresholdString: String = "3" // hPa delta
    
    @State private var pushToListening = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before You Begin").font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Bullet(
                    "Place phone in the space you care about",
                    detail: "For example, a room, shed, hallway, or enclosed area where opening a door or window changes the air pressure slightly."
                )
                Bullet(
                    "Keep the device fairly stationary",
                    detail: "Pressure changes work best when the phone isn’t moved around frequently."
                )
                Bullet(
                    "Optional: keep device plugged in",
                    detail: "Continuous barometer monitoring is more reliable on power."
                )
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize This Sensor").font(.headline)
                
                TextField("What are you monitoring? (e.g. Shed, Office, Room door)",
                          text: $useCaseName)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notification title (e.g. \"Pressure change detected\")",
                          text: $notificationTitle)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notification body (e.g. \"Air pressure changed in the shed.\")",
                          text: $notificationBody)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Trigger sensitivity (hPa delta, e.g. 3)",
                          text: $thresholdString)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
            
            Button {
                saveConfig()
                pushToListening = true
            } label: {
                Label("Start Air Pressure Sensor", systemImage: "gauge")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            NavigationLink(isActive: $pushToListening) {
                let raw = Double(thresholdString) ?? 3
                let clamped = max(0.5, min(50, raw)) // hPa delta clamp
                let cfg = AirPressureConfig(
                    useCaseName: useCaseName.isEmpty ? "Air Pressure Sensor" : useCaseName,
                    notificationTitle: notificationTitle.isEmpty ? "Air pressure changed" : notificationTitle,
                    notificationBody: notificationBody.isEmpty ? "A significant air pressure change was detected near this device." : notificationBody,
                    thresholdDelta: clamped
                )
                AirPressureListeningView(config: cfg)
            } label: {
                EmptyView()
            }
            .hidden()
        }
        .onAppear {
            loadConfig()
        }
    }
    
    private func loadConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .getDocument { snap, _ in
                guard let data = snap?.data() else { return }
                useCaseName = data["useCaseName"] as? String ?? useCaseName
                notificationTitle = data["notificationTitle"] as? String ?? notificationTitle
                notificationBody = data["notificationBody"] as? String ?? notificationBody
                if let t = data["thresholdDelta"] as? Double {
                    thresholdString = String(format: "%.1f", t)
                }
            }
    }
    
    private func saveConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let raw = Double(thresholdString) ?? 3
        let clamped = max(0.5, min(50, raw))
        let payload: [String: Any] = [
            "useCaseName": useCaseName,
            "notificationTitle": notificationTitle,
            "notificationBody": notificationBody,
            "thresholdDelta": clamped,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .setData(payload, merge: true)
    }
}
struct MagnetSensorSetupView: View {
    let functionTitle: String
    
    @State private var useCaseName: String = ""
    @State private var notificationTitle: String = ""
    @State private var notificationBody: String = ""
    @State private var thresholdString: String = "40" // μT delta
    
    @State private var pushToListening = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before You Begin").font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Bullet(
                    "Place phone near the metal or magnet you want to monitor",
                    detail: "For example, near a door with a magnetic latch, a toolbox, a safe, or a specific magnet."
                )
                Bullet(
                    "Avoid unnecessary movement",
                    detail: "Keep the phone stable so magnetic changes come from the environment, not from the phone moving."
                )
                Bullet(
                    "Optional: keep device plugged in",
                    detail: "Continuous sensor monitoring is more reliable when on power."
                )
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize This Sensor").font(.headline)
                
                TextField("What are you monitoring? (e.g. Safe door, Toolbox, Magnet)", text: $useCaseName)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notification title (e.g. \"Magnetism change detected\")",
                          text: $notificationTitle)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notification body (e.g. \"Magnetic field changed near the safe.\")",
                          text: $notificationBody)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Trigger sensitivity (μT delta, e.g. 40)",
                          text: $thresholdString)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
            
            Button {
                saveConfig()
                pushToListening = true
            } label: {
                Label("Start Magnetism Sensor", systemImage: "magnet.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            NavigationLink(isActive: $pushToListening) {
                let raw = Double(thresholdString) ?? 40
                let clamped = max(5, min(200, raw)) // μT delta clamp
                let cfg = MagnetSensorConfig(
                    useCaseName: useCaseName.isEmpty ? "Magnetism Sensor" : useCaseName,
                    notificationTitle: notificationTitle.isEmpty ? "Magnetic field changed" : notificationTitle,
                    notificationBody: notificationBody.isEmpty ? "A significant magnetic change was detected near this device." : notificationBody,
                    thresholdDelta: clamped
                )
                MagnetListeningView(config: cfg)
            } label: {
                EmptyView()
            }
            .hidden()
        }
        .onAppear {
            loadConfig()
        }
    }
    
    private func loadConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .getDocument { snap, _ in
                guard let data = snap?.data() else { return }
                useCaseName = data["useCaseName"] as? String ?? useCaseName
                notificationTitle = data["notificationTitle"] as? String ?? notificationTitle
                notificationBody = data["notificationBody"] as? String ?? notificationBody
                if let t = data["thresholdDelta"] as? Double {
                    thresholdString = String(format: "%.0f", t)
                }
            }
    }
    
    private func saveConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let raw = Double(thresholdString) ?? 40
        let clamped = max(5, min(200, raw))
        let payload: [String: Any] = [
            "useCaseName": useCaseName,
            "notificationTitle": notificationTitle,
            "notificationBody": notificationBody,
            "thresholdDelta": clamped,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .setData(payload, merge: true)
    }
}
struct LevelSensorSetupView: View {
    let functionTitle: String
    
    @State private var useCaseName: String = ""
    @State private var notificationTitle: String = ""
    @State private var notificationBody: String = ""
    @State private var angleString: String = "45"
    
    @State private var pushToListening = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before You Begin").font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Bullet(
                    "Secure the Phone",
                    detail: "Place it where it can tilt but won’t fall (shelf, bracket, stand, etc.)."
                )
                Bullet(
                    "Optional: Keep device plugged in",
                    detail: "Tilt monitoring can run for long periods; power helps for long sessions."
                )
                Bullet(
                    "Optional: Extend Auto-Lock while testing",
                    detail: "Settings → Display & Brightness → Auto-Lock."
                )
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize This Sensor").font(.headline)
                
                TextField("What is this watching? (e.g. Garage door, Shelf, Gate)",
                          text: $useCaseName)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notification title (e.g. \"Tilt reached\")",
                          text: $notificationTitle)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notification body (e.g. \"Device tilted past 45°.\")",
                          text: $notificationBody)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Target tilt angle in ° (e.g. 45)",
                          text: $angleString)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }
            
            Button {
                saveConfig()
                pushToListening = true
            } label: {
                Label("Start Level Sensor", systemImage: "triangle.lefthalf.filled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            NavigationLink(isActive: $pushToListening) {
                let rawAngle = Double(angleString) ?? 45
                let clamped = max(5, min(85, rawAngle))
                let cfg = LevelSensorConfig(
                    useCaseName: useCaseName.isEmpty ? "Level Sensor" : useCaseName,
                    notificationTitle: notificationTitle.isEmpty ? "Tilt angle reached" : notificationTitle,
                    notificationBody: notificationBody.isEmpty ? "The device tilted past your configured angle." : notificationBody,
                    targetAngle: clamped
                )
                LevelListeningView(config: cfg)
            } label: {
                EmptyView()
            }
            .hidden()
        }
        .onAppear {
            loadConfig()
        }
    }
    
    private func loadConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .getDocument { snap, _ in
                guard let data = snap?.data() else { return }
                useCaseName = data["useCaseName"] as? String ?? useCaseName
                notificationTitle = data["notificationTitle"] as? String ?? notificationTitle
                notificationBody = data["notificationBody"] as? String ?? notificationBody
                if let deg = data["targetAngle"] as? Double {
                    angleString = String(format: "%.0f", deg)
                }
            }
    }
    
    private func saveConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let rawAngle = Double(angleString) ?? 45
        let clamped = max(5, min(85, rawAngle))
        let payload: [String: Any] = [
            "useCaseName": useCaseName,
            "notificationTitle": notificationTitle,
            "notificationBody": notificationBody,
            "targetAngle": clamped,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .setData(payload, merge: true)
    }
}
struct PowerLossListeningView: View {
    let config: PowerLossConfig
    
    @State private var status: String = "listening…"
    @State private var lastState: UIDevice.BatteryState = UIDevice.current.batteryState
    @State private var lastTriggerAt: Date = .distantPast
    private let cooldown: TimeInterval = 5
    
    private let db = Firestore.firestore()
    @AppStorage("userUID") private var userUID: String = ""
    private var deviceID: String { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "bolt.slash.circle")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading) {
                    Text(config.useCaseName)
                        .font(.title3.bold())
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            Text("This sensor watches when the device starts or stops charging. Use it to detect power loss or restoration at the outlet feeding this phone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            
            Spacer()
            
            Button(role: .destructive) {
                stopListening()
            } label: {
                Label("Stop Listening", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Power Loss")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            UIDevice.current.isBatteryMonitoringEnabled = true
            
            if let uid = Auth.auth().currentUser?.uid {
                DeviceHeartbeat.shared.start(userUID: uid, deviceID: deviceID)
                DeviceHeartbeat.shared.setListening(true, task: config.useCaseName)
            }
            
            lastState = UIDevice.current.batteryState
            status = describe(state: lastState)
            
            sendLifecycleNotification(starting: true)
            
            NotificationCenter.default.addObserver(
                forName: UIDevice.batteryStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [self] _ in
                handleStateChange()
            }
        }
    }
    
    private func describe(state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging: return "charging"
        case .full: return "full"
        case .unplugged: return "on battery"
        case .unknown: fallthrough
        @unknown default: return "unknown"
        }
    }
    
    private func handleStateChange() {
        let newState = UIDevice.current.batteryState
        let now = Date()
        lastState = newState
        status = describe(state: newState)
        
        guard now.timeIntervalSince(lastTriggerAt) >= cooldown else { return }
        lastTriggerAt = now
        
        switch newState {
        case .charging, .full:
            firePowerEvent(restored: true)
        case .unplugged:
            firePowerEvent(restored: false)
        case .unknown:
            break
        @unknown default:
            break
        }
    }
    
    private func firePowerEvent(restored: Bool) {
        guard !userUID.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(uid)
            .setData(["lastPowerEventAt": FieldValue.serverTimestamp()],
                     merge: true)
        
        if let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let title = restored ? config.pluggedInTitle : config.unpluggedTitle
            let body = restored ? config.pluggedInBody : config.unpluggedBody
            let payload: [String: Any] = [
                "userId": uid,
                "title": title,
                "body": body
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: req).resume()
        }
    }
    
    private func sendLifecycleNotification(starting: Bool) {
        guard let uid = Auth.auth().currentUser?.uid,
              let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification")
        else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let title = starting
            ? "Started listening: \(config.useCaseName)"
            : "Stopped listening: \(config.useCaseName)"
        let body = starting
            ? "This device is now monitoring power state."
            : "This device stopped monitoring power state."
        
        let payload: [String: Any] = [
            "userId": uid,
            "title": title,
            "body": body
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: req).resume()
    }
    
    private func stopListening() {
        UIApplication.shared.isIdleTimerDisabled = false
        UIDevice.current.isBatteryMonitoringEnabled = false
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
        if let uid = Auth.auth().currentUser?.uid {
            DeviceHeartbeat.shared.setListening(false)
            DeviceHeartbeat.shared.stop()
            Firestore.firestore()
                .collection("users").document(uid)
                .collection("devices").document(deviceID)
                .setData(["isListening": false], merge: true)
        }
        sendLifecycleNotification(starting: false)
        dismiss()
    }
}
struct SecurityCameraSetupView: View {
    let functionTitle: String
    
    @State private var config = SecurityCameraConfig(
        useCaseName: "Security Camera",
        uploadIntervalSeconds: 3
    )
    @State private var pushToListening = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before You Begin").font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Bullet(
                    "Place phone where it can see the area",
                    detail: "Use a shelf or stand with a clear view from the back camera."
                )
                Bullet(
                    "Keep device plugged in",
                    detail: "Continuous streaming will drain the battery quickly."
                )
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize This Camera").font(.headline)
                
                TextField("Camera name (e.g. Front door, Garage)",
                          text: $config.useCaseName)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    Text("Upload every")
                    TextField("Seconds", value: $config.uploadIntervalSeconds, format: .number)
                        .keyboardType(.numberPad)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text("seconds")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            
            Button {
                saveConfig()
                pushToListening = true
            } label: {
                Label("Start Security Camera", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            NavigationLink(isActive: $pushToListening) {
                SecurityCameraListeningView(config: config, functionTitle: functionTitle)
            } label: {
                EmptyView()
            }
            .hidden()
        }
        .onAppear {
            loadConfig()
        }
    }
    
    private func loadConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .getDocument { snap, _ in
                guard let data = snap?.data() else { return }
                if let name = data["useCaseName"] as? String {
                    config.useCaseName = name
                }
                if let interval = data["uploadIntervalSeconds"] as? Double {
                    config.uploadIntervalSeconds = interval
                }
            }
    }
    
    private func saveConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let clampedInterval = max(1, min(10, config.uploadIntervalSeconds))
        let payload: [String: Any] = [
            "useCaseName": config.useCaseName,
            "uploadIntervalSeconds": clampedInterval,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .setData(payload, merge: true)
    }
}
 // MARK: - Mailbox Notifier Setup + Listening (Brightness-based)
struct PowerLossSetupView: View {
    let functionTitle: String
    
    @State private var config = PowerLossConfig(
        useCaseName: "Power Loss",
        pluggedInTitle: "Power restored",
        pluggedInBody: "Charger power has been restored.",
        unpluggedTitle: "Power lost",
        unpluggedBody: "This device stopped charging."
    )
    
    @State private var pushToListening = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before You Begin").font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Bullet(
                    "Keep device plugged in to the outlet you care about",
                    detail: "Use the same outlet or strip you want to monitor for power loss."
                )
                Bullet(
                    "Optionally extend Auto-Lock while testing",
                    detail: "Settings → Display & Brightness → Auto-Lock."
                )
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize Notifications").font(.headline)
                
                TextField("Use-case name (e.g. Garage outlet)", text: $config.useCaseName)
                    .textFieldStyle(.roundedBorder)
                
                Text("When power is restored").font(.caption).foregroundStyle(.secondary)
                TextField("Title", text: $config.pluggedInTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Body", text: $config.pluggedInBody)
                    .textFieldStyle(.roundedBorder)
                
                Text("When power is lost").font(.caption).foregroundStyle(.secondary)
                TextField("Title", text: $config.unpluggedTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Body", text: $config.unpluggedBody)
                    .textFieldStyle(.roundedBorder)
            }
            
            Button {
                saveConfig()
                pushToListening = true
            } label: {
                Label("Start Power Loss Monitor", systemImage: "bolt.slash.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            NavigationLink(isActive: $pushToListening) {
                PowerLossListeningView(config: config)
            } label: {
                EmptyView()
            }
            .hidden()
        }
        .onAppear {
            loadConfig()
        }
    }
    
    private func loadConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .getDocument { snap, _ in
                guard let data = snap?.data() else { return }
                config.useCaseName = data["useCaseName"] as? String ?? config.useCaseName
                config.pluggedInTitle = data["pluggedInTitle"] as? String ?? config.pluggedInTitle
                config.pluggedInBody = data["pluggedInBody"] as? String ?? config.pluggedInBody
                config.unpluggedTitle = data["unpluggedTitle"] as? String ?? config.unpluggedTitle
                config.unpluggedBody = data["unpluggedBody"] as? String ?? config.unpluggedBody
            }
    }
    
    private func saveConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let payload: [String: Any] = [
            "useCaseName": config.useCaseName,
            "pluggedInTitle": config.pluggedInTitle,
            "pluggedInBody": config.pluggedInBody,
            "unpluggedTitle": config.unpluggedTitle,
            "unpluggedBody": config.unpluggedBody,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .setData(payload, merge: true)
    }
}

struct MailboxNotifierSetupView: View {
    @State private var hasStartedTimer = false
    @State private var countdown = 30
    @State private var pushToListening = false
    
    @State private var config = MailboxNotifierConfig(
        useCaseName: "Mailbox Notifier",
        notificationTitle: "Mail detected",
        notificationBody: "We detected a brightness change in your mailbox."
    )
    
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let db = Firestore.firestore()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            Text("Before You Begin").font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Bullet(
                    "Keep device plugged in",
                    detail: "Recommended for longer sessions so the phone doesn’t die in the mailbox."
                )
                Bullet(
                    "Place phone face-up in the mailbox",
                    detail: "Stable position, not touching moving parts like the door."
                )
                Bullet(
                    "Optionally extend Auto-Lock while testing",
                    detail: "Settings → Display & Brightness → Auto-Lock."
                )
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize Notification").font(.headline)
                
                TextField("Use-case name (e.g. Front mailbox)", text: $config.useCaseName)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notification title", text: $config.notificationTitle)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notification body", text: $config.notificationBody)
                    .textFieldStyle(.roundedBorder)
            }
            
            if !hasStartedTimer && !pushToListening {
                Button {
                    saveConfig()
                    hasStartedTimer = true
                    countdown = 30
                } label: {
                    Label("I'm ready — start 30s placement timer", systemImage: "timer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            
            if hasStartedTimer && !pushToListening {
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
                        hasStartedTimer = false
                        pushToListening = true
                    }
                }
            }
            
            NavigationLink(isActive: $pushToListening) {
                MailboxListeningView(config: config)
            } label: {
                EmptyView()
            }
            .hidden()
        }
    }
    
    private func saveConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let payload: [String: Any] = [
            "useCaseName": config.useCaseName,
            "notificationTitle": config.notificationTitle,
            "notificationBody": config.notificationBody,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid)
            .collection("functions").document("Mailbox Notifier")
            .setData(payload, merge: true)
    }
}

struct MailboxListeningView: View {
    let config: MailboxNotifierConfig
    
    private let ratioThreshold: CGFloat = 1.8
    private let absoluteDelta: CGFloat = 0.12
    private let cooldownSeconds: TimeInterval = 12
    
    @State private var baseline: CGFloat = 0
    @State private var current: CGFloat = UIScreen.main.brightness
    @State private var status: String = "calibrating…"
    @State private var lastTriggerAt: Date = .distantPast
    @State private var hasTriggered: Bool = false
    
    private let sampler = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private let db = Firestore.firestore()
    @AppStorage("userUID") private var userUID: String = ""
    private var deviceID: String { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: hasTriggered ? "envelope.badge.fill" : "ear.badge.waveform")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(hasTriggered ? .green : .blue)
                VStack(alignment: .leading) {
                    Text(hasTriggered ? "Mail Detected" : "Listening for Door Open")
                        .font(.title3.bold())
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                Tag("baseline: " + String(format: "%.3f", baseline))
                Tag("current: " + String(format: "%.3f", current))
                Tag("ratio: " + String(format: "%.2f", baseline > 0 ? current / baseline : 0))
            }
            
            Text("Leave this phone in the mailbox with auto-brightness enabled. When the door opens and the screen brightens, we'll notify all your devices.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            
            Spacer()
            
            Button(role: .destructive) {
                stopListening()
            } label: {
                Label("Stop Listening", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Mailbox Notifier")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            baseline = max(UIScreen.main.brightness, 0.001)
            current = UIScreen.main.brightness
            status = "armed"
            UIApplication.shared.isIdleTimerDisabled = true
            
            if let uid = Auth.auth().currentUser?.uid {
                DeviceHeartbeat.shared.start(userUID: uid, deviceID: deviceID)
                DeviceHeartbeat.shared.setListening(true, task: "Mailbox Notifier")
            }
            
            sendLifecycleNotification(starting: true)
            
            NotificationCenter.default.addObserver(
                forName: UIScreen.brightnessDidChangeNotification,
                object: nil,
                queue: .main
            ) { [self] _ in
                self.sampleAndEvaluate()
            }
        }
        .onReceive(sampler) { _ in
            sampleAndEvaluate()
        }
    }
    
    private func sampleAndEvaluate() {
        current = UIScreen.main.brightness
        guard baseline > 0 else { return }
        let ratio = current / baseline
        let delta = current - baseline
        let canTrigger = Date().timeIntervalSince(lastTriggerAt) >= cooldownSeconds
        
        if !hasTriggered && canTrigger && (ratio >= ratioThreshold || delta >= absoluteDelta) {
            lastTriggerAt = Date()
            hasTriggered = true
            status = "triggered"
            fireMailEvent()
        }
    }
    
    private func fireMailEvent() {
        guard !userUID.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(uid).setData(["mailDetected": true], merge: true)
        
        if let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "userId": uid,
                "title": config.notificationTitle,
                "body": config.notificationBody
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: req).resume()
        }
    }
    
    private func sendLifecycleNotification(starting: Bool) {
        guard let uid = Auth.auth().currentUser?.uid,
              let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification")
        else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let title = starting
            ? "Started listening: \(config.useCaseName)"
            : "Stopped listening: \(config.useCaseName)"
        let body = starting
            ? "This device is now listening for light changes."
            : "This device stopped listening for light changes."
        
        let payload: [String: Any] = [
            "userId": uid,
            "title": title,
            "body": body
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: req).resume()
    }
    
    private func stopListening() {
        UIApplication.shared.isIdleTimerDisabled = false
        if let uid = Auth.auth().currentUser?.uid {
            DeviceHeartbeat.shared.setListening(false)
            DeviceHeartbeat.shared.stop()
            Firestore.firestore()
                .collection("users").document(uid)
                .collection("devices").document(deviceID)
                .setData(["isListening": false], merge: true)
        }
        NotificationCenter.default.removeObserver(
            self,
            name: UIScreen.brightnessDidChangeNotification,
            object: nil
        )
        sendLifecycleNotification(starting: false)
        dismiss()
    }
}

 // MARK: - Vibration Sensor (Config + Detector + Listening)
final class SecurityCameraStreamer: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var currentFrame: UIImage?
    
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "security-camera.capture")
    private let context = CIContext()
    
    private var lastUpload = Date.distantPast
    private var uploadInterval: TimeInterval = 3
    
    private var userUID: String = ""
    private var deviceID: String = ""
    
    private let storage = Storage.storage()
    
    func start(userUID: String, deviceID: String, uploadInterval: TimeInterval) {
        self.userUID = userUID
        self.deviceID = deviceID
        self.uploadInterval = uploadInterval
        
        configureSession()
        session.startRunning()
    }
    
    func stop() {
        session.stopRunning()
    }
    
    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        
        if let conn = output.connection(with: .video),
           conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }
        
        session.commitConfiguration()
    }
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let img = UIImage(cgImage: cg)
        
        DispatchQueue.main.async {
            self.currentFrame = img
        }
        
        let now = Date()
        guard now.timeIntervalSince(lastUpload) >= uploadInterval,
              !userUID.isEmpty, !deviceID.isEmpty,
              let data = img.jpegData(compressionQuality: 0.4) else { return }
        
        lastUpload = now
        
        let path = "securityCameras/\(userUID)/\(deviceID)/latest.jpg"
        let ref = storage.reference(withPath: path)
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        ref.putData(data, metadata: meta)
    }
}
 final class VibrationDetector: ObservableObject {
 private let motion = CMMotionManager()
 private let queue = OperationQueue()
 
 private let updateInterval = 0.2
 private let alpha = 0.05
 private let varianceThreshold = 0.02
 private let minimumGap: TimeInterval = 10
 
 @Published var variance: Double = 0
 @Published var status: String = "idle"
 
 private var meanMag: Double = 1.0
 private var varMag: Double = 0
 private var initialized = false
 private var lastEventAt: Date = .distantPast
 
 var onSpike: (() -> Void)?
 
 func start() {
 guard motion.isAccelerometerAvailable else {
 status = "no accelerometer"
 return
 }
 if motion.isAccelerometerActive { return }
 
 status = "listening…"
 initialized = false
 meanMag = 1.0
 varMag = 0
 variance = 0
 lastEventAt = .distantPast
 
 motion.accelerometerUpdateInterval = updateInterval
 queue.qualityOfService = .utility
 
 motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
 guard let self, let d = data else { return }
 let x = d.acceleration.x
 let y = d.acceleration.y
 let z = d.acceleration.z
 let mag = sqrt(x*x + y*y + z*z)
 
 if !self.initialized {
 self.initialized = true
 self.meanMag = mag
 self.varMag = 0
 }
 
 let diff = mag - self.meanMag
 self.meanMag += self.alpha * diff
 self.varMag += self.alpha * (diff * diff - self.varMag)
 
 let v = max(self.varMag, 0)
 DispatchQueue.main.async {
 self.variance = v
 }
 
 if v >= self.varianceThreshold {
 let now = Date()
 if now.timeIntervalSince(self.lastEventAt) >= self.minimumGap {
 self.lastEventAt = now
 DispatchQueue.main.async {
 self.status = "spike"
 self.onSpike?()
 }
 }
 } else {
 DispatchQueue.main.async {
 self.status = "listening…"
 }
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
 
struct VibrationSensorSetupView: View {
    let functionTitle: String
    
    @State private var useCaseName: String = ""
    @State private var notificationTitle: String = ""
    @State private var notificationBody: String = ""
    
    @State private var pushToListening = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before You Begin").font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Bullet(
                    "Place phone firmly on the surface",
                    detail: "E.g., on a dryer, machine, floor, workbench, or shelf near footsteps or vibration."
                )
                Bullet(
                    "Keep device plugged in for long sessions",
                    detail: "Prevents the sensor phone from dying while monitoring."
                )
       
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize This Sensor").font(.headline)
                
                TextField("What are you monitoring? (e.g. Dryer, Footsteps, Machine)",
                          text: $useCaseName)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notification title (e.g. \"Vibration event\")",
                          text: $notificationTitle)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notification body (e.g. \"Vibration spike detected on the dryer.\")",
                          text: $notificationBody)
                    .textFieldStyle(.roundedBorder)
            }
            
            Button {
                saveConfig()
                pushToListening = true
            } label: {
                Label("Start Vibration Sensor", systemImage: "waveform.path.ecg")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            NavigationLink(isActive: $pushToListening) {
                let config = VibrationSensorConfig(
                    useCaseName: useCaseName.isEmpty ? "Vibration Sensor" : useCaseName,
                    notificationTitle: notificationTitle.isEmpty ? "Vibration sensor triggered" : notificationTitle,
                    notificationBody: notificationBody.isEmpty ? "A vibration spike was detected by your sensor." : notificationBody
                )
                VibrationListeningView(config: config)
            } label: {
                EmptyView()
            }
            .hidden()
        }
        .onAppear {
            loadConfig()
        }
    }
    
    private func loadConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .getDocument { snap, _ in
                guard let data = snap?.data() else { return }
                useCaseName = data["useCaseName"] as? String ?? useCaseName
                notificationTitle = data["notificationTitle"] as? String ?? notificationTitle
                notificationBody = data["notificationBody"] as? String ?? notificationBody
            }
    }
    
    private func saveConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let payload: [String: Any] = [
            "useCaseName": useCaseName,
            "notificationTitle": notificationTitle,
            "notificationBody": notificationBody,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .setData(payload, merge: true)
    }
}

struct VibrationListeningView: View {
    let config: VibrationSensorConfig
    
    @StateObject private var detector = VibrationDetector()
    
    private let db = Firestore.firestore()
    @AppStorage("userUID") private var userUID: String = ""
    private var deviceID: String { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading) {
                    Text(config.useCaseName)
                        .font(.title3.bold())
                    Text(detector.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            HStack(spacing: 12) {
                Tag("variance: " + String(format: "%.4f", detector.variance))
            }
            
            Text("Device is acting as a vibration sensor. Spikes in vibration will send your custom notification to all signed-in devices.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            
            Spacer()
            
            Button(role: .destructive) {
                stopListening()
            } label: {
                Label("Stop Listening", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Vibration Sensor")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            
            if let uid = Auth.auth().currentUser?.uid {
                DeviceHeartbeat.shared.start(userUID: uid, deviceID: deviceID)
                DeviceHeartbeat.shared.setListening(true, task: config.useCaseName)
            }
            
            sendLifecycleNotification(starting: true)
            
            detector.onSpike = { [self] in
                self.fireVibrationEvent()
            }
            detector.start()
        }
    }
    
    private func fireVibrationEvent() {
        guard !userUID.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(uid)
            .setData(["lastVibrationEventAt": FieldValue.serverTimestamp()],
                     merge: true)
        
        if let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "userId": uid,
                "title": config.notificationTitle,
                "body": config.notificationBody
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: req).resume()
        }
    }
    
    private func sendLifecycleNotification(starting: Bool) {
        guard let uid = Auth.auth().currentUser?.uid,
              let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification")
        else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let title = starting
            ? "Started listening: \(config.useCaseName)"
            : "Stopped listening: \(config.useCaseName)"
        let body = starting
            ? "This device is now listening for vibration."
            : "This device stopped listening for vibration."
        
        let payload: [String: Any] = [
            "userId": uid,
            "title": title,
            "body": body
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: req).resume()
    }
    
    private func stopListening() {
        UIApplication.shared.isIdleTimerDisabled = false
        detector.stop()
        if let uid = Auth.auth().currentUser?.uid {
            DeviceHeartbeat.shared.setListening(false)
            DeviceHeartbeat.shared.stop()
            Firestore.firestore()
                .collection("users").document(uid)
                .collection("devices").document(deviceID)
                .setData(["isListening": false], merge: true)
        }
        sendLifecycleNotification(starting: false)
        dismiss()
    }
}

 // MARK: - Sound Sensor (Config + Monitor + Listening)
 
 final class SoundLevelMonitor: NSObject, ObservableObject, AVAudioRecorderDelegate {
 @Published var level: Float = 0
 
 private var recorder: AVAudioRecorder?
 private var timer: Timer?
 
 func start() {
 let session = AVAudioSession.sharedInstance()
 session.requestRecordPermission { [weak self] granted in
 guard granted else { return }
 DispatchQueue.main.async {
 self?.configureAndStart(session: session)
 }
 }
 }
 
 private func configureAndStart(session: AVAudioSession) {
 do {
 try session.setCategory(.record, mode: .measurement, options: .duckOthers)
 try session.setActive(true)
 
 let url = URL(fileURLWithPath: NSTemporaryDirectory())
 .appendingPathComponent("level.caf")
 let settings: [String: Any] = [
 AVFormatIDKey: Int(kAudioFormatAppleIMA4),
 AVSampleRateKey: 44100,
 AVNumberOfChannelsKey: 1,
 AVEncoderBitRateKey: 12800,
 AVLinearPCMBitDepthKey: 16,
 AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
 ]
 recorder = try AVAudioRecorder(url: url, settings: settings)
 recorder?.isMeteringEnabled = true
 recorder?.delegate = self
 recorder?.record()
 
 timer?.invalidate()
 timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
 self?.updateLevel()
 }
 } catch {
 print("Sound monitor error: \(error)")
 }
 }
 
 private func updateLevel() {
 guard let recorder = recorder else { return }
 recorder.updateMeters()
 let power = recorder.averagePower(forChannel: 0) // -160...0 dB
 let linear = pow(10, power / 20) // 0...1
 DispatchQueue.main.async {
 self.level = linear
 }
 }
 
 func stop() {
 timer?.invalidate()
 timer = nil
 recorder?.stop()
 recorder = nil
 try? AVAudioSession.sharedInstance()
 .setActive(false, options: .notifyOthersOnDeactivation)
 }
 }
 
struct SoundSensorSetupView: View {
    let functionTitle: String
    
    @State private var useCaseName: String = ""
    @State private var notificationTitle: String = ""
    @State private var notificationBody: String = ""
    @State private var thresholdString: String = "0.7"
    
    @State private var pushToListening = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before You Begin").font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Bullet(
                    "Place phone near the sound source",
                    detail: "E.g., near a door, alarm, machine, or room you want to monitor."
                )
                Bullet(
                    "Keep device plugged in for long sessions",
                    detail: "Continuous audio monitoring uses more power."
                )
                Bullet(
                    "Optionally extend Auto-Lock while testing",
                    detail: "Settings → Display & Brightness → Auto-Lock."
                )
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize This Sensor").font(.headline)
                
                TextField("What are you monitoring? (e.g. Knocks, Alarm, Room noise)",
                          text: $useCaseName)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notification title (e.g. \"Sound event\")",
                          text: $notificationTitle)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notification body (e.g. \"Loud sound detected at back door.\")",
                          text: $notificationBody)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Trigger threshold (0.0–1.0, default 0.7)",
                          text: $thresholdString)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
            
            Button {
                saveConfig()
                pushToListening = true
            } label: {
                Label("Start Sound Sensor", systemImage: "ear.badge.waveform")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            NavigationLink(isActive: $pushToListening) {
                let t = Float(thresholdString) ?? 0.7
                let config = SoundSensorConfig(
                    useCaseName: useCaseName.isEmpty ? "Sound Sensor" : useCaseName,
                    notificationTitle: notificationTitle.isEmpty ? "Sound sensor triggered" : notificationTitle,
                    notificationBody: notificationBody.isEmpty ? "A loud sound was detected by your sensor." : notificationBody,
                    threshold: max(0.1, min(1.0, t))
                )
                SoundListeningView(config: config)
            } label: {
                EmptyView()
            }
            .hidden()
        }
        .onAppear {
            loadConfig()
        }
    }
    
    private func loadConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .getDocument { snap, _ in
                guard let data = snap?.data() else { return }
                useCaseName = data["useCaseName"] as? String ?? useCaseName
                notificationTitle = data["notificationTitle"] as? String ?? notificationTitle
                notificationBody = data["notificationBody"] as? String ?? notificationBody
                if let t = data["threshold"] as? Double {
                    thresholdString = String(format: "%.2f", t)
                }
            }
    }
    
    private func saveConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let t = Double(thresholdString) ?? 0.7
        let payload: [String: Any] = [
            "useCaseName": useCaseName,
            "notificationTitle": notificationTitle,
            "notificationBody": notificationBody,
            "threshold": max(0.1, min(1.0, t)),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .setData(payload, merge: true)
    }
}

struct SoundListeningView: View {
    let config: SoundSensorConfig
    
    @StateObject private var monitor = SoundLevelMonitor()
    @State private var status: String = "preparing…"
    @State private var lastTriggerAt: Date = .distantPast
    private let cooldown: TimeInterval = 10
    
    private let db = Firestore.firestore()
    @AppStorage("userUID") private var userUID: String = ""
    private var deviceID: String { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "ear.badge.waveform")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text(config.useCaseName)
                        .font(.title3.bold())
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            HStack(spacing: 12) {
                Tag("level: " + String(format: "%.2f", monitor.level))
                Tag("threshold: " + String(format: "%.2f", config.threshold))
            }
            
            Text("Device is acting as a sound sensor. When the sound level crosses your threshold, we'll send your custom notification.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            
            Spacer()
            
            Button(role: .destructive) {
                stopListening()
            } label: {
                Label("Stop Listening", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Sound Sensor")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            status = "listening…"
            
            if let uid = Auth.auth().currentUser?.uid {
                DeviceHeartbeat.shared.start(userUID: uid, deviceID: deviceID)
                DeviceHeartbeat.shared.setListening(true, task: config.useCaseName)
            }
            
            sendLifecycleNotification(starting: true)
            
            monitor.start()
            startEvaluator()
        }
    }
    
    private func startEvaluator() {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
            if UIApplication.shared.applicationState == .background {
                timer.invalidate()
            }
            let level = monitor.level
            if level >= config.threshold {
                let now = Date()
                if now.timeIntervalSince(lastTriggerAt) >= cooldown {
                    lastTriggerAt = now
                    status = "triggered"
                    fireSoundEvent()
                }
            } else {
                status = "listening…"
            }
        }
    }
    
    private func fireSoundEvent() {
        guard !userUID.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(uid)
            .setData(["lastSoundEventAt": FieldValue.serverTimestamp()],
                     merge: true)
        
        if let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "userId": uid,
                "title": config.notificationTitle,
                "body": config.notificationBody
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: req).resume()
        }
    }
    
    private func sendLifecycleNotification(starting: Bool) {
        guard let uid = Auth.auth().currentUser?.uid,
              let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification")
        else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let title = starting
            ? "Started listening: \(config.useCaseName)"
            : "Stopped listening: \(config.useCaseName)"
        let body = starting
            ? "This device is now listening for sound."
            : "This device stopped listening for sound."
        
        let payload: [String: Any] = [
            "userId": uid,
            "title": title,
            "body": body
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: req).resume()
    }
    
    private func stopListening() {
        UIApplication.shared.isIdleTimerDisabled = false
        monitor.stop()
        if let uid = Auth.auth().currentUser?.uid {
            DeviceHeartbeat.shared.setListening(false)
            DeviceHeartbeat.shared.stop()
            Firestore.firestore()
                .collection("users").document(uid)
                .collection("devices").document(deviceID)
                .setData(["isListening": false], merge: true)
        }
        sendLifecycleNotification(starting: false)
        dismiss()
    }
}

 // MARK: - Presence Sensor (Config + Listening)
 
struct PresenceSensorSetupView: View {
    let functionTitle: String
    
    @State private var useCaseName: String = ""
    @State private var notificationTitle: String = ""
    @State private var notificationBody: String = ""
    
    @State private var pushToListening = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Before You Begin").font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Bullet(
                    "Place phone in the target area",
                    detail: "E.g., shop entrance, shed, desk, hallway, or another zone you care about."
                )
                Bullet(
                    "Keep device plugged in for area monitoring",
                    detail: "Presence sensing may run for long periods."
                )
                Bullet(
                    "Optionally extend Auto-Lock while testing",
                    detail: "Settings → Display & Brightness → Auto-Lock."
                )
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Customize This Sensor").font(.headline)
                
                TextField("What area is this? (e.g. Shop entrance, Shed, Desk)",
                          text: $useCaseName)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notification title (e.g. \"Presence detected\")",
                          text: $notificationTitle)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Notification body (e.g. \"Movement detected near the shop entrance.\")",
                          text: $notificationBody)
                    .textFieldStyle(.roundedBorder)
            }
            
            Button {
                saveConfig()
                pushToListening = true
            } label: {
                Label("Start Presence Sensor", systemImage: "dot.radiowaves.up.forward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            NavigationLink(isActive: $pushToListening) {
                let config = PresenceSensorConfig(
                    useCaseName: useCaseName.isEmpty ? "Presence Sensor" : useCaseName,
                    notificationTitle: notificationTitle.isEmpty ? "Presence detected" : notificationTitle,
                    notificationBody: notificationBody.isEmpty ? "Movement or handling was detected near this device." : notificationBody
                )
                PresenceListeningView(config: config)
            } label: {
                EmptyView()
            }
            .hidden()
        }
        .onAppear {
            loadConfig()
        }
    }
    
    private func loadConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .getDocument { snap, _ in
                guard let data = snap?.data() else { return }
                useCaseName = data["useCaseName"] as? String ?? useCaseName
                notificationTitle = data["notificationTitle"] as? String ?? notificationTitle
                notificationBody = data["notificationBody"] as? String ?? notificationBody
            }
    }
    
    private func saveConfig() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let payload: [String: Any] = [
            "useCaseName": useCaseName,
            "notificationTitle": notificationTitle,
            "notificationBody": notificationBody,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid)
            .collection("functions").document(functionTitle)
            .setData(payload, merge: true)
    }
}

struct PresenceListeningView: View {
    let config: PresenceSensorConfig
    
    @State private var status: String = "calibrating…"
    @State private var lastTriggerAt: Date = .distantPast
    private let cooldown: TimeInterval = 20
    
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private let updateInterval = 0.5
    private let magnitudeThreshold = 0.15
    
    private let db = Firestore.firestore()
    @AppStorage("userUID") private var userUID: String = ""
    private var deviceID: String { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text(config.useCaseName)
                        .font(.title3.bold())
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            Text("This sensor looks for subtle device movement. When someone bumps, picks up, or moves the device, we'll send your custom notification as a presence signal.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            
            Spacer()
            
            Button(role: .destructive) {
                stopListening()
            } label: {
                Label("Stop Listening", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Presence Sensor")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            status = "listening…"
            
            if let uid = Auth.auth().currentUser?.uid {
                DeviceHeartbeat.shared.start(userUID: uid, deviceID: deviceID)
                DeviceHeartbeat.shared.setListening(true, task: config.useCaseName)
            }
            
            sendLifecycleNotification(starting: true)
            startMotion()
        }
    }
    
    private func startMotion() {
        guard motion.isAccelerometerAvailable else {
            status = "no accelerometer"
            return
        }
        
        motion.accelerometerUpdateInterval = updateInterval
        queue.qualityOfService = .utility
        
        motion.startAccelerometerUpdates(to: queue) { [self] data, _ in
            guard let data = data else { return }
            let x = data.acceleration.x
            let y = data.acceleration.y
            let z = data.acceleration.z
            let mag = sqrt(x*x + y*y + z*z)
            
            let delta = abs(mag - 1.0)
            if delta >= self.magnitudeThreshold {
                let now = Date()
                if now.timeIntervalSince(self.lastTriggerAt) >= self.cooldown {
                    self.lastTriggerAt = now
                    DispatchQueue.main.async {
                        self.status = "presence detected"
                        self.firePresenceEvent()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.status = "listening…"
                }
            }
        }
    }
    
    private func firePresenceEvent() {
        guard !userUID.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        
        db.collection("users").document(uid)
            .setData(["lastPresenceEventAt": FieldValue.serverTimestamp()],
                     merge: true)
        
        if let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "userId": uid,
                "title": config.notificationTitle,
                "body": config.notificationBody
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            URLSession.shared.dataTask(with: req).resume()
        }
    }
    
    private func sendLifecycleNotification(starting: Bool) {
        guard let uid = Auth.auth().currentUser?.uid,
              let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification")
        else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let title = starting
            ? "Started listening: \(config.useCaseName)"
            : "Stopped listening: \(config.useCaseName)"
        let body = starting
            ? "This device is now listening for presence."
            : "This device stopped listening for presence."
        
        let payload: [String: Any] = [
            "userId": uid,
            "title": title,
            "body": body
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: req).resume()
    }
    
    private func stopListening() {
        UIApplication.shared.isIdleTimerDisabled = false
        motion.stopAccelerometerUpdates()
        if let uid = Auth.auth().currentUser?.uid {
            DeviceHeartbeat.shared.setListening(false)
            DeviceHeartbeat.shared.stop()
            Firestore.firestore()
                .collection("users").document(uid)
                .collection("devices").document(deviceID)
                .setData(["isListening": false], merge: true)
        }
        sendLifecycleNotification(starting: false)
        dismiss()
    }
}

 // MARK: - Device Heartbeat
// MARK: - Security Camera Broadcaster (Improved frame rate)

final class SecurityCameraSession: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isRunning = false
    
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "SecurityCamera.VideoQueue")
    
    private var lastUploadTime: Date = .distantPast
    // Lower interval = more frames uploaded to Storage (≈ 3–4 fps here)
    private let uploadInterval: TimeInterval = 0.3
    
    private var userUID: String = ""
    private var deviceID: String = ""
    
    func start(userUID: String, deviceID: String) {
        self.userUID = userUID
        self.deviceID = deviceID
        
        guard !session.isRunning else { return }
        
        session.beginConfiguration()
        session.sessionPreset = .medium // good balance of smoothness + bandwidth
        
        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input)
        else {
            print("SecurityCameraSession: cannot create camera input")
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        
        guard session.canAddOutput(output) else {
            print("SecurityCameraSession: cannot add video output")
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        
        session.commitConfiguration()
        session.startRunning()
        
        DispatchQueue.main.async {
            self.isRunning = true
        }
    }
    
    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastUploadTime) >= uploadInterval else { return }
        lastUploadTime = now
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        let uiImage = UIImage(cgImage: cg)
        guard let jpeg = uiImage.jpegData(compressionQuality: 0.4) else { return }
        
        uploadFrame(data: jpeg)
    }
    
    private func uploadFrame(data: Data) {
        guard !userUID.isEmpty, !deviceID.isEmpty else { return }
        
        let storage = Storage.storage()
        let path = "securityCameras/\(userUID)/\(deviceID)/latest.jpg"
        let ref = storage.reference().child(path)
        
        ref.putData(data, metadata: nil) { _, error in
            if let error = error {
                print("SecurityCameraSession: upload error \(error.localizedDescription)")
            }
        }
    }
}

// SwiftUI wrapper to preview the local camera feed in real time
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.videoOrientation = .portrait
        view.layer.addSublayer(layer)
        context.coordinator.previewLayer = layer
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    final class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// Main broadcaster view to use on the "camera" phone
struct SecurityCameraBroadcasterView: View {
    let useCaseName: String
    
    @StateObject private var cameraSession = SecurityCameraSession()
    @AppStorage("userUID") private var userUID: String = ""
    private var deviceID: String { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack(alignment: .bottom) {
            if cameraSession.isRunning {
                CameraPreview(session: cameraSessionSession)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
            
            VStack(spacing: 8) {
                Text(useCaseName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.top, 12)
                
                Text("Streaming camera at higher frame rate for a smoother live feed.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                Button(role: .destructive) {
                    stop()
                } label: {
                    Label("Stop Security Camera", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding()
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            start()
        }
    }
    
    private var cameraSessionSession: AVCaptureSession {
        // tiny helper so CameraPreview can get the underlying AVCaptureSession
        let mirror = Mirror(reflecting: cameraSession)
        if let session = mirror.children.first(where: { $0.label == "session" })?.value as? AVCaptureSession {
            return session
        }
        return AVCaptureSession()
    }
    
    private func start() {
        guard !userUID.isEmpty else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        
        if let uid = Auth.auth().currentUser?.uid {
            DeviceHeartbeat.shared.start(userUID: uid, deviceID: deviceID)
            DeviceHeartbeat.shared.setListening(true, task: useCaseName)
        }
        
        cameraSession.start(userUID: userUID, deviceID: deviceID)
    }
    
    private func stop() {
        UIApplication.shared.isIdleTimerDisabled = false
        cameraSession.stop()
        if let uid = Auth.auth().currentUser?.uid {
            DeviceHeartbeat.shared.setListening(false)
            DeviceHeartbeat.shared.stop()
            Firestore.firestore()
                .collection("users").document(uid)
                .collection("devices").document(deviceID)
                .setData(["isListening": false], merge: true)
        }
        dismiss()
    }
}




 final class DeviceHeartbeat {
 static let shared = DeviceHeartbeat()
 private init() {}
 
 private var timer: Timer?
 private var userUID: String = ""
 private var deviceID: String = ""
 private var isListening = false


         private var currentTask: String?
         private var lastThermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
         private var lastThermalAlertAt: Date = .distantPast
         private let thermalCooldown: TimeInterval = 300 // 5 minutes between alerts
     func start(userUID: String, deviceID: String) {
         self.userUID = userUID
         self.deviceID = deviceID
         
         UIDevice.current.isBatteryMonitoringEnabled = true
         postHeartbeat(task: currentTask)
         timer?.invalidate()
         timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
             self?.postHeartbeat(task: self?.currentTask)
         }
     }

     func stop() {
         timer?.invalidate()
         timer = nil
         UIDevice.current.isBatteryMonitoringEnabled = false
     }

     func setListening(_ listening: Bool, task: String? = nil) {
         isListening = listening
         if let task = task {
             currentTask = task
         }
         postHeartbeat(task: currentTask)
     }
     private func checkThermalIfNeeded(activeTask: String?) {
         // Only care if some function is actually listening
         guard isListening else { return }
         
         let state = ProcessInfo.processInfo.thermalState
         lastThermalState = state
         
         // Only act on serious or critical
         guard state == .serious || state == .critical else { return }
         
         let now = Date()
         guard now.timeIntervalSince(lastThermalAlertAt) >= thermalCooldown else { return }
         
         lastThermalAlertAt = now
         
         guard let url = URL(string: "https://us-central1-notifymailbox-d9657.cloudfunctions.net/sendMailNotification") else { return }
         
         var req = URLRequest(url: url)
         req.httpMethod = "POST"
         req.setValue("application/json", forHTTPHeaderField: "Content-Type")
         
         let stateText = (state == .critical) ? "critical" : "high"
         let title = "Device temperature \(stateText)"
         
         let taskText = activeTask ?? "a sensor"
         let body = "The device \(UIDevice.current.name) reached a \(stateText) temperature while running \"\(taskText)\". Consider moving it to a cooler place or ending the session."
         
         let payload: [String: Any] = [
             "userId": userUID,
             "title": title,
             "body": body
         ]
         req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
         
         URLSession.shared.dataTask(with: req).resume()
     }
 /*
 private func postHeartbeat(task: String? = nil) {
 guard !userUID.isEmpty, !deviceID.isEmpty else { return }
 let db = Firestore.firestore()
 
 let level = UIDevice.current.batteryLevel
 let batteryPct = level < 0 ? nil : Int((max(0, min(1, level)) * 100).rounded())
 
 var payload: [String: Any] = [
 "isActive": true,
 "updatedAt": FieldValue.serverTimestamp(),
 "isListening": isListening
 ]
 
 if let pct = batteryPct { payload["battery"] = pct }
 if let task = task { payload["task"] = task }
 
 payload["model"] = UIDevice.current.model
 payload["name"] = UIDevice.current.name
 payload["bundleID"] = Bundle.main.bundleIdentifier ?? ""
 payload["systemVersion"] = UIDevice.current.systemVersion
 
 db.collection("users").document(userUID)
 .collection("devices").document(deviceID)
 .setData(payload, merge: true)
 }
                     */
     private func postHeartbeat(task: String? = nil) {
         guard !userUID.isEmpty, !deviceID.isEmpty else { return }
         let db = Firestore.firestore()
         
         let level = UIDevice.current.batteryLevel
         let batteryPct = level < 0 ? nil : Int((max(0, min(1, level)) * 100).rounded())
         
         var payload: [String: Any] = [
             "isActive": true,
             "updatedAt": FieldValue.serverTimestamp(),
             "isListening": isListening
         ]
         
         if let pct = batteryPct { payload["battery"] = pct }
         if let task = task { payload["task"] = task }
         
         let state = UIDevice.current.batteryState
         let batteryState: String
         switch state {
         case .charging:  batteryState = "charging"
         case .full:      batteryState = "full"
         case .unplugged: batteryState = "unplugged"
         case .unknown:   fallthrough
         @unknown default: batteryState = "unknown"
         }
         
         payload["batteryState"] = batteryState
         payload["isPluggedIn"] = (state == .charging || state == .full)
         payload["lowPowerMode"] = ProcessInfo.processInfo.isLowPowerModeEnabled
         
         payload["model"] = UIDevice.current.model
         payload["name"] = UIDevice.current.name
         payload["bundleID"] = Bundle.main.bundleIdentifier ?? ""
         payload["systemVersion"] = UIDevice.current.systemVersion
         
         db.collection("users").document(userUID)
             .collection("devices").document(deviceID)
             .setData(payload, merge: true)
         
         // NEW: check thermal state whenever we heartbeat
         checkThermalIfNeeded(activeTask: task)
     }
 }
 
 // MARK: - Small UI Helpers
 
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
 
 private struct Tag: View {
 let text: String
 init(_ text: String) { self.text = text }
 var body: some View {
 Text(text)
 .font(.caption2)
 .padding(.horizontal, 8)
 .padding(.vertical, 4)
 .background(.ultraThinMaterial)
 .clipShape(Capsule())
 } }
 


