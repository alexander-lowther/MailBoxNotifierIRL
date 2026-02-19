
//
//  CameraTask.swift
//  Mailbox Notifier IRL
//
//  Firebase Relay Camera (NO WebRTC):
//  - Broadcaster captures frames (low-res) and uploads JPEGs to Firebase Storage
//  - Broadcaster updates a Firestore "latest frame pointer" doc
//  - Viewer listens to pointer doc and downloads latest frame
//
//  Tradeoffs:
//  - Works across different Wi-Fi/cellular networks (no LAN requirement)
//  - Delayed feed (seconds behind). Tunable via FPS/quality.
//  - Uses Storage upload/download bandwidth.
//
//  iOS 15+
//

import SwiftUI
import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

// MARK: - Firestore fields (matches your task model needs)

private enum TaskFields {
    static let collection = "tasks"
    static let name = "name"
    static let type = "type"
    static let deviceID = "deviceID"
    static let deviceName = "deviceName"
    static let startedAt = "startedAt"
    static let endedAt = "endedAt"
    static let endedBy = "endedBy"
    static let hasSamples = "hasSamples"

    // optional fields you may already use elsewhere
    static let notificationTitle = "notificationTitle"
    static let notificationBody = "notificationBody"
}

// Relay pointer doc location:
// /users/{uid}/tasks/{taskId}/cameraRelay/state
private enum RelayFields {
    static let coll = "cameraRelay"
    static let doc = "state"
    static let latestPath = "latestPath"
    static let latestTs = "latestTs"
    static let hostDeviceID = "hostDeviceID"
    static let isLive = "isLive"
    static let updatedAt = "updatedAt"
}

// Storage path:
// users/{uid}/tasks/{taskId}/cameraRelayFrames/{timestamp}.jpg
private enum RelayStorage {
    static func framePath(uid: String, taskId: String, tsMillis: Int64) -> String {
        "users/\(uid)/tasks/\(taskId)/cameraRelayFrames/\(tsMillis).jpg"
    }
}

// MARK: - Setup View (called from TasksTab)

/// Called from TasksTab (no taskId yet).
/// Creates the task doc, then navigates to CameraRelayView.
struct CameraRelaySetupView: View {
    let functionTitle: String
    let deviceID: String

    @State private var isWorking = false
    @State private var statusText: String? = nil

    @State private var createdTaskId: String? = nil
    @State private var pushToRun = false

    private let db = Firestore.firestore()

