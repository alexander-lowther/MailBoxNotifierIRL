
//
//  VibeTask.swift
//  Mail Box Notifer
//
//  Created by user281046 on 1/23/26.
//

//
//  VibeTask.swift
//  Mailbox Notifier IRL
//
//  Mirrors SoundTask structure/UI/database flow, with these differences:
//  - No Threshold/Sensitivity UI
//  - Internal vibration detection only (started / stopped)
//  - Intended use: place phone on dryer, detect when vibration begins/ends
//

import SwiftUI
import Firebase
import FirebaseFirestore
import FirebaseAuth
import CoreMotion
import UIKit

// MARK: - Setup View

struct VibeSensorSetupView: View {
    let functionTitle: String  // kept for compatibility with your existing routing

    @State private var notificationTitle: String = ""
    @State private var notificationBody: String = ""
    @State private var sendNotifications: Bool = true

    @State private var createdTaskId: String = ""
    @State private var pushToListening: Bool = false

    private let db = Firestore.firestore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                BeforeYouBeginCard(
                    title: "Before you begin",
                    subtitle: "Best results for dryer vibration detection",
                    bullets: [
                        ("Place phone flat on the dryer", "Avoid soft surfaces that dampen vibration."),
                        ("Keep device plugged in if possible", "Long sessions may drain battery."),
                        ("Minimize movement near the phone", "Bumps/handling can look like vibration.")
                    ]
                )

                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Send notifications to other devices", isOn: $sendNotifications)
                        .font(.subheadline)

                    if sendNotifications {
                        Text("Notifications")
                            .font(.headline)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Notification Subject")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            TextField("Vibration detected", text: $notificationTitle)
                                .modifier(ModernTextFieldSurface())

                            Text("Notification Body")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            TextField("Your vibration sensor changed state.", text: $notificationBody)
                                .modifier(ModernTextFieldSurface())
                        }

                        Divider().opacity(0.4)
                    }

                    Text("Detection")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("This task detects **vibration started** and **vibration stopped** using the accelerometer. There is no user threshold for this task.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button {
                    let taskId = makeTaskId()
                    createdTaskId = taskId
                    pushToListening = true

                    forceEndAllTasks(endedBy: "Begin Vibration Listener") { _ in
                        createTaskOneWrite(taskId: taskId)
                    }
                } label: {
                    Label("Start Vibration Sensor",
                          systemImage: AppSymbols.best(["waveform.path.ecg", "waveform"]))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                NavigationLink(isActive: $pushToListening) {
                    let cfg = VibeSensorConfig(
                        notificationTitle: effectiveNotificationTitle(),
                        notificationBody: effectiveNotificationBody(),
                        sendNotifications: sendNotifications
                    )

                    VibeListeningView(
                        config: cfg,
                        taskId: createdTaskId,
                        userUID: Auth.auth().currentUser?.uid ?? ""
                    )
                } label: { EmptyView() }
                    .hidden()
            }
            .padding()
        }
    }

    private func effectiveNotificationTitle() -> String {
        guard sendNotifications else { return "Vibration detected" }
        return notificationTitle.isEmpty ? "Vibration detected" : notificationTitle
    }

    private func effectiveNotificationBody() -> String {
        guard sendNotifications else { return "Your vibration sensor changed state." }
        return notificationBody.isEmpty ? "Your vibration sensor changed state." : notificationBody
    }

    private func makeTaskId() -> String {
        db.collection("_tmp").document().documentID
    }

    private func stableDeviceID() -> String {
        if let existing = UserDefaults.standard.string(forKey: "stable_device_id"), !existing.isEmpty {
            return existing
        }
        let newID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
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

        let ref = db.collection("users").document(uid)
            .collection("tasks").document(taskId)

        let payload: [String: Any] = [
            "name": "Vibration Sensor",
            "deviceID": deviceID,
            "type": "vibe",

            "startedAt": Timestamp(date: Date()),
            "endedAt": NSNull(),

            "deviceName": deviceName,
            "listenerDeviceID": deviceID,

            // Keep schema stable for future notifications
            "notificationTitle": effectiveNotificationTitle(),
            "notificationBody": effectiveNotificationBody(),
            "sendNotifications": sendNotifications,

            // Internal tuning (not user-facing). Useful for debugging / future charting.
            "vibeDetectorVersion": 1
        ]

        ref.setData(payload, merge: false) { err in
            if let err = err {
                print("Vibe task create failed: \(err.localizedDescription)")
            }
        }
    }
}

// MARK: - Listening View

