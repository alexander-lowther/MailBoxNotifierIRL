

import SwiftUI
import Firebase
import FirebaseFirestore
import FirebaseAuth
import CoreMotion
import UserNotifications
import UIKit

// MARK: - Setup View

struct LevelSensorSetupView: View {
    let functionTitle: String
    let deviceID: String
    
    @State private var threshold: Double = 45
    @State private var sendNotifications: Bool = true

    @State private var notificationTitle: String = ""
    @State private var notificationBody: String = ""
    @State private var createdTaskId: String = ""
    @State private var pushToListening: Bool = false

    private let db = Firestore.firestore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                BeforeYouBeginCard(
                    title: "Before you begin",
                    subtitle: "Tips for reliable level detection",
                    bullets: [
                        ("Keep the phone stable", "Movement will rapidly change readings and may cause triggers."),
                        ("Press re-center once placed", "This zeros the current tilt so threshold is relative to placement."),
                        ("Tilt requires flat surface", "Phone should never slide or move in unwanted directions")
                    ]
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Threshold (degrees)")
                        .font(.headline)

                    HStack {
                        Text("\(Int(threshold))°")
                            .font(.system(.title3, design: .rounded).bold())
                        Spacer()
                    }

                    Slider(value: $threshold, in: 1...90, step: 1)
                        .tint(.green)

                    Toggle("Send notifications", isOn: $sendNotifications)
                        .tint(.green)
                    if sendNotifications {
                        Text("Notifications")
                            .font(.headline)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Notification Subject")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            TextField("Sound detected", text: $notificationTitle)
                                .modifier(ModernTextFieldSurface())

                            Text("Notification Body")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            TextField("Your sound sensor was triggered.", text: $notificationBody)
                                .modifier(ModernTextFieldSurface())
                        }

                        Divider().opacity(0.4)
                    }
                    Text("Charts + triggering use **y** only (abs(y)). Listening view still shows x + y.")
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

