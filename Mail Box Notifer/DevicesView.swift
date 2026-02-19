
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct DevicesView: View {
    let userUID: String  // kept for compatibility with your routing

    @State private var devices: [DeviceDoc] = []
    @State private var errorText: String? = nil
    @State private var isLoading: Bool = true

    @State private var nameEdits: [String: String] = [:]
    @State private var savingIDs: Set<String> = []

    // iOS 15+ supported
    @FocusState private var focusedDeviceID: String?

    // iOS 15-safe replacement for iOS 17's onChange(old:new)
    @State private var previousFocusedDeviceID: String? = nil

    // Uses your existing stable device id provider
    private let localDeviceID = DeviceIdentity.id()

 
    var body: some View {
        AppNavigationContainer {
            List {
                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Text("Tap a device name to rename it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Devices") {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading devices…")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else if devices.isEmpty {
                        Text("No devices found.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(devices) { d in
                            VStack(alignment: .leading, spacing: 10) {

                                HStack(spacing: 10) {
                                    Image(systemName: d.deviceSymbol)
                                        .font(.system(size: 18, weight: .semibold))
                                        .frame(width: 28)

                                    TextField(
                                        "Device name",
                                        text: Binding(
                                            get: { nameEdits[d.id] ?? d.displayName },
                                            set: { nameEdits[d.id] = $0 }
                                        )
                                    )
                                    .focused($focusedDeviceID, equals: d.id)
                                    .textInputAutocapitalization(.words)
                                    .disableAutocorrection(true)
                                    .font(.headline)
                                    .onSubmit { commitNameIfNeeded(d) }

                                    Spacer()

                                    // ✅ Visible affordance that it's editable
                                    Image(systemName: "pencil")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.tertiary)

                                    if savingIDs.contains(d.id) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }

                                    if d.id == localDeviceID {
                                        Text("This device")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.thinMaterial)
                                            .clipShape(Capsule())
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    focusedDeviceID = d.id
                                }

                                Text(d.secondaryDescription)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)

                                if let createdAt = d.createdAt {
                                    Text("Registered \(createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 10) // ✅ more breathing room
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)   // ✅ more “production” feel
            .navigationTitle("Devices")
            .onAppear { loadDevicesOnce() }
            .refreshable { loadDevicesOnce() }

            .onChange(of: focusedDeviceID) { newValue in
                let old = previousFocusedDeviceID
                previousFocusedDeviceID = newValue

                if let old, newValue != old {
                    if let device = devices.first(where: { $0.id == old }) {
                        commitNameIfNeeded(device)
                    }
                }
            }

            .onDisappear {
                if let focused = focusedDeviceID,
                   let device = devices.first(where: { $0.id == focused }) {
                    commitNameIfNeeded(device)
                }
            }
        }
    }
    // MARK: - Save logic (same DB behavior)

    private func commitNameIfNeeded(_ device: DeviceDoc) {
        let trimmed = (nameEdits[device.id] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, trimmed != (device.name ?? "") else { return }
        saveName(deviceId: device.id)
    }

    private func loadDevicesOnce() {
        errorText = nil
        isLoading = true

        // Hard-assert auth UID consistency; do not trust a potentially stale passed userUID.
        guard let authUID = Auth.auth().currentUser?.uid, !authUID.isEmpty else {
            devices = []
            errorText = "Not signed in."
            isLoading = false
            return
        }

        Firestore.firestore()
            .collection("users")
            .document(authUID)
            .collection("devices")
            .getDocuments { snap, err in
                isLoading = false

                if let err = err {
                    errorText = err.localizedDescription
                    devices = []
                    return
                }

                let docs = snap?.documents ?? []
                let mapped = docs.map { DeviceDoc(id: $0.documentID, data: $0.data()) }

                // Stable sort to prevent list jump
                let sorted = mapped.sorted { a, b in
                    switch (a.createdAt, b.createdAt) {
                    case let (da?, db?):
                        if da != db { return da < db }
                        return a.id < b.id
                    case (_?, nil): return true
                    case (nil, _?): return false
                    default: return a.id < b.id
                    }
                }

                devices = sorted

                // Seed edit buffers (don’t overwrite active edits)
                for d in sorted where nameEdits[d.id] == nil {
                    nameEdits[d.id] = d.name ?? ""
                }
            }
    }

    private func saveName(deviceId: String) {
        errorText = nil

        guard let authUID = Auth.auth().currentUser?.uid, !authUID.isEmpty else {
            errorText = "Not signed in."
            return
        }

        let trimmed = (nameEdits[deviceId] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return }

        savingIDs.insert(deviceId)

        Firestore.firestore()
            .collection("users")
            .document(authUID)
            .collection("devices")
            .document(deviceId)
            .setData(["name": trimmed], merge: true) { err in
                savingIDs.remove(deviceId)

                if let err = err {
                    errorText = err.localizedDescription
                    return
                }

                // Update UI immediately
                if let idx = devices.firstIndex(where: { $0.id == deviceId }) {
                    devices[idx] = devices[idx].withName(trimmed)
                }

                // Persist local device name for reuse elsewhere
                if deviceId == localDeviceID {
                    UserDefaults.standard.set(trimmed, forKey: "local_device_name")
                }
            }
    }
}

// MARK: - Model

private struct DeviceDoc: Identifiable {
    let id: String
    let name: String?
    let model: String?
    let systemVersion: String?
    let createdAt: Date?

    init(id: String, data: [String: Any]) {
        self.id = id
        self.name = data["name"] as? String
        self.model = data["model"] as? String
        self.systemVersion = data["systemVersion"] as? String
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
    }

    func withName(_ newName: String) -> DeviceDoc {
        var data: [String: Any] = [:]
        data["name"] = newName
        if let model { data["model"] = model }
        if let systemVersion { data["systemVersion"] = systemVersion }
        if let createdAt { data["createdAt"] = Timestamp(date: createdAt) }
        return DeviceDoc(id: id, data: data)
    }

    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return name }
        if let model, let systemVersion { return "\(model) (iOS \(systemVersion))" }
        if let model { return model }
        return "Device"
    }
}

private extension DeviceDoc {
    var deviceSymbol: String {
        let m = (model ?? "").lowercased()
        if m.contains("watch") { return "applewatch" }
        if m.contains("ipad") { return "ipad" }
        if m.contains("iphone") { return "iphone" }
        return "questionmark.circle"
    }

    var secondaryDescription: String {
        if let model, let systemVersion {
            return "\(model) • iOS \(systemVersion)"
        }
        if let model { return model }
        return "Device"
    }
}
