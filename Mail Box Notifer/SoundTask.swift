

import SwiftUI
import Firebase
import FirebaseFirestore
import FirebaseAuth
import AVFoundation
import UIKit

// MARK: - Setup View

struct SoundSensorSetupView: View {
let functionTitle: String  // kept for compatibility with your existing routing
    let deviceID: String
@State private var notificationTitle: String = ""
@State private var notificationBody: String = ""
@State private var sensitivity: Double = 0.7
@State private var sendNotifications: Bool = true

@State private var createdTaskId: String = ""
@State private var pushToListening: Bool = false

private let db = Firestore.firestore()

var body: some View {
ScrollView {
VStack(alignment: .leading, spacing: 18) {

BeforeYouBeginCard(
title: "Before you begin",
subtitle: "A few quick tips for better detection",
bullets: [
("Place phone near the sound source", "No obstructions near the device's speaker"),
("Keep device plugged in for long sessions", "Continuous audio monitoring uses more power."),
("Keep the app running", "The app should remain in the foregrouond")
]
)

VStack(alignment: .leading, spacing: 14) {

// Notifications toggle FIRST (so it actually governs visibility)
Toggle("Send notifications to other devices", isOn: $sendNotifications)
.font(.subheadline)

// Hide/show customization based on toggle
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

Text("Sensitivity")
.font(.headline)

VStack(alignment: .leading, spacing: 10) {
HStack {
Text("Low")
.font(.caption)
.foregroundStyle(.secondary)
Spacer()
    Text(sensitivityLabel(sensitivity))
.font(.caption.weight(.bold))
.foregroundStyle(.secondary)
Spacer()
Text("High")
.font(.caption)
.foregroundStyle(.secondary)
}

Slider(value: $sensitivity, in: 0.1...1.0, step: 0.01)
.tint(.black)

Text("Drag to adjust how easily sound triggers detection.")
.font(.footnote)
.foregroundStyle(.secondary)
}
.padding(12)
.background(AppTheme.surface)
.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
}

Button {
// Requirement: Always launch listening view even if database write fails.
let taskId = makeTaskId()
createdTaskId = taskId
pushToListening = true

// DB writes occur async; cleanup first, then create.
forceEndAllTasks(endedBy: "Begin Sound Listener") { _ in
createTaskOneWrite(taskId: taskId)
}
} label: {
Label("Start Sound Sensor",
systemImage: AppSymbols.best(["ear.badge.waveform", "ear"]))
.frame(maxWidth: .infinity)
}
.buttonStyle(.borderedProminent)

NavigationLink(isActive: $pushToListening) {
let cfg = SoundSensorConfig(
notificationTitle: effectiveNotificationTitle(),
notificationBody: effectiveNotificationBody(),
threshold: Float(max(0.1, min(1.0, sensitivity))),
sendNotifications: sendNotifications
)
SoundListeningView(
config: cfg,
taskId: createdTaskId,
userUID: Auth.auth().currentUser?.uid ?? ""
)
} label: {
EmptyView()
}
.hidden()
}
.padding()
}
}

private func effectiveNotificationTitle() -> String {
// If notifications are OFF, we still store safe defaults (or blanks) consistently.
guard sendNotifications else { return "Sound detected" }
return notificationTitle.isEmpty ? "Sound detected" : notificationTitle
}

private func effectiveNotificationBody() -> String {
guard sendNotifications else { return "Your sound sensor was triggered." }
return notificationBody.isEmpty ? "Your sound sensor was triggered." : notificationBody
}

private func makeTaskId() -> String {
// Deterministic local id for immediate navigation; doesn't require network.
db.collection("_tmp").document().documentID
}



/// Single Firestore write that sets startedAt + endedAt(null) + listenerDevice in one call.
/// NOTE: This does NOT block navigation.

/// NOTE: This does NOT block navigation.
private func createTaskOneWrite(taskId: String) {
guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
// Can't write task/logs without auth, but navigation still proceeds.
return
}



let threshold = Float(max(0.1, min(1.0, sensitivity)))

let title = effectiveNotificationTitle()
let body = effectiveNotificationBody()

// ✅ Pull locally cached device name (set in DevicesView)
let cachedName = UserDefaults.standard.string(forKey: "local_device_name")
let fallbackName = UIDevice.current.name
let deviceName = (cachedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
? cachedName!
: fallbackName

let ref = db.collection("users").document(uid)
.collection("tasks").document(taskId)

let payload: [String: Any] = [
"name": "Sound Spike",
"deviceID": deviceID,
"type": "sound",

"startedAt": Timestamp(date: Date()),
"endedAt": NSNull(),

// ✅ Now always populated
"deviceName": deviceName,


// Store sensitivity/threshold for charting & configuration
"threshold": threshold,

// Store even if sendNotifications is false (keeps schema stable)
"notificationTitle": title,
"notificationBody": body,
"sendNotifications": sendNotifications
]

ref.setData(payload, merge: false) { err in
if let err = err {
print("Sound task create failed: \(err.localizedDescription)")
}
}
}
private func sensitivityLabel(_ v: Double) -> String {
switch v {
case ..<0.40: return "Low"
case ..<0.75: return "Medium"
default: return "High"
}
}
}

