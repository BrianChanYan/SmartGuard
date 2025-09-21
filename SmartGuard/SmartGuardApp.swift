//
//  SmartGuardApp.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/20.
//

import SwiftUI

@main
struct SmartGuardApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var appState = AppStateManager()
    @StateObject private var familyStatusManager = FamilyStatusManager()
    @StateObject private var securityManager = SecurityAlertManager()
    @AppStorage("mjpegURL") private var urlString: String = "http://192.168.1.199:5000/mjpeg"

    var body: some Scene {
        WindowGroup {
            ZStack {
                if appState.isLoading {
                    LaunchScreenView(appState: appState)
                        .transition(.opacity)
                } else {
                    MainTabView(appState: appState)
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .environmentObject(familyStatusManager)
                        .environmentObject(securityManager)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: appState.isLoading)
            .onAppear {
                appState.startPreloading(urlString: urlString)

                familyStatusManager.onStatusChanged = { name, newStatus in
                    securityManager.handleMemberStatusChange(name: name, newStatus: newStatus)
                }
            }
        }
    }
}