struct VibeListeningView: View {
    let config: VibeSensorConfig
    let taskId: String
    let userUID: String

    @StateObject private var monitor = VibrationMonitor()

    @State private var status: String = "preparing…"
    @State private var samples: [SessionSamplePoint] = []
    @State private var events: [[String: Any]] = []
    @State private var sampleTimer: Timer? = nil
    @State private var evaluatorTimer: Timer? = nil

    // Push cooldown (prevents vibration chatter spamming notifications)
    @State private var lastVibeNotifyAt: Date? = nil
    private let vibeNotifyCooldown: TimeInterval = 30

    private let db = Firestore.firestore()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {

            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Vibration Sensor")
                        .font(.title3.bold())
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VibeLevelBubble(level: Float(monitor.level), stateText: monitor.stateText)

            HStack(spacing: 12) {
              //  Tag("Vibe Level")
                Tag(String(format: "%.2f", monitor.level), fixedWidth: 84, monospaced: true)
               // Tag("State")
                Tag(monitor.stateText, fixedWidth: 110, monospaced: false)
            }

            let visLevel = Double(min(1.0, max(0.0, pow(monitor.level, 0.7))))
            VibeWaveView(level: visLevel, isActive: monitor.isVibrating)
                .frame(height: 120)
                .padding(.top, 4)

            Text("Device is acting as a vibration sensor. When vibration starts or stops, the state will change and, if enabled, your notification will be used later when push notifications are implemented.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4.0)

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
            status = "listening…"

            monitor.start()
            startSampling()
            startEvaluator()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            monitor.stop()
            sampleTimer?.invalidate()
            evaluatorTimer?.invalidate()
            sampleTimer = nil
            evaluatorTimer = nil
        }
    }

    private func startSampling() {
        sampleTimer?.invalidate()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let p = SessionSamplePoint(time: Date(), value: monitor.level)
            samples.append(p)
            if samples.count > 600 { samples.removeFirst(samples.count - 600) }
        }
    }

    private func startEvaluator() {
        evaluatorTimer?.invalidate()
        evaluatorTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            if UIApplication.shared.applicationState == .background { return }

            // Mirror SoundTask: update a simple status string for UI
            status = monitor.isVibrating ? "vibration detected" : "listening…"

            // Transition logging (started/stopped)
            guard let transition = monitor.consumeTransition() else { return }

            events.append([
                "t": Timestamp(date: transition.time),
                "type": transition.kind,      // "vibration_started" | "vibration_stopped"
                "level": transition.level
            ])

            // ✅ Push notifications on discrete events (cooldown prevents chatter spam)
            guard config.sendNotifications else { return }

            let now = Date()
            let cooldownOk: Bool
            if let last = lastVibeNotifyAt {
                cooldownOk = now.timeIntervalSince(last) >= vibeNotifyCooldown
            } else {
                cooldownOk = true
            }
            guard cooldownOk else { return }
            lastVibeNotifyAt = now

            if transition.kind == "vibration_started" {
                NotificationService.shared.sendPush(
                    subject: config.notificationTitle,
                    body: config.notificationBody,
                    taskId: taskId,
                    eventType: "vibration_started",
                    sourceDeviceID: nil
                )
            } else if transition.kind == "vibration_stopped" {
                NotificationService.shared.sendPush(
                    subject: "Dryer finished",
                    body: "Vibration stopped — your dryer may be done.",
                    taskId: taskId,
                    eventType: "vibration_stopped",
                    sourceDeviceID: nil
                )
            }
        }
    }

    private func stopListening() {
        UIApplication.shared.isIdleTimerDisabled = false
        monitor.stop()
        sampleTimer?.invalidate()
        evaluatorTimer?.invalidate()
        sampleTimer = nil
        evaluatorTimer = nil

        endTask()
        dismiss()
    }

    private func endTask() {
        guard !userUID.isEmpty else { return }
        let ref = db.collection("users").document(userUID).collection("tasks").document(taskId)

        var payload: [String: Any] = [
            "endedAt": Timestamp(date: Date()),
            "endedReason": "user_stopped"
        ]

        payload["samples"] = samples.map { ["t": Timestamp(date: $0.time), "v": $0.value] }
        payload["events"] = events

        ref.setData(payload, merge: true) { err in
            if let err = err {
                print("Vibe task end failed: \(err.localizedDescription)")
            }
        }
    }
}

// MARK: - Bubble