// MARK: - Listening View

struct SoundListeningView: View {
   let config: SoundSensorConfig

   @State private var evaluatorTimer: Timer?
   @State private var lastNotificationSentAt: Date?
   let taskId: String
   let userUID: String
   @State private var aboveSince: Date? = nil
   @StateObject private var monitor = SoundLevelMonitor()
   @State private var status: String = "preparing…"
   @State private var samples: [SessionSamplePoint] = []
   @State private var sampleTimer: Timer? = nil
   
   private let db = Firestore.firestore()
   
   @Environment(\.dismiss) private var dismiss
   
   var body: some View {
       VStack(spacing: 16) {
           
           HStack(spacing: 12) {
               Image(systemName: "ear.badge.waveform")
                   .font(.system(size: 34, weight: .bold))
                   .foregroundStyle(Color(red: 61/255, green: 99/255, blue: 68/255))
               
               VStack(alignment: .leading, spacing: 2) {
                   Text("Sound Spike")
                       .font(.title3.bold())
                   Text(status)
                       .font(.caption)
                       .foregroundStyle(.secondary)
               }
               Spacer()
           }
           HStack {
               SoundLevelBubble(level: monitor.level)
               SoundLevelBubbleDB(peakDb: monitor.peakDb)
           }
           let thresholdDb = dbThreshold(from: config.threshold)
           let thresholdNorm = (max(-60, min(0, thresholdDb)) + 60) / 60

           ThresholdPill(
               normalized: thresholdNorm,
               db: thresholdDb
           )

           let visLevel = Double(min(1.0, max(0.0, pow(monitor.level, 0.6))))
           SignalBarsView(level: visLevel)
               .frame(height: 120)
               .padding(.top, 4)
           
           Text("Device is acting as a sound sensor.")
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
       .navigationTitle("Sound Spike")
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
           sampleTimer = nil
       }
   }
   struct ThresholdPill: View {
       let normalized: Float   // 0.0 ... 1.0
       let db: Float           // dBFS (negative)

