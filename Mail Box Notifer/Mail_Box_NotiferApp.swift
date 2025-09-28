//
//  Mail_Box_NotiferApp.swift
//  Mail Box Notifer
//
//  Created by Alexander Lowther on 7/22/25.
import SwiftUI
import Firebase
import FirebaseMessaging

@main
struct MailBoxNotifierIRLApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

