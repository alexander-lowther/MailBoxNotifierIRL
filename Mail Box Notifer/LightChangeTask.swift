

import SwiftUI
import Firebase
import FirebaseFirestore
import FirebaseAuth
import AVFoundation
import UserNotifications
import UIKit

// MARK: - Setup View

struct LightChangeSensorSetupView: View {
    let functionTitle: String

    @State private var sensitivity: Double = 0.18          // normalized luminance delta (0..1)
    @State private var requireSustainedMs: Double = 250     // avoid false triggers
    @State private var sendNotifications: Bool = true
    @State private var notificationTitle: String = "Opened"
    @State private var notificationBody: String = "Light changed — your compartment was opened."

    @State private var createdTaskId: String = ""
    @State private var pushToListening: Bool = false

    private let db = Firestore.firestore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                BeforeYouBeginCard(
                    title: "Before you begin",
                    subtitle: "Best setup for reliable detection",
                    bullets: [
                        ("Camera facing up", "Place the phone with the screen down and camera facing the opening."),
                        ("Press Start before placing", "Start listening first, then set it in the mailbox/cabinet."),
                        ("Avoid moving the phone", "Movement can cause brightness swings and false triggers.")
                    ]
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Sensitivity")
                        .font(.headline)

                    HStack {
                        Text(String(format: "%.2f", sensitivity))
                            .font(.system(.title3, design: .rounded).bold())
                        Spacer()
                    }

                    Slider(value: $sensitivity, in: 0.05...0.60, step: 0.01)
                        .tint(.green)

                    Text("Higher sensitivity triggers more easily. Start around 0.15–0.25.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Divider().opacity(0.25)

                    Text("Stability (ms)")
                        .font(.headline)

                    HStack {
                        Text("\(Int(requireSustainedMs)) ms")
                            .font(.system(.title3, design: .rounded).bold())
                        Spacer()
                    }

                    Slider(value: $requireSustainedMs, in: 0...1000, step: 50)
                        .tint(.green)

                    Text("Requires the change to persist briefly to avoid false positives.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                // Custom notifications (like SoundTask)
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Send notifications", isOn: $sendNotifications)
                        .tint(.green)

                    TextField("Notification title", text: $notificationTitle)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!sendNotifications)

                    TextField("Notification body", text: $notificationBody, axis: .vertical)
                        .lineLimit(2, reservesSpace: true)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!sendNotifications)

                    Text("Tip: keep the title short (e.g., “Mailbox opened”).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    let taskId = makeTaskId()
                    createdTaskId = taskId
                    pushToListening = true

                    forceEndAllTasks(endedBy: "Begin LightChange Listener") { _ in
                        createTaskOneWrite(taskId: taskId)
                    }
                } label: {
                    Label("Start Light Change Sensor", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                NavigationLink(isActive: $pushToListening) {
                    let cfg = LightChangeConfig(
                        sensitivity: sensitivity,
                        requireSustainedMs: Int(requireSustainedMs),
                        sendNotifications: sendNotifications,
                        notificationTitle: notificationTitle,
                        notificationBody: notificationBody
                    )
                    LightChangeListeningView(
                        config: cfg,
                        taskId: createdTaskId,
                        userUID: Auth.auth().currentUser?.uid ?? ""
                    )
                } label: { EmptyView() }
                .hidden()
            }
            .padding()
        }
        .navigationTitle(functionTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func makeTaskId() -> String {
        db.collection("_tmp").document().documentID
    }

    private func stableDeviceID() -> String {
        if let existing = UserDefaults.standard.string(forKey: "stable_device_id"), !existing.isEmpty {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: "stable_device_id")
        return newID
    }

    private func createTaskOneWrite(taskId: String) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }

        let deviceID = stableDeviceID()
        let cachedName = UserDefaults.standard.string(forKey: "local_device_name")
        let fallbackName = UIDevice.current.name
        let deviceName = (cachedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? cachedName!
            : fallbackName

        let ref = db.collection("users").document(uid).collection("tasks").document(taskId)

        let payload: [String: Any] = [
            "name": "Light Change",
            "type": "light_change",
            "deviceID": deviceID,
            "deviceName": deviceName,
            "listenerDeviceID": deviceID,

            "startedAt": Timestamp(date: Date()),
            "endedAt": NSNull(),

            "sensitivity": sensitivity,
            "requireSustainedMs": Int(requireSustainedMs),

            "sendNotifications": sendNotifications,
            "notificationTitle": notificationTitle,
            "notificationBody": notificationBody
        ]

        ref.setData(payload, merge: false) { err in
            if let err = err {
                print("LightChange task create failed: \(err.localizedDescription)")
            }
        }
    }
}

// MARK: - Config

struct LightChangeConfig: Hashable {
    let sensitivity: Double
    let requireSustainedMs: Int
    let sendNotifications: Bool
    let notificationTitle: String
    let notificationBody: String
}

// MARK: - Listening View

struct LightChangeListeningView: View {
    let config: LightChangeConfig
    let taskId: String
    let userUID: String