                    // Mirror SoundTask approach: end other tasks first; write task doc async.
                    forceEndAllTasks(endedBy: "Begin Level Listener") { _ in
                        createTaskOneWrite(taskId: taskId)
                    }
                } label: {
                    Label("Start Level Sensor", systemImage: "level")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

            NavigationLink(isActive: $pushToListening) {
                    LevelListeningView(
                        config: LevelSensorConfig(
                            threshold: threshold,
                            sendNotifications: sendNotifications,
                            notificationTitle: effectiveNotificationTitle(),
                            notificationBody: effectiveNotificationBody()
                        ),
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

    private func makeTaskId() -> String {
        db.collection("_tmp").document().documentID
    }

  
    
    private func effectiveNotificationTitle() -> String {
        guard sendNotifications else { return "Level threshold hit" }
        return notificationTitle.isEmpty ? "Level threshold hit" : notificationTitle
    }

    private func effectiveNotificationBody() -> String {
        guard sendNotifications else { return "Your level sensor was triggered." }
        return notificationBody.isEmpty ? "Your level sensor was triggered." : notificationBody
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
            "name": "Level Sensor",
            "type": "level",
            "deviceID": deviceID,
            "deviceName": deviceName,
         
            "notificationTitle": effectiveNotificationTitle(),
            "notificationBody": effectiveNotificationBody(),
            "startedAt": Timestamp(date: Date()),
            "endedAt": NSNull(),

            "threshold": threshold,
            "sendNotifications": sendNotifications
        ]

        ref.setData(payload, merge: false) { err in
            if let err = err {
                print("Level task create failed: \(err.localizedDescription)")
            }
        }
    }
}

// MARK: - Config
struct LevelSensorConfig: Hashable {
    let threshold: Double
    let sendNotifications: Bool
    let notificationTitle: String
    let notificationBody: String
}
// MARK: - Listening View

struct LevelListeningView: View {
    let config: LevelSensorConfig
    let taskId: String
    let userUID: String

    @StateObject private var monitor = LevelMotionMonitor()

    // allow live toggle (fix “switch does nothing”)
    @State private var sendNotificationsLive: Bool
    @State private var status: String = "preparing…"

    @State private var samples: [SessionSamplePoint] = []
    @State private var sampleTimer: Timer? = nil

    // jitter guard (prevents rapid flip-flop at threshold)
    @State private var lastHitAt: Date? = nil
    private let minHitInterval: TimeInterval = 0.8

    private let db = Firestore.firestore()
    @Environment(\.dismiss) private var dismiss

    init(config: LevelSensorConfig, taskId: String, userUID: String) {
        self.config = config
        self.taskId = taskId
        self.userUID = userUID
        _sendNotificationsLive = State(initialValue: config.sendNotifications)
    }

    var body: some View {
        VStack(spacing: 14) {

            // Header
            HStack(spacing: 12) {
                Image(systemName: "level")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Level Sensor")
                        .font(.title3.bold())
                    Text("Threshold: \(Int(config.threshold))° (y)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    monitor.recenter()
                    status = "re-centered"
                } label: {
                    Label("Re-center", systemImage: "scope")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            // Dial
            LevelDialView(xDeg: monitor.xDeg, yDeg: monitor.yDeg, isTriggered: monitor.hitFlash)
                .frame(height: 340)
                .padding(.horizontal)

            // Chips row
            HStack(spacing: 12) {
                BubbleChip(label: "x", value: String(format: "%.1f°", monitor.xDeg), isActive: false)
                Spacer(minLength: 0)
                BubbleChip(label: "y", value: String(format: "%.1f°", monitor.yDeg), isActive: monitor.yAbs >= config.threshold)
            }
            .padding(.horizontal)

            // Notifications toggle chip row (so user can verify it actually works)
            HStack {
             //   BubbleToggleChip(
               //     title: "Notifications",
                 //   isOn: $sendNotificationsLive
               // )
              //  Spacer()
            }
            .padding(.horizontal)

            BubbleStatus(text: status)

            Spacer()

            // Stop at bottom (requirement)
            Button {
                endSessionAndDismiss()
            } label: {
                Text("Stop Listening")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 18)
        }
        .onAppear {
            monitor.start(threshold: config.threshold)
            status = "listening…"
            if sendNotificationsLive { requestNotificationPermissionIfNeeded() }
            startSampling()
        }
        .onDisappear {
            sampleTimer?.invalidate()
            sampleTimer = nil
            monitor.stop()
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Sampling + HIT triggers
    private func maybeNotify(direction: LevelMotionMonitor.HitKind, yAbs: Double) {
        guard sendNotificationsLive else { return }

        // Optional: tighter cooldown to prevent spam on oscillation
        // (you already have minHitInterval; that’s probably enough)
        let eventType = (direction == .up) ? "level_threshold_up" : "level_threshold_down"

        // You can keep the user-configured subject/body, but it’s often useful
        // to inject direction/value for debugging:
        let subject = config.notificationTitle
        let body = "\(config.notificationBody) y=\(Int(yAbs))°, thr=\(Int(config.threshold))° (\(direction == .up ? "up" : "down"))."
        NotificationService.shared.sendPush(
          subject: subject,
          body: body,
          taskId: taskId,
          eventType: eventType,
          sourceDeviceID: nil
        )

    }
    private func startSampling() {
        sampleTimer?.invalidate()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            if UIApplication.shared.applicationState == .background { return }

            let now = Date()
            let yAbs = abs(monitor.yDeg)
            monitor.yAbs = yAbs

            // ✅ charts: {t, v}
            samples.append(.init(time: now, value: yAbs))
            if samples.count > 2400 { samples.removeFirst(samples.count - 2400) }

            if let hit = monitor.consumeHit() {
                if let last = lastHitAt, now.timeIntervalSince(last) < minHitInterval {
                    // ignore jitter
                } else {
                    lastHitAt = now
                    status = (hit.kind == .up) ? "threshold hit (up)" : "threshold hit (down)"
                    maybeNotify(direction: hit.kind, yAbs: yAbs)
                }
            } else {
                status = "listening…"
            }
        }
    }

    // MARK: - Stop / write samples

    private func endSessionAndDismiss() {
        monitor.stop()
        sampleTimer?.invalidate()
        sampleTimer = nil

        let ref = db.collection("users").document(userUID).collection("tasks").document(taskId)
        let payload: [String: Any] = [
            "endedAt": Timestamp(date: Date()),
            "endedBy": "user_stopped",
            "sendNotifications": sendNotificationsLive,
            "samples": samples.map { ["t": Timestamp(date: $0.time), "v": $0.value] }
        ]

        ref.setData(payload, merge: true) { err in
            if let err = err {
                print("Level task end failed: \(err.localizedDescription)")
            }
            dismiss()
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }


}

// MARK: - Motion Monitor (crossing-based hits)

private final class LevelMotionMonitor: ObservableObject {
    private let motion = CMMotionManager()

    @Published var xDeg: Double = 0
    @Published var yDeg: Double = 0
    @Published var yAbs: Double = 0

    // brief flash for dial color
    @Published var hitFlash: Bool = false

    enum HitKind { case up, down }
    struct Hit { let time: Date; let kind: HitKind }

    private var baselineX: Double = 0
    private var baselineY: Double = 0

    private var threshold: Double = 45
    private var lastYAbs: Double = 0
    private var pendingHit: Hit?

    private var lastFlashAt: Date?

    func start(threshold: Double) {
        guard motion.isDeviceMotionAvailable else { return }

        self.threshold = threshold
        lastYAbs = 0
        pendingHit = nil
        hitFlash = false

        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] dm, _ in
            guard let self, let dm else { return }

            let roll = dm.attitude.roll * 180.0 / Double.pi
            let pitch = dm.attitude.pitch * 180.0 / Double.pi

            let x = roll - self.baselineX
            let y = pitch - self.baselineY

            self.xDeg = x
            self.yDeg = y

            let yAbs = abs(y)

            // ✅ HIT logic (crossing):
            // Up: last < thr and now >= thr
            if self.lastYAbs < self.threshold && yAbs >= self.threshold {
                self.pendingHit = Hit(time: Date(), kind: .up)
                self.flash()
            }
            // Down: last >= thr and now < thr
            else if self.lastYAbs >= self.threshold && yAbs < self.threshold {
                self.pendingHit = Hit(time: Date(), kind: .down)
                self.flash()
            }

            self.lastYAbs = yAbs
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        pendingHit = nil
        hitFlash = false
    }

    func recenter() {
        baselineX += xDeg
        baselineY += yDeg
        lastYAbs = 0
    }

    func consumeHit() -> Hit? {
        defer { pendingHit = nil }
        return pendingHit
    }

    private func flash() {
        hitFlash = true
        lastFlashAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            if let t = self.lastFlashAt, Date().timeIntervalSince(t) >= 0.55 {
                self.hitFlash = false
            }
        }
    }
}

// MARK: - Bubble UI helpers

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
                // request permission on-demand
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

// MARK: - Dial UI (Surface Level vibe)

private struct LevelDialView: View {
    let xDeg: Double
    let yDeg: Double
    let isTriggered: Bool

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let r = size * 0.42

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)

                Circle()
                    .strokeBorder(.black.opacity(0.45), lineWidth: size * 0.07)
                    .shadow(radius: 6)

                TickRing()
                    .stroke(.black.opacity(0.55), lineWidth: 2)
                    .padding(size * 0.09)

                Circle()
                    .fill(isTriggered ? Color.green.opacity(0.95) : Color.green.opacity(0.70))
                    .padding(size * 0.14)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.25), lineWidth: 2)
                            .padding(size * 0.14)
                    )

                Reticle()
                    .stroke(.white.opacity(0.45), lineWidth: 2)
                    .frame(width: size * 0.24, height: size * 0.24)

                // Bubble position uses BOTH x and y
                let dx = clamp(xDeg / 45.0, -1, 1) * r * 0.55
                let dy = clamp(yDeg / 45.0, -1, 1) * r * 0.55

                Circle()
                    .fill(.white.opacity(0.25))
                    .frame(width: size * 0.26, height: size * 0.26)
                    .blur(radius: 0.4)
                    .offset(x: dx, y: dy)
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: dx)
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: dy)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                            .frame(width: size * 0.26, height: size * 0.26)
                            .offset(x: dx, y: dy)
                    )

                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: size * 0.20, height: size * 0.20)
                    .offset(x: -size * 0.17, y: -size * 0.18)

                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: size * 0.12, height: size * 0.12)
                    .offset(x: size * 0.20, y: -size * 0.12)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, v))
    }
}