       var body: some View {
           HStack(spacing: 6) {
               Text("Threshold")
                   .font(.caption.weight(.medium))
                   .foregroundStyle(.secondary)

               // Normalized value (UI space)
               Text(String(format: "%.2f", normalized))
                   .font(.caption.monospacedDigit().weight(.semibold))

               Text("|")
                   .font(.caption.weight(.medium))
                   .foregroundStyle(.secondary)

               // dB value (trigger space)
               Text(String(format: "%.1f dB", db))
                   .font(.caption.monospacedDigit().weight(.semibold))
           }
           .padding(.horizontal, 12)
           .padding(.vertical, 6)
           .background(
               Capsule()
                   .fill(AppTheme.surface)
                   .overlay(
                       Capsule()
                           .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                   )
           )
       }
   }
   private func startSampling() {
       sampleTimer?.invalidate()
       sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
           let p = SessionSamplePoint(time: Date(), value: Double(monitor.level))
           samples.append(p)
           if samples.count > 600 {
               samples.removeFirst(samples.count - 600)
           }
       }
   }
   
   private func startEvaluator() {
       Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
           if UIApplication.shared.applicationState == .background {
               timer.invalidate()
               return
           }

           let thresholdDb = dbThreshold(from: config.threshold)
           let isAbove = monitor.peakDb >= thresholdDb

           status = isAbove ? "triggered" : "listening…"

           // ✅ Fire only on threshold cross WITH 10s cooldown
           guard config.sendNotifications, isAbove else { return }

           let now = Date()

           // Enforce 10-second cooldown
           if let lastSent = lastNotificationSentAt,
              now.timeIntervalSince(lastSent) < 10 {
               return
           }

           // ✅ Timestamp BEFORE sending to avoid race conditions
           lastNotificationSentAt = now

           NotificationService.shared.sendPush(
               subject: config.notificationTitle,
               body: config.notificationBody,
               taskId: taskId,
               eventType: "sound_threshold_crossed",
               sourceDeviceID: nil
           )
       }
   }



   struct SoundLevelBubbleDB: View {
       let peakDb: Float   // dBFS (<= 0, typically negative)

       var body: some View {
           ZStack {
               Circle()
                   .fill(AppTheme.surface)
                   .overlay(
                       Circle().strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                   )
                   .frame(width: 140, height: 140)

               VStack(spacing: 6) {
                   Text("Sound Level (dB)")
                       .font(.caption.weight(.semibold))
                       .foregroundStyle(.secondary)

                   Text(String(format: "%.1f", peakDb))
                       .font(.system(size: 34, weight: .bold, design: .rounded))
                       .monospacedDigit()
                       .foregroundStyle(.primary)

                   Text("dBFS")
                       .font(.caption)
                       .foregroundStyle(.secondary)
               }
               .frame(width: 140, height: 140)
           }
           .padding(.top, 4)
       }
   }

// slider 0.1...1.0  (LOW threshold -> sensitive; HIGH threshold -> strict)
private func dbThreshold(from slider: Float) -> Float {
// Low threshold (slider=0.1) => easier => lower dB threshold (more negative)
// High threshold (slider=1.0) => harder => higher dB threshold (closer to 0)

// Recommended range: -30 dB (easy) up to -8 dB (strict)
let minDb: Float = -34
let maxDb: Float = -6

return minDb + (maxDb - minDb) * slider
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

let encoded = samples.map { ["t": Timestamp(date: $0.time), "v": $0.value] }
payload["samples"] = encoded

ref.setData(payload, merge: true) { err in
if let err = err {
print("Sound task end failed: \(err.localizedDescription)")
}
}
}
}

// MARK: - Fixed-size bubble

struct SoundLevelBubble: View {
let level: Float

var body: some View {
ZStack {
Circle()
.fill(AppTheme.surface)
.overlay(
Circle().strokeBorder(.primary.opacity(0.10), lineWidth: 1)
)
.frame(width: 140, height: 140)

VStack(spacing: 6) {
Text("Sound Level (n)")
.font(.caption.weight(.semibold))
.foregroundStyle(.secondary)

Text(String(format: "%.2f", level))
.font(.system(size: 34, weight: .bold, design: .rounded))
.monospacedDigit()
.foregroundStyle(.primary)

Text(levelDescriptor(level))
.font(.caption)
.foregroundStyle(.secondary)
}
.frame(width: 140, height: 140)
}
.padding(.top, 4)
}

private func levelDescriptor(_ v: Float) -> String {
switch v {
case ..<0.10: return "Quiet"
case ..<0.35: return "Moderate"
default: return "Loud"
}
}
}

// MARK: - Audio Monitor

