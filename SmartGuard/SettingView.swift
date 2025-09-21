//
//  SettingView.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/20.
//

import SwiftUI
import Foundation

struct SettingsView: View {
    @Binding var urlString: String
    @Binding var videoQuality: String
    @Environment(\.dismiss) private var dismiss
    @State private var workingURL = ""
    @State private var workingQuality = ""

    private let qualityOptions = ["480p (SD)", "720p (HD)", "1080p (FHD)", "4K (UHD)"]

    var body: some View {
        ZStack {
            Color(red: 0x09/255.0, green: 0x09/255.0, blue: 0x09/255.0).ignoresSafeArea()

            VStack(spacing: 20) {
                // Top Bar
                HStack {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))

                    Spacer()

                    Image("face")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                ScrollView {
                    VStack(spacing: 20) {
                        // User Profile Card
                        VStack(spacing: 16) {
                            HStack(spacing: 16) {
                                // Avatar with modern styling
                                ZStack {
                                    Circle()
                                        .fill(Color(red: 255/255, green: 129/255, blue: 79/255).opacity(0.2))
                                        .frame(width: 80, height: 80)

                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .frame(width: 60, height: 60)
                                        .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("User")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)

                                    Text("SmartGuard System")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)

                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 8, height: 8)
                                        Text("Online")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }

                                Spacer()

                                Button(action: {
                                    // Edit profile action
                                }) {
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))
                                        .font(.title3)
                                }
                            }
                            .padding(20)
                        }
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(16)
                        .padding(.horizontal, 20)

                        // Camera Settings Card
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "camera.fill")
                                    .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))
                                    .font(.title3)
                                Text("Camera Settings")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.top, 14)
                            .padding(.leading, 9)

                            VStack(alignment: .leading, spacing: 12) {
                                Text("MJPEG Stream URL")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)

                                TextField("http://<board-ip>:5000/mjpeg", text: $workingURL)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(8)

                                if !isValidURL(workingURL) && !workingURL.isEmpty {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                            .font(.caption)
                                        Text("Invalid URL format")
                                            .foregroundColor(.red)
                                            .font(.caption)
                                    }
                                }
                            }
                            .padding(16)
                        }
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(16)
                        .padding(.horizontal, 20)

                        // Video Quality Card
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "video.fill")
                                    .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))
                                    .font(.title3)
                                Text("Video Quality")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.top, 14)
                            .padding(.leading, 9)

                            VStack(spacing: 12) {
                                ForEach(qualityOptions, id: \.self) { quality in
                                    QualityOptionRow(
                                        quality: quality,
                                        isSelected: workingQuality == quality,
                                        onTap: { workingQuality = quality }
                                    )
                                }
                            }
                            .padding(16)
                        }
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(16)
                        .padding(.horizontal, 20)

                        // System Info Card
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))
                                    .font(.title3)
                                Text("System Information")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.top, 14)
                            .padding(.leading, 9)

                            VStack(spacing: 12) {
                                SystemInfoRow(title: "App Version", value: "1.0.0")
                                SystemInfoRow(title: "System Version", value: "iOS 17.0")
                                SystemInfoRow(title: "Device Model", value: "iPhone")
                                SystemInfoRow(title: "Connection Status", value: "Connected", valueColor: .green)
                            }
                            .padding(16)
                        }
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(16)
                        .padding(.horizontal, 20)

                        // Save Button
                        Button(action: {
                            let oldURL = urlString
                            urlString = workingURL
                            videoQuality = workingQuality

                            let successFeedback = UINotificationFeedbackGenerator()
                            successFeedback.notificationOccurred(.success)

                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                Text("Save Settings")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                isValidURL(workingURL) ?
                                Color(red: 255/255, green: 129/255, blue: 79/255) :
                                Color.gray
                            )
                            .cornerRadius(16)
                        }
                        .disabled(!isValidURL(workingURL))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                }

                Spacer()
            }
        }
        .onAppear {
            workingURL = urlString
            workingQuality = videoQuality
        }
    }

    private func isValidURL(_ s: String) -> Bool {
        guard let u = URL(string: s) else { return false }
        return ["http", "https"].contains(u.scheme?.lowercased())
    }
}

// MARK: - Supporting Views
struct QualityOptionRow: View {
    let quality: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(quality)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)

                    Text(qualityDescription(for: quality))
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))
                        .font(.title3)
                } else {
                    Circle()
                        .strokeBorder(Color.gray, lineWidth: 2)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(12)
            .background(isSelected ? Color(red: 255/255, green: 129/255, blue: 79/255).opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func qualityDescription(for quality: String) -> String {
        switch quality {
        case "480p (SD)": return "Standard quality - Save bandwidth"
        case "720p (HD)": return "High quality - Recommended"
        case "1080p (FHD)": return "Full HD - Best clarity"
        case "4K (UHD)": return "Ultra HD - Requires high-speed network"
        default: return ""
        }
    }
}

struct SystemInfoRow: View {
    let title: String
    let value: String
    var valueColor: Color = .white

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(valueColor)
        }
        .padding(.vertical, 4)
    }
}
