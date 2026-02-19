
import SwiftUI
import AVFoundation
import Firebase
import FirebaseFirestore
import FirebaseAuth
import UIKit
import CoreImage
import SwiftUI
import AVFoundation
import Firebase
import FirebaseFirestore
import FirebaseAuth
import UIKit
import CoreImage
import CoreVideo      // ✅ add this
import CoreMedia      // ✅ add this (safe/typical with CMSampleBuffer)
// MARK: - Setup View

struct LightChangeSetupView: View {
    let functionTitle: String
    let deviceID: String
    @State private var sendNotifications: Bool = true
    @State private var notificationTitle: String = ""
    @State private var notificationBody: String = ""

    @State private var createdTaskId: String = ""
    @State private var pushToListening: Bool = false

    private let db = Firestore.firestore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                // Keep it simple, hands-free, no overwhelm
                BeforeYouBeginCard(
                    title: "Before you begin",
                    subtitle: "Hands-free mailbox monitoring",
                    bullets: [
                        ("Use the front camera", "Place the phone so the face camera points into the mailbox."),
                        ("Plug in if possible", "Long listening sessions can drain battery."),
                        ("Start and leave it", "The task runs hands-free once started.")
                    ]
                )

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Send notifications to all my devices", isOn: $sendNotifications)
                        .tint(.green)

                    if sendNotifications {
                        Text("Notification")
                            .font(.headline)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Subject")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            TextField("Mail detected", text: $notificationTitle)
                                .modifier(ModernTextFieldSurface())

                            Text("Body")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            TextField("Your mailbox sensor detected mail activity.", text: $notificationBody)
                                .modifier(ModernTextFieldSurface())
                        }
                    }
                }
                .padding(16)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    let taskId = makeTaskId()
                    createdTaskId = taskId
                    pushToListening = true

                    forceEndAllTasks(endedBy: "Begin Mailbox Camera Listener") { _ in
                        createTaskOneWrite(taskId: taskId)
                    }
                } label: {
                    Label("Start Mailbox Camera", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                NavigationLink(isActive: $pushToListening) {
                    let cfg = LightChangeConfig(
                        sendNotifications: sendNotifications,
                        notificationTitle: effectiveNotificationTitle(),
                        notificationBody: effectiveNotificationBody()
                    )

                    LightChangeListeningView(
                        config: cfg,
                        taskId: createdTaskId,
                        userUID: Auth.auth().currentUser?.uid ?? "",
                        deviceID: deviceID
                    )
                } label: { EmptyView() }
                .hidden()
            }
            .padding()
        }
        .navigationTitle(functionTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func effectiveNotificationTitle() -> String {
        guard sendNotifications else { return "Mail detected" }
        return notificationTitle.isEmpty ? "Mail detected" : notificationTitle
    }

    private func effectiveNotificationBody() -> String {
        guard sendNotifications else { return "Your mailbox sensor detected activity." }
        return notificationBody.isEmpty ? "Your mailbox sensor detected activity." : notificationBody
    }

    private func makeTaskId() -> String {
        db.collection("_tmp").document().documentID
    }



    private func createTaskOneWrite(taskId: String) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }

       
       
        let cachedName = UserDefaults.standard.string(forKey: "local_device_name")
        let fallbackName = UIDevice.current.name
        let deviceName = (cachedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? cachedName!
            : fallbackName

        let ref = db.collection("users").document(uid).collection("tasks").document(taskId)

        let payload: [String: Any] = [
            "name": "Light Change",
            "type": "camera_mailbox",

            "deviceID": deviceID,
            "deviceName": deviceName,


            "startedAt": Timestamp(date: Date()),
            "endedAt": NSNull(),

            "sendNotifications": sendNotifications,
            "notificationTitle": effectiveNotificationTitle(),
            "notificationBody": effectiveNotificationBody(),

            // internal versioning for future tweaks
            "cameraTaskVersion": 1,
            "cameraPosition": "front"
        ]

        ref.setData(payload, merge: false) { err in
            if let err = err {
                print("Mailbox camera task create failed: \(err.localizedDescription)")
            }
        }
    }
}

// MARK: - Config

struct LightChangeConfig: Hashable {
    let sendNotifications: Bool
    let notificationTitle: String
    let notificationBody: String
}

// MARK: - Listening View

struct LightChangeListeningView: View {
    let config: LightChangeConfig
    let taskId: String
    let userUID: String
    let  deviceID: String
    
    @StateObject private var camera = LightChangeCameraMonitor()

    @State private var status: String = "preparing…"

    // Firestore logging (optional but consistent)
    @State private var samples: [SessionSamplePoint] = []
    @State private var events: [[String: Any]] = []

    @State private var sampleTimer: Timer? = nil

    // Cooldown to prevent spam
    @State private var lastNotifyAt: Date? = nil
    private let notifyCooldown: TimeInterval = 60

    // ✅ ONLY an initial "arming" buffer. During this, detections are ignored.
    @State private var startedAt: Date = .distantPast
    @State private var isArmed: Bool = false
    @State private var armWorkItem: DispatchWorkItem? = nil
    private let armDelay: TimeInterval = 10

    private let db = Firestore.firestore()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {

            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Light Change")
                        .font(.title3.bold())
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal)

