//
//  MJPEGViewerApp.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/20.
//

import SwiftUI

// This file is no longer used as the main app entry point
// SmartGuardApp.swift is now the main entry point
struct MJPEGViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(
                cameraViewModel: CameraViewModel(),
                weatherViewModel: WeatherViewModel()
            )
        }
    }
}