    var body: some View {
        List {
            Section(header: Text(functionTitle)) {
                Text("Streams using Firebase Storage + Firestore pointer. Works across networks but is delayed.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            // Keep config minimal (you asked not to over-engineer).
            Section(header: Text("Notes")) {
                Text("Broadcaster uploads low-res frames periodically. Viewer downloads latest frame.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("Make sure Firebase Storage is enabled and rules allow /users/{uid}/…")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if let statusText {
                Section {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }

            Section {
                Button {
                    statusText = nil
                    createAndStart()
                } label: {
                    Label(isWorking ? "Working…" : "Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
            }

            // iOS 15 safe programmatic navigation
            NavigationLink(isActive: $pushToRun) {
                if let taskId = createdTaskId {
                    CameraRelayView(
                        taskId: taskId,
                        userUID: Auth.auth().currentUser?.uid ?? "",
                        deviceID: deviceID,
                        taskDeviceID: deviceID // creator is broadcaster
                    )
                } else {
                    EmptyView()
                }
            } label: { EmptyView() }
            .hidden()
        }
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func createAndStart() {
        guard !isWorking else { return }
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            statusText = "Not signed in."
            return
        }

        isWorking = true

        let ref = db.collection("users").document(uid)
            .collection(TaskFields.collection).document()

        // IMPORTANT: Your TaskDoc init requires name, deviceID, startedAt, deviceName.
        let taskData: [String: Any] = [
            TaskFields.name: "Camera",
            TaskFields.type: "camera_relay",
            TaskFields.deviceID: deviceID,
            TaskFields.deviceName: UIDevice.current.name,
            TaskFields.startedAt: FieldValue.serverTimestamp(),
            TaskFields.hasSamples: false
        ]

        ref.setData(taskData) { err in
            isWorking = false
            if let err = err {
                statusText = "Failed to create task: \(err.localizedDescription)"
                return
            }
            createdTaskId = ref.documentID
            pushToRun = true
        }
    }
}

// MARK: - Running View

struct CameraRelayView: View {
    let taskId: String
    let userUID: String
    let deviceID: String
    let taskDeviceID: String // broadcaster iff == deviceID

    @StateObject private var vm = CameraRelayVM()

    var body: some View {
        VStack(spacing: 12) {
            header

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.secondarySystemBackground))

                if let img = vm.currentFrame {
                    GeometryReader { geo in
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .padding(10)
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(vm.statusText.isEmpty ? "Waiting…" : vm.statusText)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            }
            .frame(height: 360)

            HStack(spacing: 10) {
                Button {
                    vm.start(taskId: taskId, userUID: userUID, deviceID: deviceID, taskDeviceID: taskDeviceID)
                } label: {
                    Label(vm.isRunning ? "Running…" : "Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isRunning)

                Button(role: .destructive) {
                    vm.stopAll(markNotLive: true)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!vm.isRunning)
            }

            if !vm.debugText.isEmpty {
                Text(vm.debugText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Optional auto-start to reduce clicks:
            // vm.start(...)
        }
        .onDisappear {
            vm.stopAll(markNotLive: deviceID == taskDeviceID)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(deviceID == taskDeviceID ? "Broadcasting (Relay)" : "Viewing (Relay)")
                .font(.headline)
            Text("Cross-network. Delayed feed. Low-res frames.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ViewModel

@MainActor
final class CameraRelayVM: ObservableObject {
    @Published var currentFrame: UIImage? = nil
    @Published var statusText: String = ""
    @Published var debugText: String = ""
    @Published var isRunning: Bool = false

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    private var streamRef: DocumentReference?
    private var listener: ListenerRegistration?

    private var capture: CameraCapture? 

    private var lastSeenPath: String?
    private var uploadInFlight = false

    // Tunables: conservative defaults (stable + cost-aware)
    private let fps: Double = 1.2           // ~1 frame/sec (delayed is OK)
    private let jpegQuality: CGFloat = 0.32 // small
    private let maxDimension: CGFloat = 480 // low-res
    private let maxDownloadBytes: Int64 = 450_000

    func start(taskId: String, userUID: String, deviceID: String, taskDeviceID: String) {
        guard !isRunning else { return }
        isRunning = true
        statusText = ""
        debugText = ""
        currentFrame = nil

        streamRef = db.collection("users").document(userUID)
            .collection(TaskFields.collection).document(taskId)
            .collection(RelayFields.coll).document(RelayFields.doc)

        if deviceID == taskDeviceID {
            startBroadcaster(taskId: taskId, userUID: userUID, deviceID: deviceID)
        } else {
            startViewer()
        }
    }

    func stopAll(markNotLive: Bool) {
        isRunning = false

        listener?.remove()
        listener = nil

        capture?.stop()
        capture = nil

        uploadInFlight = false
        lastSeenPath = nil

        if markNotLive, let ref = streamRef {
            ref.setData([
                RelayFields.isLive: false,
                RelayFields.updatedAt: FieldValue.serverTimestamp()
            ], merge: true)
        }

        statusText = ""
        debugText = ""
    }

    // MARK: - Broadcaster

    private func startBroadcaster(taskId: String, userUID: String, deviceID: String) {
        statusText = "Starting capture…"

        // Mark live (best effort)
        streamRef?.setData([
            RelayFields.isLive: true,
            RelayFields.hostDeviceID: deviceID,
            RelayFields.updatedAt: FieldValue.serverTimestamp()
        ], merge: true)

        let cap = CameraCapture(targetFPS: fps, jpegQuality: jpegQuality, maxDimension: maxDimension)
        capture = cap

        cap.onPreview = { [weak self] img in
            Task { @MainActor in self?.currentFrame = img }
        }

        cap.onJPEG = { [weak self] jpeg in
            guard let self else { return }
            // Hard throttle: do not allow parallel uploads
            if self.uploadInFlight { return }
            self.uploadInFlight = true
            self.uploadFrame(jpeg: jpeg, uid: userUID, taskId: taskId, deviceID: deviceID)
        }

        cap.start()
        statusText = "Broadcasting (delayed)"
    }

    private func uploadFrame(jpeg: Data, uid: String, taskId: String, deviceID: String) {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        let path = RelayStorage.framePath(uid: uid, taskId: taskId, tsMillis: ts)

        let ref = storage.reference(withPath: path)
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        ref.putData(jpeg, metadata: meta) { [weak self] _, err in
            guard let self else { return }

            if let err = err {
                Task { @MainActor in
                    self.debugText = "Upload error: \(err.localizedDescription)"
                    self.uploadInFlight = false
                }
                return
            }

            // Update pointer doc (single doc)
            self.streamRef?.setData([
                RelayFields.latestPath: path,
                RelayFields.latestTs: ts,
                RelayFields.hostDeviceID: deviceID,
                RelayFields.isLive: true,
                RelayFields.updatedAt: FieldValue.serverTimestamp()
            ], merge: true)

            Task { @MainActor in
                self.uploadInFlight = false
            }
        }
    }

    // MARK: - Viewer

    private func startViewer() {
        statusText = "Waiting for frames…"
        currentFrame = nil

        guard let ref = streamRef else {
            statusText = "Missing relay doc."
            isRunning = false
            return
        }

        listener?.remove()
        listener = ref.addSnapshotListener { [weak self] snap, err in
            guard let self else { return }
            Task { @MainActor in
                if let err = err {
                    self.statusText = "Listener error: \(err.localizedDescription)"
                    self.isRunning = false
                    return
                }
                guard let data = snap?.data() else { return }

                let live = (data[RelayFields.isLive] as? Bool) ?? false
                if !live {
                    self.statusText = "Broadcaster not live."
                    return
                }

                guard let path = data[RelayFields.latestPath] as? String, !path.isEmpty else {
                    self.statusText = "No frames yet…"
                    return
                }

                // Avoid re-downloading same frame
                if self.lastSeenPath == path { return }
                self.lastSeenPath = path

                self.downloadFrame(path: path)
            }
        }
    }

    private func downloadFrame(path: String) {
        statusText = "Downloading…"
        let ref = storage.reference(withPath: path)

        ref.getData(maxSize: maxDownloadBytes) { [weak self] data, err in
            guard let self else { return }
            if let err = err {
                Task { @MainActor in
                    self.debugText = "Download error: \(err.localizedDescription)"
                    self.statusText = "Waiting…"
                }
                return
            }
            guard let data = data, let img = UIImage(data: data) else {
                Task { @MainActor in self.statusText = "Bad frame data." }
                return
            }
            Task { @MainActor in
                self.currentFrame = img
                self.statusText = "Viewing (delayed)"
            }
        }
    }
}

// MARK: - Camera capture: AVCaptureSession -> JPEG throttled

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onJPEG: ((Data) -> Void)?
    var onPreview: ((UIImage) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.relay.capture.queue")

    private let targetFPS: Double
    private let jpegQuality: CGFloat
    private let maxDimension: CGFloat

    private var lastSent: CFTimeInterval = 0
    private let ciContext = CIContext(options: nil)

    init(targetFPS: Double, jpegQuality: CGFloat, maxDimension: CGFloat) {
        self.targetFPS = max(0.5, targetFPS)
        self.jpegQuality = min(max(jpegQuality, 0.1), 0.9)
        self.maxDimension = max(160, maxDimension)
        super.init()
    }

    func start() {
        queue.async {
            self.configureIfNeeded()
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configureIfNeeded() {
        guard session.inputs.isEmpty else { return }

        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(out) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(out)

        if let conn = out.connection(with: .video) {
            conn.videoOrientation = .portrait
        }

        session.commitConfiguration()
    }

    private func shouldSend(now: CFTimeInterval) -> Bool {
        let minInterval = 1.0 / targetFPS
        if now - lastSent >= minInterval {
            lastSent = now
            return true
        }
        return false
    }

    private func downscale(_ image: UIImage) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resized ?? image
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard shouldSend(now: now) else { return }

        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }

        let img = UIImage(cgImage: cg)
        let scaled = downscale(img)

        onPreview?(scaled)
        if let jpeg = scaled.jpegData(compressionQuality: jpegQuality) {
            onJPEG?(jpeg)
        }
    }
}
