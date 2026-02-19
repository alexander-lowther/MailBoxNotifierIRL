
//
//  PowerTask.swift
//  Mail Box Notifer
//
//  Power Loss Monitor
//  - No user customization
//  - Automatically sends push notifications:
//      * Listening started
//      * Power Off (charging lost)
//      * Power On  (charging restored)
//  - Firestore logging remains independent of push
//

import SwiftUI
import Firebase
import FirebaseFirestore
import FirebaseAuth
import UIKit

// MARK: - Setup View

struct PowerLossSetupView: View {
    let functionTitle: String  // kept for compatibility with your existing routing
    let deviceID: String   
    @State private var createdTaskId: String = ""
    @State private var pushToListening: Bool = false

    private let db = Firestore.firestore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                BeforeYouBeginCard(
                    title: "Before you begin",
                    subtitle: "Power outage detection tips",
                    bullets: [
                        ("Plug into a stable outlet", "This task watches charging state."),
                        ("Leave device plugged in", "Unplugging simulates power loss."),
                        ("Long sessions recommended", "Best used as a continuous monitor.")
                    ]
                )

                VStack(alignment: .leading, spacing: 14) {
                    Text("Detection")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("This task detects when the phone **loses charging power** and when it **begins charging again**. Notifications are automatic: **Power Off** and **Power On**.")
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

                    // DB writes occur async; cleanup first, then create.
                    forceEndAllTasks(endedBy: "Begin Power Loss Listener") { _ in
                        createTaskOneWrite(taskId: taskId)
                    }
                } label: {
                    Label("Start Power Loss Monitor",
                          systemImage: AppSymbols.best(["bolt.badge.clock", "bolt"]))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                NavigationLink(isActive: $pushToListening) {
                    PowerLossListeningView(
                        taskId: createdTaskId,
                        userUID: Auth.auth().currentUser?.uid ?? ""
                    )
                } label: { EmptyView() }
                .hidden()
            }
            .padding()
        }
    }

    private func makeTaskId() -> String {
        db.collection("_tmp").document().documentID
    }

  

    /// Single Firestore write that sets startedAt + endedAt(null) + listenerDevice in one call.
    /// NOTE: This does NOT block navigation.
    private func createTaskOneWrite(taskId: String) {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }




        let cachedName = UserDefaults.standard.string(forKey: "local_device_name")
        let fallbackName = UIDevice.current.name
        let deviceName = (cachedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? cachedName!
            : fallbackName

        let ref = db.collection("users").document(uid)
            .collection("tasks").document(taskId)

        // No customization; fixed push text stored for schema stability / future analytics.
        let payload: [String: Any] = [
            "name": "Power Loss",
            "deviceID": deviceID,
            "type": "powerloss",

            "startedAt": Timestamp(date: Date()),
            "endedAt": NSNull(),

            "deviceName": deviceName,
         

            "sendNotifications": true,
            "notificationTitlePowerOff": "Power Off",
            "notificationBodyPowerOff": "Phone is not charging.",
            "notificationTitlePowerOn": "Power On",
            "notificationBodyPowerOn": "Phone is charging.",

            "powerDetectorVersion": 2
        ]

        ref.setData(payload, merge: false) { err in
            if let err = err {
                print("PowerLoss task create failed: \(err.localizedDescription)")
            }
        }
    }
}

// MARK: - Listening View

struct PowerLossListeningView: View {
    let taskId: String
    let userUID: String

    @StateObject private var monitor = ChargingMonitor()

    @State private var status: String = "preparing…"
    @State private var samples: [SessionSamplePoint] = []
    @State private var events: [[String: Any]] = []
    @State private var sampleTimer: Timer? = nil

    // Push guards
    @State private var didSendStartedPush: Bool = false
    @State private var baselineInitialized: Bool = false
    @State private var lastPowerNotifyAt: Date? = nil
    private let powerNotifyCooldown: TimeInterval = 5