final class SoundLevelMonitor: NSObject, ObservableObject, AVAudioRecorderDelegate {
@Published var level: Float = 0
// normalized 0...1 for UI
@Published var peakDb: Float = -160          // actual dB (peak)

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
timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true)
{ [weak self] _ in
self?.updateLevel()
}
} catch {
// keep silent for now
}
}





private func updateLevel() {
guard let recorder = recorder else { return }
recorder.updateMeters()

// Use PEAK power for event detection
let peak = recorder.peakPower(forChannel: 0) // dB in [-160, 0]
peakDb = peak

// Normalize dB to 0...1 for display (tweak floor as you like)
let floorDb: Float = -60
let clamped = max(floorDb, min(0, peak))
let normalized = (clamped - floorDb) / (0 - floorDb) // 0...1

DispatchQueue.main.async {
self.level = normalized
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

// MARK: - Models

struct SoundSensorConfig: Codable, Hashable {
var notificationTitle: String
var notificationBody: String
var threshold: Float
var sendNotifications: Bool
}

struct SessionSamplePoint: Identifiable, Hashable {
let id = UUID()
let time: Date
let value: Double
}

// MARK: - Minimal shared UI + helpers (unchanged)

struct Bullet: View {
let title: String
let detail: String

init(_ title: String, detail: String) {
self.title = title
self.detail = detail
}

var body: some View {
HStack(alignment: .top, spacing: 10) {
Image(systemName: "checkmark.seal.fill")
.font(.system(size: 14, weight: .semibold))
.padding(.top, 2)
.foregroundStyle(.secondary)

VStack(alignment: .leading, spacing: 2) {
Text(title)
.font(.subheadline.weight(.semibold))
Text(detail)
.font(.footnote)
.foregroundStyle(.secondary)
}
}
}
}

struct Tag: View {
let text: String
var fixedWidth: CGFloat? = nil
var monospaced: Bool = false

init(_ text: String, fixedWidth: CGFloat? = nil, monospaced: Bool = false) {
self.text = text
self.fixedWidth = fixedWidth
self.monospaced = monospaced
}

var body: some View {
Group {
if monospaced {
Text(text).monospacedDigit()
} else {
Text(text)
}
}
.font(.caption.weight(.semibold))
.lineLimit(1)
.frame(width: fixedWidth, alignment: .center)
.padding(.horizontal, 10)
.padding(.vertical, 6)
.background(AppTheme.surface)
.overlay(
Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 1)
)
.clipShape(Capsule())
}
}

struct SignalBarsView: View {
let level: Double

var body: some View {
GeometryReader { geo in
let h = geo.size.height
let w = geo.size.width
let bars = 18
let gap: CGFloat = 4
let barW = max(2, (w - CGFloat(bars - 1) * gap) / CGFloat(bars))

HStack(alignment: .bottom, spacing: gap) {
ForEach(0..<bars, id: \.self) { i in
let frac = Double(i + 1) / Double(bars)
let on = level >= frac
RoundedRectangle(cornerRadius: 3)
.frame(width: barW, height: max(6, h * CGFloat(frac)))
.opacity(on ? 1.0 : 0.25)
}
}
.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
}
}
}

struct ModernTextFieldSurface: ViewModifier {
func body(content: Content) -> some View {
content
.textInputAutocapitalization(.sentences)
.disableAutocorrection(false)
.padding(.horizontal, 12)
.padding(.vertical, 12)
.background(AppTheme.surface)
.overlay(
RoundedRectangle(cornerRadius: 14, style: .continuous)
.strokeBorder(.primary.opacity(0.10), lineWidth: 1)
)
.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
}
}
/*
struct BeforeYouBeginCard: View {
let title: String
let subtitle: String
let bullets: [(String, String)]

var body: some View {
VStack(alignment: .leading, spacing: 10) {
HStack(alignment: .center, spacing: 10) {
ZStack {
RoundedRectangle(cornerRadius: 12, style: .continuous)
.fill(AppTheme.surface)
.overlay(
RoundedRectangle(cornerRadius: 12, style: .continuous)
.strokeBorder(.primary.opacity(0.08), lineWidth: 1)
)
.frame(width: 44, height: 44)
//   systemImage: AppSymbols.best(["ear.badge.waveform", "ear"]))
Image(systemName: "ear.badge.waveform")
.font(.system(size: 18, weight: .semibold))
.foregroundStyle(.secondary)
}

VStack(alignment: .leading, spacing: 2) {
Text(title)
.font(.headline)
Text(subtitle)
.font(.footnote)
.foregroundStyle(.secondary)
}

Spacer()
}

VStack(alignment: .leading, spacing: 10) {
    ForEach(Array(bullets.enumerated()), id: \.offset) { _, item in
Bullet(item.0, detail: item.1)
}
}
.padding(.top, 4)
}
.padding(14)
.background(AppTheme.surface)
.overlay(
RoundedRectangle(cornerRadius: 18, style: .continuous)
.strokeBorder(.primary.opacity(0.08), lineWidth: 1)
)
.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
}
}
*/

struct BeforeYouBeginCard: View {
   let title: String
   let subtitle: String
   let bullets: [(String, String)]

   var body: some View {
       VStack(alignment: .leading, spacing: 14) {

           // Header
           HStack(alignment: .center, spacing: 12) {
               Image(systemName: "ear.badge.waveform")
                   .font(.system(size: 18, weight: .semibold))
                   .foregroundStyle(.secondary)
                   .frame(width: 44, height: 44)
                   .background(
                       RoundedRectangle(cornerRadius: 12, style: .continuous)
                           .fill(AppTheme.surface)
                           .overlay(
                               RoundedRectangle(cornerRadius: 12, style: .continuous)
                                   .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                           )
                   )

               VStack(alignment: .leading, spacing: 3) {
                   Text(title)
                       .font(.headline)

                   Text(subtitle)
                       .font(.footnote)
                       .foregroundStyle(.secondary)
                       .fixedSize(horizontal: false, vertical: true)
               }

               Spacer(minLength: 0)
           }

           // Items (no visible bullets)
           VStack(alignment: .leading, spacing: 0) {
               ForEach(Array(bullets.enumerated()), id: \.offset) { idx, item in
                   VStack(alignment: .leading, spacing: 4) {
                       Text(item.0)
                           .font(.subheadline.weight(.semibold))

                       Text(item.1)
                           .font(.footnote)
                           .foregroundStyle(.secondary)
                           .fixedSize(horizontal: false, vertical: true)
                   }
                   .padding(.vertical, 10)

                   if idx != bullets.count - 1 {
                       Divider()
                           .opacity(0.10)
                   }
               }
           }
           .padding(.top, 2)
       }
       .padding(16)
       .background(AppTheme.surface)
       .overlay(
           RoundedRectangle(cornerRadius: 18, style: .continuous)
               .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
       )
       .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
   }
}
// MARK: - forceEndAllTasks (paste into ContentView)

func forceEndAllTasks(endedBy: String, completion: ((Error?) -> Void)? = nil) {
guard let uid = Auth.auth().currentUser?.uid else {
completion?(NSError(
domain: "Auth",
code: -1,
userInfo: [NSLocalizedDescriptionKey: "No user logged in"]
))
return
}

let db = Firestore.firestore()
let tasksRef = db.collection("users").document(uid).collection("tasks")

// Goal:
// - End every task that is still "open" (missing endedAt OR endedAt == null)
// - Do NOT modify tasks that already have a valid endedAt timestamp
//
// Firestore cannot query "field does not exist", so we do two passes:
//   1) endedAt == null  (matches explicit null)
//   2) fetch remaining candidates and end those missing endedAt (client-side filter)
//
// If you guarantee endedAt is always written as null at creation time, pass #2 will do nothing.

let now = FieldValue.serverTimestamp()

func endDocs(_ docs: [QueryDocumentSnapshot], completion: @escaping (Error?) -> Void) {
guard !docs.isEmpty else { completion(nil); return }

let batch = db.batch()
for doc in docs {
batch.updateData([
"endedAt": now,
"endedBy": "multiple_active_cleanup"
], forDocument: doc.reference)
}
batch.commit { err in completion(err) }
}

// PASS 1: endedAt explicitly null
tasksRef
.whereField("endedAt", isEqualTo: NSNull())
.getDocuments { snapNull, err in
if let err = err {
completion?(err)
return
}

let nullDocs = snapNull?.documents ?? []

endDocs(nullDocs) { err in
if let err = err {
completion?(err)
return
}

// PASS 2: endedAt missing (cannot be queried directly)
tasksRef.getDocuments { snapAll, err in
if let err = err {
completion?(err)
return
}

let allDocs = snapAll?.documents ?? []

let missingEndedAtDocs: [QueryDocumentSnapshot] = allDocs.filter { doc in
let data = doc.data()
if data.keys.contains("endedAt") == false { return true }
return data["endedAt"] is NSNull
}

endDocs(missingEndedAtDocs) { err in
completion?(err)
}
}
}
}
}
import Firebase
import FirebaseFirestore
import FirebaseAuth

/// Ends ONLY "open" tasks (endedAt missing or null) that belong to the given deviceID.
/// Use this on app load to clean up tasks left open if the user exited mid-task.
///
/// Notes:
/// - Prefers serverTimestamp for endedAt.
/// - Uses two-pass strategy because Firestore cannot query "field does not exist".
/// - Pass 1: endedAt == null (queryable) AND deviceID matches.
/// - Pass 2: fetch tasks for this deviceID and end those where endedAt is missing or NSNull.
func forceEndOpenTasksForDevice(
deviceID: String,
endedBy: String,
completion: ((Error?) -> Void)? = nil
) {
guard !deviceID.isEmpty else {
completion?(NSError(
domain: "Device",
code: -1,
userInfo: [NSLocalizedDescriptionKey: "Missing deviceID"]
))
return
}

guard let uid = Auth.auth().currentUser?.uid else {
completion?(NSError(
domain: "Auth",
code: -1,
userInfo: [NSLocalizedDescriptionKey: "No user logged in"]
))
return
}

let db = Firestore.firestore()
let tasksRef = db.collection("users").document(uid).collection("tasks")
let now = FieldValue.serverTimestamp()

func endDocs(_ docs: [QueryDocumentSnapshot], completion: @escaping (Error?) -> Void) {
guard !docs.isEmpty else { completion(nil); return }

let batch = db.batch()
for doc in docs {
batch.updateData([
"endedAt": now,
"endedBy": "app_load_cleanup",
"endedDeviceID": deviceID
], forDocument: doc.reference)
}
batch.commit { err in completion(err) }
}

// PASS 1: endedAt explicitly null (queryable), scoped to this deviceID
tasksRef
.whereField("deviceID", isEqualTo: deviceID)
.whereField("endedAt", isEqualTo: NSNull())
.getDocuments { snapNull, err in
if let err = err {
completion?(err)
return
}

let nullDocs = snapNull?.documents ?? []

endDocs(nullDocs) { err in
if let err = err {
completion?(err)
return
}

// PASS 2: endedAt missing (cannot be queried)
// We fetch only tasks for this deviceID, then client-filter for missing/null endedAt.
tasksRef
.whereField("deviceID", isEqualTo: deviceID)
.getDocuments { snapAll, err in
if let err = err {
completion?(err)
return
}

let allDocs = snapAll?.documents ?? []

let stillOpenDocs: [QueryDocumentSnapshot] = allDocs.filter { doc in
let data = doc.data()

// Open if:
// - endedAt missing
// - endedAt == NSNull
// (Do NOT end tasks that already have a Timestamp endedAt.)
if data.keys.contains("endedAt") == false { return true }
return data["endedAt"] is NSNull
}

endDocs(stillOpenDocs) { err in
completion?(err)
}
}
}
}
}