    @StateObject private var camera = LightChangeCameraMonitor()

    // live toggle + live editable title/body (like SoundTask)
    @State private var sendNotificationsLive: Bool
    @State private var titleLive: String
    @State private var bodyLive: String

    @State private var status: String = "preparing…"
    @State private var events: [[String: Any]] = []

    private let db = Firestore.firestore()
    @Environment(\.dismiss) private var dismiss

    init(config: LightChangeConfig, taskId: String, userUID: String) {
        self.config = config
        self.taskId = taskId
        self.userUID = userUID
        _sendNotificationsLive = State(initialValue: config.sendNotifications)
        _titleLive = State(initialValue: config.notificationTitle)
        _bodyLive = State(initialValue: config.notificationBody)
    }

    var body: some View {
        VStack(spacing: 14) {

            // Header
            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Light Change")
                        .font(.title3.bold())
                    Text("Sensitivity: \(String(format: "%.2f", config.sensitivity))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    camera.recalibrate()
                    status = "recalibrated"
                } label: {
                    Label("Recalibrate", systemImage: "scope")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            // Center camera preview
            CameraPreviewView(session: camera.session)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal)
                .frame(height: 320)

            // Bubble chips row
            HStack(spacing: 12) {
                BubbleChip(label: "base", value: String(format: "%.2f", camera.baselineLum), isActive: false)
                Spacer(minLength: 0)
                BubbleChip(label: "now", value: String(format: "%.2f", camera.currentLum), isActive: camera.isTriggered)
            }
            .padding(.horizontal)

            BubbleStatus(text: status)

            // Custom notifications controls (compact + bubble-ish)
            VStack(alignment: .leading, spacing: 10) {
                BubbleToggleChip(title: "Notifications", isOn: $sendNotificationsLive)

                TextField("Title", text: $titleLive)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!sendNotificationsLive)

                TextField("Body", text: $bodyLive, axis: .vertical)
                    .lineLimit(2, reservesSpace: true)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!sendNotificationsLive)
            }
            .padding(.horizontal)

            Spacer()

            Button {
                stopAndDismiss()
            } label: {
                Text("Stop Listening")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 18)
        }
        .onAppear {
            requestCameraPermissionIfNeededAndStart()
            if sendNotificationsLive { requestNotificationPermissionIfNeeded() }

            camera.onTrigger = {
                // Log event + notify
                let now = Date()
                events.append([
                    "t": Timestamp(date: now),
                    "type": "light_change_triggered",
                    "baseline": camera.baselineLum,
                    "current": camera.currentLum
                ])

                status = "opened detected"
                maybeNotify()
            }
        }
        .onDisappear {
            camera.stop()
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Stop & persist minimal data

    private func stopAndDismiss() {
        camera.stop()

        let ref = db.collection("users").document(userUID).collection("tasks").document(taskId)

        let payload: [String: Any] = [
            "endedAt": Timestamp(date: Date()),
            "endedReason": "user_stopped",

            "sendNotifications": sendNotificationsLive,
            "notificationTitle": titleLive,
            "notificationBody": bodyLive,

            "events": events
        ]

        ref.setData(payload, merge: true) { err in
            if let err = err {
                print("LightChange end failed: \(err.localizedDescription)")
            }
            dismiss()
        }
    }

    // MARK: - Permissions

    private func requestCameraPermissionIfNeededAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            camera.start(sensitivity: config.sensitivity, requireSustainedMs: config.requireSustainedMs)
            status = "listening…"
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        camera.start(sensitivity: config.sensitivity, requireSustainedMs: config.requireSustainedMs)
                        status = "listening…"
                    } else {
                        status = "camera permission denied"
                    }
                }
            }
        default:
            status = "camera permission denied"
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    // MARK: - Notify

    private func maybeNotify() {
        guard sendNotificationsLive else { return }

        let content = UNMutableNotificationContent()
        content.title = titleLive.isEmpty ? "Opened" : titleLive
        content.body = bodyLive.isEmpty ? "Light changed — opened detected." : bodyLive
        content.sound = .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "lightchange.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
        )
    }
}

