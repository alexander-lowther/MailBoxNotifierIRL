


import SwiftUI
struct TasksTab: View {
    let deviceID: String
    private let tasks: [TaskTile] = [
        .init(
            title: "Light Change",
            subtitle: "Camera detects light shift",
            useCases: "MailBox, Cabinet, Door Open",
            systemImage: AppSymbols.best(["bolt.badge.clock", "bolt"]),
            destination: .light,
            assetImage: "MailBox"
        ),
        
        
        .init(
            title: "Sound Spike",
            subtitle: "Detect sound above a threshold",
            useCases: "Dog Bark, Doorbell, Alarm",
            systemImage: AppSymbols.best(["ear.badge.waveform","ear"]),
            destination: .sound,
            assetImage: nil
        ),
        .init(
            title: "Vibration Change",
            subtitle: "Vibration on vs off",
            useCases: "Dryer, Compressor, Vehicle",
            systemImage: AppSymbols.best(["waveform.path.ecg", "waveform"]),
            destination: .vibe,
            assetImage: nil
        ),
        .init(
            title: "Power Loss",
            subtitle: "Detect charging lost/restored",
            useCases: "Power Outage",
            systemImage: AppSymbols.best(["bolt.badge.clock", "bolt"]),
            destination: .power ,
            assetImage: nil
        ),
        
        
            .init(
                title: "Angle Change",
                subtitle: "Level will detect tilt in degress",
                useCases: "Incline, Level",
                systemImage: AppSymbols.best(["bolt.badge.clock", "bolt"]),
                destination: .level,
                assetImage: nil
            ),
        
        
  
 //       .init(
 //           title: "Camera",
  //          subtitle: "Multi-purpose streaming camera",
  //          useCases: "Security, Dash Cam",
  //          systemImage: AppSymbols.best(["video", "camera"]),
  //          destination: .camera,
  //          assetImage: nil
  //      ),

        // Add your other tasks here…
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Tasks")
                    .font(.largeTitle.bold())
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 16   // ✅ vertical spacing only (row-to-row)
                ) {
                    ForEach(tasks) { tile in
                        CompatNavigationLink {
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
            SoundSensorSetupView(functionTitle: "Sound Spike", deviceID: deviceID)

        case .vibe:
            VibeSensorSetupView(functionTitle: "Vibration \n Change", deviceID: deviceID)

        case .power:
            PowerLossSetupView(functionTitle: "Power Loss", deviceID: deviceID)
            // NOTE: you renamed the file to PowerTask.swift, but the struct name
            // in the code I provided is PowerLossSetupView. That is fine.
            // File name does not need to match struct name.
        case .level:
            LevelSensorSetupView(functionTitle: "Angle Changes", deviceID: deviceID)
            
        case .light:
            LightChangeSetupView(functionTitle: "Light Changes", deviceID: deviceID)
            
        case .camera:
                CameraRelaySetupView(functionTitle: "Camera", deviceID: deviceID)
        }
    }
}

private struct TaskCard: View {
    let tile: TaskTile

    private var displayTitle: String {
        tile.title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
        
            HStack(alignment: .center, spacing: 12) {
                
                if tile.assetImage == nil {

                    Image(systemName: tile.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 40, height: 40)
                        .background(Color.green.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                } else {
                    Image(tile.assetImage!)
                        .resizable()
                        .scaledToFit()
                      //  .renderingMode(.template)
                        .foregroundStyle(.black)
                        .frame(width: 24, height: 24)
                        .frame(width: 40, height: 40)
                        .background(Color.green.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                }
                Text(displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)     // a touch more help for long titles
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading) // ✅ take remaining width
                    .layoutPriority(1)            // ✅ stop the squeeze-wrap weirdness
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(tile.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(tile.useCases)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .padding(10)

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
    case camera
}
private struct TaskTile: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let useCases: String
    let systemImage: String
    let destination: TaskDestination
    let assetImage: String?
}