            CameraPreviewView(session: camera.session)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.primary.opacity(0.10), lineWidth: 1)
                )
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("Hands-free monitoring")
                    .font(.headline)
                Text("Leave the phone in place. The first 10 seconds are ignored so you can place it in the cabinet. After that, when light increases, a push notification is sent.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Spacer()

            Button(role: .destructive) {
                stopListening()
            } label: {
                Label("Stop Listening", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.bottom, 18)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true

            startedAt = Date()
            isArmed = false
            status = "starting camera…"

            camera.onActivityDetected = { strength in
                handleActivityDetected(strength: strength)
            }

            camera.startFrontCamera()
            startSampling()

            // ✅ Arm after 10s. No delayed notification scheduling.
            armWorkItem?.cancel()
            let work = DispatchWorkItem {
                isArmed = true
                status = "listening…"
            }
            armWorkItem = work
            status = "arming (10s)…"
            DispatchQueue.main.asyncAfter(deadline: .now() + armDelay, execute: work)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            armWorkItem?.cancel()
            armWorkItem = nil
            sampleTimer?.invalidate()
            sampleTimer = nil
            camera.stop()
        }
    }

    // MARK: - Sampling

    private func startSampling() {
        sampleTimer?.invalidate()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let p = SessionSamplePoint(time: Date(), value: camera.activityLevel)
            samples.append(p)
            if samples.count > 900 { samples.removeFirst(samples.count - 900) }
        }
    }

    // MARK: - Detection handling (NO per-event delay)

    private func handleActivityDetected(strength: Double) {
        let now = Date()

        // ✅ Ignore any detection before arming completes
        guard isArmed else {
            // Keep status stable; do not spam UI.
            return
        }

        // status + event log
        status = "activity detected"
        events.append([
            "t": Timestamp(date: now),
            "type": "mail_activity_detected",
            "strength": strength
        ])

        // If notifications disabled, do nothing further
        guard config.sendNotifications else { return }

        // Cooldown guard (prevents spam if cabinet flutters / repeated exposure)
        if let last = lastNotifyAt, now.timeIntervalSince(last) < notifyCooldown {
            return
        }

        lastNotifyAt = now
        status = "sending notification…"

        NotificationService.shared.sendPush(
            subject: config.notificationTitle,
            body: config.notificationBody,
            taskId: taskId,
            eventType: "mail_activity_detected",
            sourceDeviceID: deviceID
        )

        // Return to listening state quickly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if isArmed { status = "listening…" }
        }
    }

    // MARK: - Stop / Firestore write

    private func stopListening() {
        UIApplication.shared.isIdleTimerDisabled = false
        armWorkItem?.cancel()
        armWorkItem = nil
        sampleTimer?.invalidate()
        sampleTimer = nil
        camera.stop()
        endTask()
        dismiss()
    }

    private func endTask() {
        guard !userUID.isEmpty else { return }
        let ref = db.collection("users").document(userUID).collection("tasks").document(taskId)

        var payload: [String: Any] = [
            "endedAt": Timestamp(date: Date()),
            "endedBy": "user_stopped"
        ]

        payload["samples"] = samples.map { ["t": Timestamp(date: $0.time), "v": $0.value] }
        payload["events"] = events

        ref.setData(payload, merge: true) { err in
            if let err = err {
                print("Mailbox camera task end failed: \(err.localizedDescription)")
            }
        }
    }

 
}

// MARK: - Camera Monitor

final class LightChangeCameraMonitor: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()

    @Published var activityLevel: Double = 0.0 // 0..1 normalized for chart/UI

    // Callbacks
    var onActivityDetected: ((Double) -> Void)?

    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "MailboxCameraMonitor.frames")

    private let ciContext = CIContext(options: nil)

    // Internal detection (no user-facing sensitivity)
    private var baseline: Double? = nil
    private var lastTriggeredAt: Date = .distantPast

    // Internal: tuned to be conservative + stable
    private let warmupFrames = 18
    private var frameCount = 0
    private let triggerDelta: Double = 0.12        // internal threshold
    private let minTriggerGap: TimeInterval = 3.0  // internal debounce

    func startFrontCamera() {
        stop()

        session.beginConfiguration()
        session.sessionPreset = .medium

        // FRONT camera
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) { session.addInput(input) }
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]

        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        if session.canAddOutput(output) { session.addOutput(output) }

        if let conn = output.connection(with: .video) {
            conn.videoOrientation = .portrait
            conn.isVideoMirrored = true
        }

        session.commitConfiguration()

        baseline = nil
        frameCount = 0
        lastTriggeredAt = .distantPast
        activityLevel = 0

        session.startRunning()
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
    }

    // MARK: - Frame processing

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Compute mean luminance-ish quickly via CIAreaAverage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent

        guard let filter = CIFilter(name: "CIAreaAverage") else { return }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let out = filter.outputImage else { return }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(out,
                         toBitmap: &bitmap,
                         rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8,
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        // Luma approximation from RGB
        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0
        let mean = (0.2126 * r + 0.7152 * g + 0.0722 * b)

        frameCount += 1

        // Establish baseline
        if baseline == nil {
            baseline = mean
            return
        }

        guard let baseBefore = baseline else { return }
        let diff = mean - baseBefore
        let delta = abs(diff)

        // normalize for UI charts
        let normalized = min(1.0, max(0.0, delta / 0.35))
        DispatchQueue.main.async {
            self.activityLevel = (self.activityLevel * 0.85) + (normalized * 0.15)
        }

        // Trigger logic: ONLY when light increased (drawer opened)
        let now = Date()
        let shouldTrigger =
            frameCount > warmupFrames &&
            diff >= triggerDelta &&
            now.timeIntervalSince(lastTriggeredAt) >= minTriggerGap

        if shouldTrigger {
            lastTriggeredAt = now
            DispatchQueue.main.async {
                self.onActivityDetected?(delta)
            }
            // Freeze baseline on trigger so the jump doesn't get absorbed immediately
            return
        }

        // Baseline update AFTER trigger evaluation
        if frameCount <= warmupFrames {
            baseline = (baseBefore * 0.90) + (mean * 0.10)
        } else {
            baseline = (baseBefore * 0.985) + (mean * 0.015)
        }
    }
}

// MARK: - Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