// MARK: - Camera Monitor (brightness detector)

final class LightChangeCameraMonitor: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()

    @Published var baselineLum: Double = 0.0
    @Published var currentLum: Double = 0.0
    @Published var isTriggered: Bool = false

    var onTrigger: (() -> Void)?

    private var sensitivity: Double = 0.18
    private var requireSustainedMs: Int = 250

    private var lastCalibratedAt: CFTimeInterval = CACurrentMediaTime()

    // Sustained detection
    private var aboveSince: CFTimeInterval? = nil
    private var lastTriggerAt: CFTimeInterval = 0
    private let triggerCooldown: CFTimeInterval = 1.5  // avoid rapid re-triggers

    private let queue = DispatchQueue(label: "LightChangeCameraQueue")

    func start(sensitivity: Double, requireSustainedMs: Int) {
        self.sensitivity = sensitivity
        self.requireSustainedMs = requireSustainedMs

        configureSessionIfNeeded()
        recalibrate()
        session.startRunning()
    }

    func stop() {
        session.stopRunning()
        aboveSince = nil
        isTriggered = false
    }

    func recalibrate() {
        baselineLum = currentLum
        lastCalibratedAt = CACurrentMediaTime()
        aboveSince = nil
        isTriggered = false
    }

    private var isConfigured = false
    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        if let conn = output.connection(with: .video), conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }

        session.commitConfiguration()
    }

    // MARK: - Sample buffer delegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        // Fast luminance approximation: sample a small grid
        let lum = Self.estimateLuminance(from: imageBuffer)

        DispatchQueue.main.async {
            self.currentLum = lum

            // If baseline is 0 (first frames), set it gently
            if self.baselineLum == 0.0 && (CACurrentMediaTime() - self.lastCalibratedAt) < 1.0 {
                self.baselineLum = lum
            }

            self.evaluateTrigger()
        }
    }

    private func evaluateTrigger() {
        let delta = abs(currentLum - baselineLum)
        let now = CACurrentMediaTime()

        // Treat large change as "opened"
        if delta >= sensitivity {
            if aboveSince == nil { aboveSince = now }
            let sustained = (now - (aboveSince ?? now)) * 1000.0

            if sustained >= Double(requireSustainedMs),
               (now - lastTriggerAt) >= triggerCooldown {
                lastTriggerAt = now
                isTriggered = true
                onTrigger?()
            }
        } else {
            aboveSince = nil
            isTriggered = false
        }
    }

    // MARK: - Luminance estimate

    private static func estimateLuminance(from pixelBuffer: CVPixelBuffer) -> Double {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        // Sample a 10x10 grid
        let gridX = 10
        let gridY = 10
        var sum: Double = 0
        var count: Double = 0

        for gy in 0..<gridY {
            let y = (height * gy) / (gridY + 1)
            for gx in 0..<gridX {
                let x = (width * gx) / (gridX + 1)
                let offset = y * bytesPerRow + x * 4
                let b = Double(ptr[offset + 0])
                let g = Double(ptr[offset + 1])
                let r = Double(ptr[offset + 2])

                // Rec. 709 luma
                let l = 0.2126*r + 0.7152*g + 0.0722*b
                sum += l
                count += 1
            }
        }

        // normalize 0..1
        return (count == 0) ? 0 : (sum / count) / 255.0
    }
}

// MARK: - Camera Preview UIViewRepresentable

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

// MARK: - Bubble helpers (match your existing style from LevelTask_v4)

private struct BubbleChip: View {
    let label: String
    let value: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(.ultraThinMaterial, in: Circle())

            Text(value)
                .font(.system(.headline, design: .rounded).bold())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isActive ? Color.green.opacity(0.18) : Color.black.opacity(0.08))
        .clipShape(Capsule())
    }
}

private struct BubbleToggleChip: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isOn ? "bell.fill" : "bell.slash")
                .foregroundStyle(isOn ? .green : .secondary)
                .frame(width: 24, height: 24)
                .background(.ultraThinMaterial, in: Circle())

            Text(title)
                .font(.subheadline.weight(.semibold))

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.08))
        .clipShape(Capsule())
        .onChange(of: isOn) { newValue in
            if newValue {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
    }
}

private struct BubbleStatus: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial)
            .clipShape(Capsule())
            .padding(.horizontal)
    }
}
