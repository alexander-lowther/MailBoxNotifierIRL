
//
//  CameraTask_LAN.swift
//  Mailbox Notifier IRL
//
//  Option A: LAN-only live-ish stream (same Wi-Fi/subnet).
//  - Broadcaster: AVCaptureSession -> JPEG frames -> TCP server (Network.framework)
//  - Viewer: TCP client -> JPEG frames -> UIImage -> SwiftUI
//
//  Signaling: Firestore stores hostIP + port under:
//  /users/{uid}/tasks/{taskId}/cameraLan/state
//
//  iOS 15+
//

import SwiftUI
import AVFoundation
import FirebaseFirestore
import Network
import UIKit

private enum LanFields {
    static let coll = "cameraLan"
    static let doc = "state"
    static let hostIP = "hostIP"
    static let port = "port"
    static let hostDeviceID = "hostDeviceID"
    static let isLive = "isLive"
    static let updatedAt = "updatedAt"
}

struct CameraTaskLANView: View {
    let taskId: String
    let userUID: String
    let deviceID: String
    let taskDeviceID: String  // broadcaster iff this matches deviceID

    @StateObject private var vm = CameraTaskLANVM()

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(deviceID == taskDeviceID ? "LAN Broadcaster" : "LAN Viewer")
                    .font(.headline)
                Text("Fastest option, but requires same Wi-Fi / LAN.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
                    vm.stopAll()
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
        .navigationTitle("Camera (LAN)")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vm.stopAll() }
    }
}

@MainActor
final class CameraTaskLANVM: ObservableObject {
    @Published var currentFrame: UIImage? = nil
    @Published var statusText: String = ""
    @Published var debugText: String = ""
    @Published var isRunning: Bool = false

    private let db = Firestore.firestore()
    private var streamRef: DocumentReference?
    private var listener: ListenerRegistration?

    private var server: FrameServer?
    private var client: FrameClient?
    private var capture: CameraCapture?

    // Tunables (low-res & tolerant to delay)
    private let fps: Double = 6
    private let jpegQuality: CGFloat = 0.45
    private let maxDimension: CGFloat = 480

    func start(taskId: String, userUID: String, deviceID: String, taskDeviceID: String) {
        guard !isRunning else { return }
        isRunning = true
        statusText = ""
        debugText = ""

        streamRef = db.collection("users").document(userUID)
            .collection("tasks").document(taskId)
            .collection(LanFields.coll).document(LanFields.doc)

        if deviceID == taskDeviceID {
            startBroadcaster(deviceID: deviceID)
        } else {
            startViewer()
        }
    }

    func stopAll() {
        isRunning = false
        statusText = ""
        debugText = ""

        listener?.remove()
        listener = nil

        capture?.stop()
        capture = nil

        server?.stop()
        server = nil

        client?.stop()
        client = nil

        currentFrame = nil

        // best-effort mark down
        if let ref = streamRef {
            ref.setData([LanFields.isLive: false, LanFields.updatedAt: FieldValue.serverTimestamp()], merge: true)
        }
    }

    private func startBroadcaster(deviceID: String) {
        statusText = "Starting broadcaster…"

        guard let ip = NetworkInfo.localIPv4Address() else {
            statusText = "No Wi-Fi IP found. Connect to Wi-Fi."
            isRunning = false
            return
        }

        let server = FrameServer()
        self.server = server
        server.onState = { [weak self] s in Task { @MainActor in self?.debugText = s } }

        server.start { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .failure(let err):
                    self.statusText = "Server failed: \(err.localizedDescription)"
                    self.isRunning = false
                case .success(let port):
                    self.statusText = "Broadcasting \(ip):\(port)"

                    self.streamRef?.setData([
                        LanFields.hostIP: ip,
                        LanFields.port: port,
                        LanFields.hostDeviceID: deviceID,
                        LanFields.isLive: true,
                        LanFields.updatedAt: FieldValue.serverTimestamp()
                    ], merge: true)

                    let capture = CameraCapture(targetFPS: self.fps, jpegQuality: self.jpegQuality, maxDimension: self.maxDimension)
                    self.capture = capture
                    capture.onPreview = { [weak self] img in Task { @MainActor in self?.currentFrame = img } }
                    capture.onJPEG = { [weak self] jpeg in self?.server?.sendFrame(jpeg) }
                    capture.start()
                }
            }
        }
    }

    private func startViewer() {
        statusText = "Waiting for broadcaster…"
        currentFrame = nil

        guard let ref = streamRef else {
            statusText = "Missing stream doc."
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
                let isLive = (data[LanFields.isLive] as? Bool) ?? false
                guard isLive else {
                    self.statusText = "Broadcaster not live."
                    return
                }
                guard let ip = data[LanFields.hostIP] as? String,
                      let port = data[LanFields.port] as? Int else {
                    self.statusText = "Endpoint not ready…"
                    return
                }
                if self.client?.isConnectedTo(ip: ip, port: port) == true { return }
                self.connect(ip: ip, port: port)
            }
        }
    }

    private func connect(ip: String, port: Int) {
        statusText = "Connecting \(ip):\(port)…"
        debugText = ""

        client?.stop()
        let c = FrameClient(host: ip, port: port)
        client = c

        c.onState = { [weak self] s in Task { @MainActor in self?.debugText = s } }
        c.onFrame = { [weak self] jpeg in
            guard let self else { return }
            if let img = UIImage(data: jpeg) {
                Task { @MainActor in
                    self.currentFrame = img
                    self.statusText = "Viewing \(ip):\(port)"
                }
            }
        }
        c.start()
    }
}

