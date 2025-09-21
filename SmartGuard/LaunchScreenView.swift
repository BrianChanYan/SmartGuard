//
//  LaunchScreenView.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/20.
//

import SwiftUI

struct LaunchScreenView: View {
    @ObservedObject var appState: AppStateManager
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var showLoadingItems = false

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()
                Spacer() 

                // Logo
                VStack(spacing: 20) {
                    Image("top_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 80)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)

                }

                // Loading Progress
                VStack(spacing: 20) {
                    // Progress Bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(
                                    colors: [Color(red: 255/255, green: 129/255, blue: 79/255), Color.orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .frame(width: geometry.size.width * appState.loadingProgress, height: 4)
                                .animation(.easeInOut(duration: 0.3), value: appState.loadingProgress)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 60)

                    // Loading Text
                    Text(appState.loadingText)
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    // Loading Items
                    if showLoadingItems {
                        VStack(alignment: .leading, spacing: 12) {
                            LoadingItemView(
                                icon: "antenna.radiowaves.left.and.right",
                                text: "連接攝影機",
                                isLoaded: appState.streamReady
                            )

                            LoadingItemView(
                                icon: "location.circle.fill",
                                text: "獲取天氣資訊",
                                isLoaded: appState.weatherLoaded
                            )

                            LoadingItemView(
                                icon: "checkmark.shield.fill",
                                text: "系統檢查",
                                isLoaded: appState.systemChecked
                            )
                        }
                        .padding(.horizontal, 60)
                        .transition(.opacity)
                    }
                }

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        // Logo animation
        withAnimation(.easeOut(duration: 0.8)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }

        // Show loading items
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeIn(duration: 0.3)) {
                showLoadingItems = true
            }
        }
    }
}

struct LoadingItemView: View {
    let icon: String
    let text: String
    let isLoaded: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isLoaded ? "checkmark.circle.fill" : icon)
                .foregroundColor(isLoaded ? .green : .gray)
                .font(.system(size: 20))
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundColor(isLoaded ? .white : .gray)

            Spacer()

            if !isLoaded {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
    }
}

struct LaunchScreenView_Previews: PreviewProvider {
    static var previews: some View {
        LaunchScreenView(appState: AppStateManager())
    }
}