private struct Reticle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        p.addEllipse(in: rect)

        let tick: CGFloat = r * 0.28
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addLine(to: CGPoint(x: c.x, y: c.y - r + tick))

        p.move(to: CGPoint(x: c.x, y: c.y + r))
        p.addLine(to: CGPoint(x: c.x, y: c.y + r - tick))

        p.move(to: CGPoint(x: c.x - r, y: c.y))
        p.addLine(to: CGPoint(x: c.x - r + tick, y: c.y))

        p.move(to: CGPoint(x: c.x + r, y: c.y))
        p.addLine(to: CGPoint(x: c.x + r - tick, y: c.y))
        return p
    }
}

private struct TickRing: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let majorEvery = 10
        let total = 60

        for i in 0..<total {
            let angle = (Double(i) / Double(total)) * Double.pi * 2.0
            let isMajor = (i % majorEvery == 0)
            let inner = r - (isMajor ? r * 0.18 : r * 0.10)
            let outer = r

            let x1 = c.x + CGFloat(cos(angle)) * inner
            let y1 = c.y + CGFloat(sin(angle)) * inner
            let x2 = c.x + CGFloat(cos(angle)) * outer
            let y2 = c.y + CGFloat(sin(angle)) * outer

            p.move(to: CGPoint(x: x1, y: y1))
            p.addLine(to: CGPoint(x: x2, y: y2))
        }
        return p
    }
}
