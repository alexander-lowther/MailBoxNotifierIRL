
import SwiftUI



// MARK: - Card UI (keep in this file, or move to AppUI.swift)
//
//  TasksTab.swift
//  Mailbox Notifier IRL
//
//  Updated to include Vibration + Power tasks.
//

import SwiftUI

struct TasksTab: View {
    let userUID: String
    let deviceID: String

    // Keep your task catalog simple and explicit
    private let tasks: [TaskTile] = [
        .init(
            title: "Sound Sensor",
            subtitle: "Detect sound above a threshold",
            systemImage: AppSymbols.best(["ear.badge.waveform","ear"]),
            destination: .sound
        ),
        .init(
            title: "Vibration Sensor",
            subtitle: "Detect vibration started/stopped",
            systemImage: AppSymbols.best(["waveform.path.ecg", "waveform"]),
            destination: .vibe
        ),
        .init(
            title: "Power Loss",
            subtitle: "Detect charging lost/restored",
            systemImage: AppSymbols.best(["bolt.badge.clock", "bolt"]),
            destination: .power
        ),
        
        
            .init(
                title: "Level Sensor",
                subtitle: "Measure Angles",
                systemImage: AppSymbols.best(["bolt.badge.clock", "bolt"]),
                destination: .level
            ),
        
        
            .init(
                title: "Light Change",
                subtitle: "Notify mail",
                systemImage: AppSymbols.best(["bolt.badge.clock", "bolt"]),
                destination: .light
            ),
        
        // Add your other tasks here…
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tasks")
                    .font(.largeTitle.bold())

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(tasks) { tile in
                        NavigationLink {
                            destinationView(for: tile.destination)
                        } label: {
                            TaskCard(tile: tile)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func destinationView(for dest: TaskDestination) -> some View {
        switch dest {
        case .sound:
            SoundSensorSetupView(functionTitle: "Sound Sensor")

        case .vibe:
            VibeSensorSetupView(functionTitle: "Vibration Sensor")

        case .power:
            PowerLossSetupView(functionTitle: "Power Loss")
            // NOTE: you renamed the file to PowerTask.swift, but the struct name
            // in the code I provided is PowerLossSetupView. That is fine.
            // File name does not need to match struct name.
        case .level:
            LevelSensorSetupView(functionTitle: "Level Sensor")
            
        case .light:
            LightChangeSensorSetupView(functionTitle: "Light Change")
        }
    }
}
private struct TaskCard: View {
    let tile: TaskTile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: tile.systemImage)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(10)
                    .background(Color.green.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()
            }

            Text(tile.title)
                .font(.headline)

            Text(tile.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Simple model

private enum TaskDestination {
    case sound
    case vibe
    case power
    case level
    case light
}
private struct TaskTile: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let destination: TaskDestination
}
