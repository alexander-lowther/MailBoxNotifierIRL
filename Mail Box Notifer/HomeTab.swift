/*most recent*/
import SwiftUI
import Firebase
import FirebaseFirestore
private struct ActiveTaskRow {
    let taskName: String
    let deviceName: String
    let startedAt: Date
}



struct HomeTab: View {
    let userUID: String
    let deviceID: String

    @EnvironmentObject private var taskLog: TaskLog
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                Text("Active Tasks")
                    .font(.title2.bold())

                if taskLog.activeTasks.isEmpty {
                    Text("Activate a Task to View")
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                } else if let task = taskLog.activeTasks.first {
                    // Active task card (with chevron)
                    if task.name == "Camera" {
                        NavigationLink {
                            CameraRelayView (taskId: task.id, userUID: userUID, deviceID: deviceID, taskDeviceID: task.deviceID)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Camera")
                                        .font(.headline)

                                    Text("Tap to view live stream")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            TaskDetailView(userUID: userUID, task: task)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(task.name)
                                        .font(.headline)

                                    Text("Started: \(task.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            
                         //       Image(systemName: "chevron.right")
                         //           .font(.system(size: 14, weight: .semibold))
                         //           .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }.disabled(true)
                        .buttonStyle(.plain)
                    }
                }

                Text("Previous Tasks")
                    .font(.title2.bold())

                if taskLog.previousTasks.isEmpty {
                    Text("No completed tasks yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(taskLog.previousTasks) { task in
                        NavigationLink {
                            TaskDetailView(userUID: userUID, task: task)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(task.name)
                                        .font(.headline)

                                    Text("Ended: \(task.endedAt?.formatted() ?? "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if !task.hasSamples {
                                        Text("Chart not available")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Home")
        .onAppear { taskLog.refresh(userUID: userUID) }
        .refreshable { taskLog.refresh(userUID: userUID) }
    }

}
