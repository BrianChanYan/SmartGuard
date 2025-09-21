//
//  AppStateManager.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/20.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class AppStateManager: ObservableObject {
    @Published var isLoading = true
    @Published var loadingProgress: Double = 0
    @Published var loadingText = "initializing..."

    // Loading states
    @Published var weatherLoaded = false
    @Published var streamReady = false
    @Published var systemChecked = false

    // Shared ViewModels
    let cameraViewModel = CameraViewModel()
    let weatherViewModel = WeatherViewModel()

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupObservers()
    }

    private func setupObservers() {
        cameraViewModel.$isConnected
            .sink { [weak self] isConnected in
                if isConnected {
                    self?.streamReady = true
                }
            }
            .store(in: &cancellables)

        // weather loading state
        weatherViewModel.$temperature
            .sink { [weak self] temp in
                if temp != "--" && temp != "--°C" {
                    self?.weatherLoaded = true
                }
            }
            .store(in: &cancellables)
    }

    func startPreloading(urlString: String) {
        Task {
            await startLoadingSequence(urlString: urlString)
        }
    }

    private func startLoadingSequence(urlString: String) async {
        do {
            //Connect to stream
            await updateLoadingState(text: "連接攝影機...", progress: 0.2)
            cameraViewModel.start(urlString: urlString)

            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 sec

            // Load weather
            await updateLoadingState(text: "獲取天氣資訊...", progress: 0.5)
            weatherViewModel.fetchWeather()

            // Wait for weather
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 sec

            await updateLoadingState(text: "系統檢查...", progress: 0.8)
            systemChecked = true
            try await Task.sleep(nanoseconds: 800_000_000) // 0.8 sec

            // Complete
            await updateLoadingState(text: "準備完成", progress: 1.0)
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 sec

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isLoading = false
                }
            }

            print("preload complete")
        } catch {
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isLoading = false
                }
            }
        }
    }

    private func updateLoadingState(text: String, progress: Double) async {
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.loadingText = text
                self.loadingProgress = progress
            }
        }
    }
}
