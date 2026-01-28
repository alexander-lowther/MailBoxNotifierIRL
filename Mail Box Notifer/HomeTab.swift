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

                    VStack(alignment: .leading, spacing: 6) {

                        if task.name == "Camera" {
                            Text("camera temp")
                                .font(.headline)
                        } else {

                            Text(task.name)
                                .font(.headline)

                            Text("Started: \(task.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                    
                            
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                            VStack(alignment: .leading, spacing: 6) {
                                Text(task.name).font(.headline)
                                Text("Ended: \(task.endedAt?.formatted() ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if !task.hasSamples {
                                    Text("Chart not available")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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
        // Refresh when navigating back to Home (tab switch / re-entry)
        .onAppear {
            taskLog.refresh(userUID: userUID)
        }
        // Optional: user-initiated refresh gesture (no realtime listeners)
        .refreshable {
            taskLog.refresh(userUID: userUID)
        }
    }
}
