
//
//  TaskDetailView.swift
//  Mail Box Notifer
//
//  Charts read from task document field: samples: [ { t: Timestamp, v: Double } ]
//  Samples are persisted ONLY when user taps "Stop Listening".
//

import SwiftUI
import FirebaseFirestore

#if canImport(Charts)
import Charts
#endif

struct TaskDetailView: View {
    let userUID: String
    let task: TaskDoc

    @State private var points: [TaskSamplePoint] = []
    @State private var errorText: String? = nil
    @State private var listener: ListenerRegistration?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                chartSection
            }
            .padding()
        }
        .navigationTitle(task.name)
        .onAppear { startListeningTaskDoc() }
        .onDisappear { stopListening() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Device: \(task.deviceName)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Started: \(task.startedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let ended = task.endedAt {
                Text("Ended: \(ended.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Status: In progress")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        Group {
            if points.isEmpty {
                Text("Chart not available.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                #if canImport(Charts)
                if #available(iOS 16.0, *) {
                    Chart(points) { p in
                        LineMark(
                            x: .value("Time", p.t),
                            y: .value("Value", p.v)
                        )
                    }
                    .frame(height: 220)
                    .padding(.top, 8)
                } else {
                    Text("Charts require iOS 16+.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                #else
                Text("Charts framework not available.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                #endif
            }
        }
    }

    private func startListeningTaskDoc() {
        stopListening()

        let db = Firestore.firestore()
        listener = db.collection("users")
            .document(userUID)
            .collection("tasks")
            .document(task.id)
            .addSnapshotListener { snap, err in
                if let err = err {
                    errorText = err.localizedDescription
                    points = []
                    return
                }
                errorText = nil

                guard let data = snap?.data() else {
                    points = []
                    return
                }

                let raw = data["samples"] as? [[String: Any]] ?? []
                let parsed = raw.compactMap { TaskSamplePoint(data: $0) }
                points = parsed.sorted { $0.t < $1.t }
            }
    }

    private func stopListening() {
        listener?.remove()
        listener = nil
    }
}

struct TaskSamplePoint: Identifiable {
    let id: String
    let t: Date
    let v: Double

    init?(data: [String: Any]) {
        guard
            let ts = data["t"] as? Timestamp,
            let v = data["v"] as? Double
        else { return nil }

        self.id = UUID().uuidString
        self.t = ts.dateValue()
        self.v = v
    }
}
