//
//  MoreTab.swift
//  Mail Box Notifer
//
//  Created by user281046 on 1/21/26.
//

//
//  MoreTab.swift
//  Mail Box Notifer
//
//  5th bottom-tab screen: "More"
//  Contains sections/rows for Settings, About, and Upcoming.
//
//  Drop-in file. No other dependencies required.
//

import SwiftUI

struct MoreTab: View {
    let uid: String
    let deviceID: String

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Settings
                Section("Settings") {
                    NavigationLink {
                        MoreSettingsView(uid: uid, deviceID: deviceID)
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }

                    NavigationLink {
                        MoreSettingsView(uid: uid, deviceID: deviceID)
                    } label: {
                        Label("Device Name", systemImage: "iphone")
                    }

                    NavigationLink {
                        MoreSettingsView(uid: uid, deviceID: deviceID)
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                }

                // MARK: - About
                Section("About") {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About Mailbox Notifier IRL", systemImage: "info.circle")
                    }

                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Privacy", systemImage: "hand.raised")
                    }

                    NavigationLink {
                        SupportView()
                    } label: {
                        Label("Help & Support", systemImage: "questionmark.circle")
                    }
                }

                // MARK: - Upcoming
                Section("Upcoming") {
                    NavigationLink {
                        UpcomingView()
                    } label: {
                        Label("Roadmap", systemImage: "map")
                    }

                    NavigationLink {
                        UpcomingView()
                    } label: {
                        Label("Beta Features", systemImage: "sparkles")
                    }

                    NavigationLink {
                        UpcomingView()
                    } label: {
                        Label("Changelog", systemImage: "list.bullet.rectangle")
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

// MARK: - Placeholder Destinations (safe drop-in)
// Replace these with your real views when ready.

private struct MoreSettingsView: View {
    let uid: String
    let deviceID: String

    var body: some View {
        List {
            Section("Status") {
                Text("UID: \(uid)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("DeviceID: \(deviceID)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Settings") {
                Text("Settings UI goes here.")
            }
        }
        .navigationTitle("Settings")
    }
}

private struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mailbox Notifier IRL")
                    .font(.title2).bold()

                Text("Use multiple devices to detect events and notify your other signed-in devices.")
                    .foregroundStyle(.secondary)

                Divider()

                Text("Version")
                    .font(.headline)
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("About")
    }
}

private struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy")
                    .font(.title2).bold()
                Text("Privacy details go here.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Privacy")
    }
}

private struct SupportView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Help & Support")
                    .font(.title2).bold()
                Text("Support information goes here.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Support")
    }
}

private struct UpcomingView: View {
    var body: some View {
        List {
            Section("Upcoming") {
                Text("• Improved task reliability")
                Text("• Better cross-device visibility")
                Text("• Additional sensors and automations")
            }
        }
        .navigationTitle("Upcoming")
    }
}

// MARK: - Previews

#Preview {
    MoreTab(uid: "demoUID", deviceID: "demoDeviceID")
}