// MARK: - Capture (AVFoundation -> JPEG)

final class CameraCapture2: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onJPEG: ((Data) -> Void)?
    var onPreview: ((UIImage) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.capture.queue")
    private let targetFPS: Double
    private let jpegQuality: CGFloat
    private let maxDimension: CGFloat
    private var lastSent: CFTimeInterval = 0

    init(targetFPS: Double, jpegQuality: CGFloat, maxDimension: CGFloat) {
        self.targetFPS = max(1, targetFPS)
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
        let ctx = CIContext(options: nil)
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return }
        let img = UIImage(cgImage: cg)
        let scaled = downscale(img)

        onPreview?(scaled)
        if let jpeg = scaled.jpegData(compressionQuality: jpegQuality) {
            onJPEG?(jpeg)
        }
    }
}

// MARK: - TCP protocol: [UInt32 length big-endian][JPEG bytes]

final class FrameServer {
    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "frame.server.queue")
    var onState: ((String) -> Void)?

    func start(completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async {
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                self.listener = listener

                listener.stateUpdateHandler = { [weak self] st in self?.onState?("Listener: \(st)") }

                listener.newConnectionHandler = { [weak self] conn in
                    guard let self else { return }
                    self.connection?.cancel()
                    self.connection = conn
                    self.onState?("Client connected.")
                    conn.stateUpdateHandler = { [weak self] st in self?.onState?("Conn: \(st)") }
                    conn.start(queue: self.queue)
                }

                listener.start(queue: self.queue)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if let p = listener.port?.rawValue {
                        completion(.success(Int(p)))
                    } else {
                        completion(.failure(NSError(domain: "FrameServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "No port assigned"])))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    func stop() {
        queue.async {
            self.connection?.cancel()
            self.connection = nil
            self.listener?.cancel()
            self.listener = nil
            self.onState?("Server stopped.")
        }
    }

    func sendFrame(_ jpeg: Data) {
        queue.async {
            guard let conn = self.connection, conn.state == .ready else { return }
            var len = UInt32(jpeg.count).bigEndian
            let header = Data(bytes: &len, count: 4)
            conn.send(content: header + jpeg, completion: .contentProcessed { _ in })
        }
    }
}

final class FrameClient {
    private let host: String
    private let port: Int
    private var conn: NWConnection?
    private let queue = DispatchQueue(label: "frame.client.queue")

    private var buffer = Data()
    private var expectedLen: Int?

    var onFrame: ((Data) -> Void)?
    var onState: ((String) -> Void)?

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func isConnectedTo(ip: String, port: Int) -> Bool {
        guard let c = conn else { return false }
        return (ip == host && port == self.port && c.state == .ready)
    }

    func start() {
        stop()
        let endpointHost = NWEndpoint.Host(host)
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            onState?("Bad port.")
            return
        }

        let c = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
        conn = c
        c.stateUpdateHandler = { [weak self] st in self?.onState?("Client: \(st)") }
        c.start(queue: queue)

        receiveLoop()
    }

    func stop() {
        conn?.cancel()
        conn = nil
        buffer.removeAll(keepingCapacity: false)
        expectedLen = nil
    }

    private func receiveLoop() {
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error = error {
                self.onState?("Recv error: \(error.localizedDescription)")
                return
            }
            if let data = data, !data.isEmpty {
                self.buffer.append(data)
                self.drainFrames()
            }
            if isComplete {
                self.onState?("Connection closed.")
                return
            }
            self.receiveLoop()
        }
    }

    private func drainFrames() {
        while true {
            if expectedLen == nil {
                guard buffer.count >= 4 else { return }
                let lenData = buffer.prefix(4)
                buffer.removeFirst(4)
                let len = lenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                expectedLen = Int(len)
            }
            guard let needed = expectedLen else { return }
            guard buffer.count >= needed else { return }
            let frame = buffer.prefix(needed)
            buffer.removeFirst(needed)
            expectedLen = nil
            onFrame?(Data(frame))
        }
    }
}

// MARK: - Local IPv4 helper

enum NetworkInfo {
    static func localIPv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" { // Wi-Fi typically en0
                    var addr = interface.ifa_addr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(&addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }

            if let next = interface.ifa_next {
                ptr = next
            } else {
                break
            }
        }
        return address
    }
}
