
 import SwiftUI
 import Firebase
 import FirebaseMessaging
 import UserNotifications
 import AuthenticationServices
 import CryptoKit
 import UIKit
 import CoreMotion
 import AVFoundation
 
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
 
 struct HomeView: View {
 let userUID: String
 @State private var mailDetected = false
 @State private var errorMessage: String?
 @State private var activeTasksSummary: String = ""
 private let db = Firestore.firestore()
 
 var body: some View {
 ScrollView {
 VStack(spacing: 16) {
 
 // Active task card
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
 Text("Turn on a function in the Functions tab (e.g., Mailbox Notifier or Vibration Sensor) to start listening.")
 .font(.caption)
 .foregroundStyle(.secondary)
 } else {
 Text("This device is currently listening. You can stop it from the relevant Function detail screen.")
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 }
 .frame(maxWidth: .infinity, alignment: .leading)
 .padding(16)
 .background(.thinMaterial)
 .clipShape(RoundedRectangle(cornerRadius: 16))
 .padding(.horizontal)
 
 // Mail status card
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
 
 // Controls
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
 .onAppear {
 listenForMail()
 subscribeActiveTask()
 }
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
 
 func subscribeActiveTask() {
 guard let uid = Auth.auth().currentUser?.uid else { return }
 let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
 
 db.collection("users").document(uid)
 .collection("devices").document(deviceID)
 .addSnapshotListener { snap, _ in
 guard let data = snap?.data() else { activeTasksSummary = ""; return }
 let listening = data["isListening"] as? Bool ?? false
 let task = data["task"] as? String ?? ""
 if listening, !task.isEmpty {
 activeTasksSummary = "Active: \(task)"
 } else {
 activeTasksSummary = ""
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
 subtitle: "Detect mail + push alerts",
 systemImage: "envelope.badge",
 status: .available,
 info: "Uses screen auto-brightness change (no camera) to detect openings. Sends push to all signed-in devices via FCM."
 ),
 .init(
 title: "Security Camera",
 subtitle: "Visual checks (coming soon)",
 systemImage: "camera.viewfinder",
 status: .planned,
 info: "Turn your old phone into a basic security camera with snapshots or short clips. Logic coming in a future update."
 ),
 .init(
 title: "Vibration Sensor",
 subtitle: "Detect motion / vibration",
 systemImage: "waveform.path.ecg",
 status: .available,
 info: "Use the accelerometer to detect vibration from appliances, tools, vehicles, or footsteps. Configure a custom notification for any spike."
 ),
 .init(
 title: "Sound Sensor",
 subtitle: "Noise / knock detection",
 systemImage: "ear.badge.waveform",
 status: .available,
 info: "Listen for sound spikes (knocks, barks, alarms, machinery). All audio stays on-device; only events and alerts are sent."
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
 title: "QR / Barcode",
 subtitle: "Scan & log",
 systemImage: "qrcode.viewfinder",
 status: .available,
 info: "Use the camera to scan codes and log events (arrivals, packages)."
 ),
 .init(
 title: "Dashcam",
 subtitle: "Auto-record while moving",
 systemImage: "car.rear.fill",
 status: .planned,
 info: "Records when motion exceeds threshold and device is powered. Overwrites oldest clips (ring buffer)."
 ),
 .init(
 title: "Baby Monitor",
 subtitle: "Low-latency audio",
 systemImage: "figure.2.and.child.holdinghands",
 status: .planned,
 info: "One-tap audio streaming to another device in the app. Local network preferred."
 ),
 .init(
 title: "Pet Watcher",
 subtitle: "Motion + barks",
 systemImage: "pawprint.fill",
 status: .planned,
 info: "Detects motion in a zone and higher SPL spikes suggestive of barks; sends a clip and alert."
 ),
 .init(
 title: "Doorbell / Knock",
 subtitle: "Detect door knocks",
 systemImage: "bell.circle.fill",
 status: .available,
 info: "Use sound + motion combo near a door to detect knocks/rings and push an alert with timestamp."
 ),
 .init(
 title: "Light Level",
 subtitle: "Via camera analysis",
 systemImage: "lightbulb.fill",
 status: .available,
 info: "Approximates ambient light using the camera feed (iOS does not expose the ambient light sensor directly to apps)."
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
 Text("Choose a function to turn this device into a sensor, notifier, or simple camera. You can customize every use case.")
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
 if !device.systemVersion.isEmpty {
 Text("iOS \(device.systemVersion)")
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
 Text("User ID: \(user.uid)")
 .font(.caption)
 .foregroundStyle(.secondary)
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
 
 struct VibrationSensorConfig {
 let useCaseName: String
 let notificationTitle: String
 let notificationBody: String
 }
 
 struct SoundSensorConfig {
 let useCaseName: String
 let notificationTitle: String
 let notificationBody: String
 let threshold: Float
 }
 
 struct PresenceSensorConfig {
 let useCaseName: String
 let notificationTitle: String
 let notificationBody: String
 }
 
 // MARK: - Function Detail (Enable + Specialized Setup)
 
 struct FunctionDetailView: View {
 let userUID: String
 let item: FunctionsView.FunctionItem
 @State private var isEnabling = false
 @State private var enabled = false
 
 var body: some View {
 ScrollView {
 VStack(alignment: .leading, spacing: 16) {
 HStack(spacing: 12) {
 Image(systemName: item.systemImage)
 .font(.system(size: 34, weight: .bold))
 VStack(alignment: .leading) {
 Text(item.title).font(.title2.bold())
 Text(item.subtitle)
 .font(.subheadline)
 .foregroundStyle(.secondary)
 }
 Spacer()
 }
 
 Text(item.info)
 .font(.body)
 
 Divider()
 
 VStack(alignment: .leading, spacing: 8) {
 Text("Setup Preview").font(.headline)
 Text("Tapping Enable will create or update a config document for \(item.title) under your user profile. You can adjust use-case and notification text for sensor-based functions.")
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
 enabled ? "Enabled" : "Enable \(item.title)",
 systemImage: enabled ? "checkmark.circle" : "play.circle"
 )
 .frame(maxWidth: .infinity)
 }
 }
 .buttonStyle(.borderedProminent)
 .disabled(isEnabling)
 
 // Mailbox-specific UI
 if item.title == "Mailbox Notifier" {
 Divider().padding(.top, 8)
 MailboxNotifierSetupView()
 } else if item.title == "Vibration Sensor" {
 Divider().padding(.top, 8)
 VibrationSensorSetupView(functionTitle: item.title)
 } else if item.title == "Sound Sensor" {
 Divider().padding(.top, 8)
 SoundSensorSetupView(functionTitle: item.title)
 } else if item.title == "Presence" {
 Divider().padding(.top, 8)
 PresenceSensorSetupView(functionTitle: item.title)
 }
 // Security Camera + other planned functions are UI-only for now
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
 let doc = db.collection("users").document(uid)
 .collection("functions").document(item.title)
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
 
 // MARK: - Mailbox Notifier Setup + Listening (Brightness-based)
 
 struct MailboxNotifierSetupView: View {
 @State private var allowNotifications = false
 @State private var disableAutoLock = false
 @State private var keepPluggedIn = false
 @State private var placePhoneFaceUp = false
 
 @State private var hasStartedTimer = false
 @State private var countdown = 30
 @State private var pushToListening = false
 
 private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
 
 var body: some View {
 VStack(alignment: .leading, spacing: 16) {
 Text("Before You Begin").font(.headline)
 
 VStack(alignment: .leading, spacing: 10) {
 ChecklistRow(isOn: $allowNotifications,
 title: "Allow Notifications",
 subtitle: "Settings → Notifications → Allow for this app.")
 ChecklistRow(isOn: $disableAutoLock,
 title: "Disable Auto-Lock (Temporarily)",
 subtitle: "Settings → Display & Brightness → Auto-Lock → set longer while testing.")
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
 
 if !hasStartedTimer && !pushToListening {
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
 MailboxListeningView()
 } label: {
 EmptyView()
 }
 .hidden()
 }
 }
 
 private var allRequiredChecks: Bool {
 allowNotifications && disableAutoLock && keepPluggedIn && placePhoneFaceUp
 }
 }
 
 struct MailboxListeningView: View {
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
 .onAppear {
 baseline = max(UIScreen.main.brightness, 0.001)
 current = UIScreen.main.brightness
 status = "armed"
 UIApplication.shared.isIdleTimerDisabled = true
 
 if let uid = Auth.auth().currentUser?.uid {
 DeviceHeartbeat.shared.start(userUID: uid, deviceID: deviceID)
 DeviceHeartbeat.shared.setListening(true, task: "Mailbox Notifier")
 }
 
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
 .onDisappear {
 stopListening()
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
 req.httpBody = try? JSONSerialization.data(withJSONObject: ["userId": uid])
 URLSession.shared.dataTask(with: req).resume()
 }
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
 }
 }
 
 // MARK: - Vibration Sensor (Config + Detector + Listening)
 
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
 
 @State private var allowNotifications = false
 @State private var disableAutoLock = false
 @State private var keepPluggedIn = false
 @State private var placeFirmly = false
 
 @State private var useCaseName: String = ""
 @State private var notificationTitle: String = ""
 @State private var notificationBody: String = ""
 
 @State private var pushToListening = false
 
 private let db = Firestore.firestore()
 
 var body: some View {
 VStack(alignment: .leading, spacing: 16) {
 Text("Before You Begin").font(.headline)
 
 VStack(alignment: .leading, spacing: 10) {
 ChecklistRow(isOn: $allowNotifications,
 title: "Allow Notifications",
 subtitle: "Settings → Notifications → Allow for this app.")
 ChecklistRow(isOn: $disableAutoLock,
 title: "Disable Auto-Lock (Temporarily)",
 subtitle: "Settings → Display & Brightness → Auto-Lock → longer while testing.")
 ChecklistRow(isOn: $keepPluggedIn,
 title: "Keep Device Plugged In",
 subtitle: "Recommended for long-running monitoring.")
 ChecklistRow(isOn: $placeFirmly,
 title: "Place Phone Firmly on Surface",
 subtitle: "E.g., on a dryer, machine, vehicle, workbench, or shelf.")
 }
 .padding(12)
 .background(.ultraThinMaterial)
 .clipShape(RoundedRectangle(cornerRadius: 12))
 
 VStack(alignment: .leading, spacing: 8) {
 Text("Customize This Sensor").font(.headline)
 
 TextField("What are you monitoring? (e.g. Dryer, Generator, Workbench)",
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
 .disabled(!allRequiredChecks)
 .animation(.easeInOut, value: allRequiredChecks)
 
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
 
 private var allRequiredChecks: Bool {
 allowNotifications && disableAutoLock && keepPluggedIn && placeFirmly
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
 .onAppear {
 UIApplication.shared.isIdleTimerDisabled = true
 
 if let uid = Auth.auth().currentUser?.uid {
 DeviceHeartbeat.shared.start(userUID: uid, deviceID: deviceID)
 DeviceHeartbeat.shared.setListening(true, task: config.useCaseName)
 }
 
 detector.onSpike = { [self] in
 self.fireVibrationEvent()
 }
 detector.start()
 }
 .onDisappear {
 stopListening()
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
 
 @State private var allowNotifications = false
 @State private var disableAutoLock = false
 @State private var keepPluggedIn = false
 @State private var placeNearSource = false
 
 @State private var useCaseName: String = ""
 @State private var notificationTitle: String = ""
 @State private var notificationBody: String = ""
 @State private var thresholdString: String = "0.7"
 
 @State private var pushToListening = false
 
 private let db = Firestore.firestore()
 
 var body: some View {
 VStack(alignment: .leading, spacing: 16) {
 Text("Before You Begin").font(.headline)
 
 VStack(alignment: .leading, spacing: 10) {
 ChecklistRow(isOn: $allowNotifications,
 title: "Allow Notifications",
 subtitle: "Settings → Notifications → Allow for this app.")
 ChecklistRow(isOn: $disableAutoLock,
 title: "Disable Auto-Lock (Temporarily)",
 subtitle: "Settings → Display & Brightness → Auto-Lock → longer while testing.")
 ChecklistRow(isOn: $keepPluggedIn,
 title: "Keep Device Plugged In",
 subtitle: "Recommended for long-running sound monitoring.")
 ChecklistRow(isOn: $placeNearSource,
 title: "Place Phone Near Sound Source",
 subtitle: "E.g., near a door, pet area, machine, or alarm.")
 }
 .padding(12)
 .background(.ultraThinMaterial)
 .clipShape(RoundedRectangle(cornerRadius: 12))
 
 VStack(alignment: .leading, spacing: 8) {
 Text("Customize This Sensor").font(.headline)
 
 TextField("What are you monitoring? (e.g. Knocks, Barks, Alarm)",
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
 .disabled(!allRequiredChecks)
 .animation(.easeInOut, value: allRequiredChecks)
 
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
 
 private var allRequiredChecks: Bool {
 allowNotifications && disableAutoLock && keepPluggedIn && placeNearSource
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
 .onAppear {
 UIApplication.shared.isIdleTimerDisabled = true
 status = "listening…"
 
 if let uid = Auth.auth().currentUser?.uid {
 DeviceHeartbeat.shared.start(userUID: uid, deviceID: deviceID)
 DeviceHeartbeat.shared.setListening(true, task: config.useCaseName)
 }
 
 monitor.start()
 startEvaluator()
 }
 .onDisappear {
 stopListening()
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
 }
 }
 
 // MARK: - Presence Sensor (Config + Listening)
 
 struct PresenceSensorSetupView: View {
 let functionTitle: String
 
 @State private var allowNotifications = false
 @State private var disableAutoLock = false
 @State private var keepPluggedIn = false
 @State private var placeInArea = false
 
 @State private var useCaseName: String = ""
 @State private var notificationTitle: String = ""
 @State private var notificationBody: String = ""
 
 @State private var pushToListening = false
 
 private let db = Firestore.firestore()
 
 var body: some View {
 VStack(alignment: .leading, spacing: 16) {
 Text("Before You Begin").font(.headline)
 
 VStack(alignment: .leading, spacing: 10) {
 ChecklistRow(isOn: $allowNotifications,
 title: "Allow Notifications",
 subtitle: "Settings → Notifications → Allow for this app.")
 ChecklistRow(isOn: $disableAutoLock,
 title: "Disable Auto-Lock (Temporarily)",
 subtitle: "Settings → Display & Brightness → Auto-Lock → longer while testing.")
 ChecklistRow(isOn: $keepPluggedIn,
 title: "Keep Device Plugged In",
 subtitle: "Recommended when monitoring an area.")
 ChecklistRow(isOn: $placeInArea,
 title: "Place Phone in Target Area",
 subtitle: "E.g., shop entrance, office desk, wildlife viewing area.")
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
 .disabled(!allRequiredChecks)
 .animation(.easeInOut, value: allRequiredChecks)
 
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
 
 private var allRequiredChecks: Bool {
 allowNotifications && disableAutoLock && keepPluggedIn && placeInArea
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
 }
 }
 
 // MARK: - Device Heartbeat
 
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
 }
 }
 
