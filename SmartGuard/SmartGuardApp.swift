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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