struct VibeLevelBubble: View {
    let level: Float
    let stateText: String

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.surface)
                .overlay(
                    Circle().strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                )
                .frame(width: 140, height: 140)

            VStack(spacing: 6) {
                Text("Vibration")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(String(format: "%.2f", level))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Text(stateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 140, height: 140)
        }
        .padding(.top, 4)
    }
}


// MARK: - Wave Animation (replaces bar graph)

/// A simple "heartbeat-style" wave animation driven by current vibration level.
struct VibeWaveView: View {
    let level: Double        // 0...1
    let isActive: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let midY = size.height / 2.0
                let w = size.width
                let h = size.height

                let activeBoost = isActive ? 1.0 : 0.35
                let amp = (0.10 + 0.45 * level) * activeBoost * h
                let phase = t * 3.0
                let freq = 2.0 * Double.pi / max(1.0, w) * 18.0

                var path = Path()
                path.move(to: CGPoint(x: 0, y: midY))

                let step = max(2.0, w / 140.0)
                var x: Double = 0
                while x <= w {
                    let s1 = sin(x * freq + phase)
                    let s2 = 0.35 * sin(x * freq * 2.3 + phase * 1.25)
                    let y = midY + (s1 + s2) * amp
                    path.addLine(to: CGPoint(x: x, y: y))
                    x += step
                }

                // Double stroke for subtle "glow"
                context.stroke(path, with: .color(.primary.opacity(0.25)), lineWidth: 8)
                context.stroke(path, with: .color(.primary.opacity(0.95)), lineWidth: 2.5)

                // Simple EKG-ish pulse overlay when active
                if isActive {
                    var pulse = Path()
                    let cx = w * 0.55
                    pulse.move(to: CGPoint(x: cx - 40, y: midY))
                    pulse.addLine(to: CGPoint(x: cx - 18, y: midY))
                    pulse.addLine(to: CGPoint(x: cx - 10, y: midY - amp * 0.55))
                    pulse.addLine(to: CGPoint(x: cx - 2,  y: midY + amp * 0.25))
                    pulse.addLine(to: CGPoint(x: cx + 10, y: midY - amp * 0.18))
                    pulse.addLine(to: CGPoint(x: cx + 26, y: midY))
                    pulse.addLine(to: CGPoint(x: cx + 46, y: midY))

                    context.stroke(pulse, with: .color(.primary.opacity(0.70)), lineWidth: 3)
                }
            }
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}


// MARK: - Monitor

final class VibrationMonitor: ObservableObject {
    @Published var level: Double = 0.0     // 0..1 normalized
    @Published var isVibrating: Bool = false

    var stateText: String { isVibrating ? "Vibrating" : "Still" }

    struct Transition {
        let time: Date
        let kind: String   // "vibration_started" | "vibration_stopped"
        let level: Double
    }

    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    // Internal tuning (not user-facing)
    private let startThreshold: Double = 0.10
    private let stopThreshold: Double  = 0.06
    private let debounceSeconds: TimeInterval = 2.0

    private var lastTransitionAt: Date = .distantPast
    private var pendingTransition: Transition? = nil

    func start() {
        guard manager.isAccelerometerAvailable else { return }
        manager.accelerometerUpdateInterval = 1.0 / 50.0

        queue.qualityOfService = .userInitiated

        manager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }

            // Magnitude includes gravity; subtract ~1g to focus on movement/vibration.
            let mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            let movement = abs(mag - 1.0)

            // Normalize into 0..1 for UI
            let normalized = min(1.0, max(0.0, movement * 4.0))

            DispatchQueue.main.async {
                // simple smoothing
                self.level = (self.level * 0.85) + (normalized * 0.15)
                self.evaluateState(now: Date())
            }
        }
    }

    func stop() {
        manager.stopAccelerometerUpdates()
    }

    func consumeTransition() -> Transition? {
        defer { pendingTransition = nil }
        return pendingTransition
    }

    private func evaluateState(now: Date) {
        let elapsed = now.timeIntervalSince(lastTransitionAt)
        guard elapsed >= debounceSeconds else { return }

        if !isVibrating, level >= startThreshold {
            isVibrating = true
            lastTransitionAt = now
            pendingTransition = Transition(time: now, kind: "vibration_started", level: level)
        } else if isVibrating, level <= stopThreshold {
            isVibrating = false
            lastTransitionAt = now
            pendingTransition = Transition(time: now, kind: "vibration_stopped", level: level)
        }
    }
}

// MARK: - Models

struct VibeSensorConfig: Codable, Hashable {
    var notificationTitle: String
    var notificationBody: String
    var sendNotifications: Bool
}