    private let db = Firestore.firestore()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {

            HStack(spacing: 12) {
                Image(systemName: "bolt")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Power Loss")
                        .font(.title3.bold())
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            PowerStateBubble(isCharging: monitor.isCharging)

            HStack(spacing: 12) {
                Tag("Charging")
                Tag(monitor.isCharging ? "Yes" : "No", fixedWidth: 84, monospaced: false)
                Tag("Battery")
                Tag(String(format: "%.0f%%", monitor.batteryLevel * 100), fixedWidth: 84, monospaced: true)
            }

            let vis = Double(min(1.0, max(0.0, monitor.batteryLevel)))
            SignalBarsView(level: vis)
                .frame(height: 120)
                .padding(.top, 4)

            Text("Device is monitoring charging state. When charging is lost or restored, this is logged and a push notification is sent to your other devices.")
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
        .navigationTitle("Power Loss")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true

            monitor.start()
            status = monitor.isCharging ? "charging…" : "not charging…"

       //     startSampling()

            // Push permission request is safe and non-blocking.
            NotificationService.shared.requestAuthorizationIfNeeded()

            // "User started listening..." (once)
            if !didSendStartedPush {
                didSendStartedPush = true
                NotificationService.shared.sendPush(
                    subject: "Listening started",
                    body: "Power Task has started",
                    taskId: taskId,
                    eventType: "listening_started",
                    sourceDeviceID: nil
                )
            }

            // Establish baseline so we don't immediately send Power On/Off on initial refresh.
            baselineInitialized = true
        }
        .onChange(of: monitor.isCharging) { newValue in
            status = newValue ? "charging…" : "not charging…"

            // Always log to events for review later.
            let eventType = newValue ? "power_on" : "power_off"
            events.append([
                "t": Timestamp(date: Date()),
                "type": eventType,
                "batteryLevel": monitor.batteryLevel
            ])

            // Do not send Power On/Off until baseline is set.
            guard baselineInitialized else { return }

            // Cooldown to avoid spam if state flaps.
            let now = Date()
            let cooldownOk: Bool
            if let last = lastPowerNotifyAt {
                cooldownOk = now.timeIntervalSince(last) >= powerNotifyCooldown
            } else {
                cooldownOk = true
            }
            guard cooldownOk else { return }
            lastPowerNotifyAt = now

            if newValue {
                // Power restored / charging
                NotificationService.shared.sendPush(
                    subject: "Power On",
                    body: "Phone is charging.",
                    taskId: taskId,
                    eventType: "power_on",
                    sourceDeviceID: nil
                )
            } else {
                // Power lost / not charging
                NotificationService.shared.sendPush(
                    subject: "Power Off",
                    body: "Phone is not charging.",
                    taskId: taskId,
                    eventType: "power_off",
                    sourceDeviceID: nil
                )
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            monitor.stop()
            sampleTimer?.invalidate()
            sampleTimer = nil
        }
    }

    private func startSampling() {
        sampleTimer?.invalidate()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // sample value: 1 if charging else 0 (simple charting)
            let v = monitor.isCharging ? 1.0 : 0.0
            let p = SessionSamplePoint(time: Date(), value: v)
            samples.append(p)
            if samples.count > 600 { samples.removeFirst(samples.count - 600) }
        }
    }

    private func stopListening() {
        UIApplication.shared.isIdleTimerDisabled = false
        monitor.stop()
        sampleTimer?.invalidate()
        sampleTimer = nil

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
                print("PowerLoss task end failed: \(err.localizedDescription)")
            }
        }
    }
}

// MARK: - Bubble

struct PowerStateBubble: View {
    let isCharging: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.surface)
                .overlay(
                    Circle().strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                )
                .frame(width: 140, height: 140)

            VStack(spacing: 6) {
                Text("Power State")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Image(systemName: isCharging ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.primary)

                Text(isCharging ? "Charging" : "Not Charging")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 140, height: 140)
        }
        .padding(.top, 4)
    }
}

// MARK: - Monitor

final class ChargingMonitor: ObservableObject {
    @Published var isCharging: Bool = false
    @Published var batteryLevel: Double = 0.0  // 0..1

    private var observers: [NSObjectProtocol] = []
    private var timer: Timer? = nil

    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()

        let nc = NotificationCenter.default

        observers.append(
            nc.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        )

        observers.append(
            nc.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        )

        // Extra safety: periodic refresh in case notifications are delayed.
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        let nc = NotificationCenter.default
        observers.forEach { nc.removeObserver($0) }
        observers.removeAll()

        timer?.invalidate()
        timer = nil

        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    private func refresh() {
        let state = UIDevice.current.batteryState
        let charging = (state == .charging || state == .full)

        isCharging = charging

        let lvl = UIDevice.current.batteryLevel
        batteryLevel = (lvl < 0) ? batteryLevel : Double(lvl)
    }
}
