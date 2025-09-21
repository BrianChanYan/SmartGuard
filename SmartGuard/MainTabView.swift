//
//  MainTabView.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/20.
//

import SwiftUI

struct MainTabView: View {
    let appState: AppStateManager
    @AppStorage("mjpegURL") private var urlString: String = "http://192.168.1.199:5000/mjpeg"
    @AppStorage("videoQuality") private var videoQuality: String = "720p (HD)"
    @State private var selectedTab = 1

    var body: some View {
        TabView(selection: $selectedTab) {
            TaskView()
                .tabItem {
                    Image(systemName: "person.3.fill")
                    Text("Family")
                }
                .tag(0)

            ContentView(
                cameraViewModel: appState.cameraViewModel,
                weatherViewModel: appState.weatherViewModel
            )
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(1)

            SettingsView(urlString: $urlString, videoQuality: $videoQuality)
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Setting")
                }
                .tag(2)
        }
        .accentColor(Color(red: 255/255, green: 129/255, blue: 79/255))
        .preferredColorScheme(.dark)
        .onChange(of: selectedTab) { _ in
            let selectionFeedback = UISelectionFeedbackGenerator()
            selectionFeedback.selectionChanged()
        }
        .onAppear {
            // 
            DispatchQueue.main.async {
                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = UIColor(red: 0x09/255.0, green: 0x09/255.0, blue: 0x09/255.0, alpha: 1.0)

                // color
                appearance.stackedLayoutAppearance.normal.iconColor = UIColor.gray
                appearance.stackedLayoutAppearance.selected.iconColor = UIColor(red: 255/255, green: 129/255, blue: 79/255, alpha: 1.0)

                appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray]
                appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(red: 255/255, green: 129/255, blue: 79/255, alpha: 1.0)]

                UITabBar.appearance().standardAppearance = appearance
                UITabBar.appearance().scrollEdgeAppearance = appearance

                appearance.stackedLayoutAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -5)
                appearance.stackedLayoutAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -5)
                appearance.stackedLayoutAppearance.normal.titleTextAttributes[.font] = UIFont.systemFont(ofSize: 10, weight: .medium)
                appearance.stackedLayoutAppearance.selected.titleTextAttributes[.font] = UIFont.systemFont(ofSize: 10, weight: .medium)

                UITabBar.appearance().isTranslucent = false
            }
        }
    }
}
