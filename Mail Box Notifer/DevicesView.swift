
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct DevicesView: View {
    let userUID: String

    @State private var devices: [DeviceDoc] = []
    @State private var errorText: String? = nil
    @State private var isLoading: Bool = true

    // Per-device editable name buffer
    @State private var nameEdits: [String: String] = [:]
    @State private var savingIDs: Set<String> = []

    // Use the same stable device ID scheme as ContentView.
    private let localDeviceID: String = {
        if let existing = UserDefaults.standard.string(forKey: "stable_device_id"), !existing.isEmpty {
            return existing
        }
        let newID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(newID, forKey: "stable_device_id")
        return newID
    }()

    var body: some View {
        NavigationStack {
            List {
                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Devices") {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading devices…")
                                .foregroundStyle(.secondary)
                        }
                    } else if devices.isEmpty {
                        Text("No devices found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(devices) { d in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                  //  Text(d.displayName)
                                   //     .font(.headline)

                                    if d.id == localDeviceID {
                                        Text("This device")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.thinMaterial)
                                            .clipShape(Capsule())
                                    }
                                }

                                // Rename (simple)
                                HStack(spacing: 10) {
                                    TextField("Device name", text: Binding(
                                        get: { nameEdits[d.id] ?? (d.name ?? "") },
                                        set: { nameEdits[d.id] = $0 }
                                    ))
                                    .textInputAutocapitalization(.words)
                                    .disableAutocorrection(true)

                                    Button("Save") {
                                        saveName(deviceId: d.id)
                                    }
                                    .disabled(savingIDs.contains(d.id))
                                }

                                Text(d.id)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                if let createdAt = d.createdAt {
                                    Text("Registered: \(createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                if let updatedAt = d.fcmTokenUpdatedAt {
                                    Text("Token updated: \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Text(d.tokenStatusText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("Devices")
            .onAppear { loadDevicesOnce() }
            .refreshable {
                // No realtime listeners; user explicitly refreshes.
                loadDevicesOnce()
            }
        }
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

                // Stable sort: createdAt then id (prevents reorder “jumping”)
                let sorted = mapped.sorted { a, b in
                    switch (a.createdAt, b.createdAt) {
                    case let (da?, db?):
                        if da != db { return da < db }
                        return a.id < b.id
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    default:
                        return a.id < b.id
                    }
                }

                devices = sorted

                // Seed edit buffers (do not overwrite any active edits)
                for d in sorted {
                    if nameEdits[d.id] == nil {
                        nameEdits[d.id] = d.name ?? ""
                    }
                }
            }
    }

    private func saveName(deviceId: String) {
        errorText = nil

        guard let authUID = Auth.auth().currentUser?.uid, !authUID.isEmpty else {
            errorText = "Not signed in."
            return
        }

        let raw = nameEdits[deviceId] ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errorText = "Device name cannot be empty."
            return
        }

        savingIDs.insert(deviceId)

        Firestore.firestore()
            .collection("users")
            .document(authUID)
            .collection("devices")
            .document(deviceId)
            .setData([
                "name": trimmed
            ], merge: true) { err in
                savingIDs.remove(deviceId)

                if let err = err {
                    errorText = err.localizedDescription
                    return
                }

                // Keep UI consistent without waiting for refresh
                if let idx = devices.firstIndex(where: { $0.id == deviceId }) {
                    devices[idx] = devices[idx].withName(trimmed)
                }

                // Persist local device name for easy reuse in Tasks (feature #2).
                if deviceId == localDeviceID {
                    UserDefaults.standard.set(trimmed, forKey: "local_device_name")
                }
            }
    }
}

private struct DeviceDoc: Identifiable {
    let id: String
    let name: String?
    let model: String?
    let systemVersion: String?
    let fcmToken: String?
    let createdAt: Date?
    let fcmTokenUpdatedAt: Date?

    init(id: String, data: [String: Any]) {
        self.id = id
        self.name = data["name"] as? String
        self.model = data["model"] as? String
        self.systemVersion = data["systemVersion"] as? String
        self.fcmToken = data["fcmToken"] as? String
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        self.fcmTokenUpdatedAt = (data["fcmTokenUpdatedAt"] as? Timestamp)?.dateValue()
    }

    func withName(_ newName: String) -> DeviceDoc {
        // Rebuild with only name changed
        var data: [String: Any] = [:]
        data["name"] = newName
        if let model { data["model"] = model }
        if let systemVersion { data["systemVersion"] = systemVersion }
        if let fcmToken { data["fcmToken"] = fcmToken }
        if let createdAt { data["createdAt"] = Timestamp(date: createdAt) }
        if let fcmTokenUpdatedAt { data["fcmTokenUpdatedAt"] = Timestamp(date: fcmTokenUpdatedAt) }
        return DeviceDoc(id: id, data: data)
    }

    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return name }
        if let model, let systemVersion { return "\(model) (iOS \(systemVersion))" }
        if let model { return model }
        return "Device"
    }

    var tokenStatusText: String {
        if let fcmToken, !fcmToken.isEmpty {
            return "Push token: present"
        }
        return "Push token: not available yet"
    }
}
