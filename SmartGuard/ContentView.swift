import SwiftUI
import Combine
import UIKit

struct ContentView: View {
    @ObservedObject var cameraViewModel: CameraViewModel
    @ObservedObject var weatherViewModel: WeatherViewModel
    @AppStorage("mjpegURL") private var urlString: String = "http://192.168.1.199:5000/mjpeg"
    @AppStorage("videoQuality") private var videoQuality: String = "720p (HD)"
    @AppStorage("safeModeActivated") private var safeModeActivated = false
    @State private var isRefreshing = false


    @EnvironmentObject var statusManager: FamilyStatusManager
    @EnvironmentObject var securityManager: SecurityAlertManager
    @State private var recognitionHandler: FaceRecognitionHandler?

    var body: some View {
        ZStack {
            Color(red: 0x09/255.0, green: 0x09/255.0, blue: 0x09/255.0).ignoresSafeArea()

            VStack(spacing: 0) {
                // Fixed Top Bar with Title and Settings
                HStack {
                    Image("top_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)

                    Spacer()

                    // Weather Info
                    HStack(spacing: 8) {
                        Image(systemName: weatherViewModel.weatherIcon)
                            .foregroundColor(getWeatherIconColor(weatherViewModel.weatherIcon))
                            .font(.title3)

                        Text(weatherViewModel.temperature)
                            .foregroundColor(.white)
                            .font(.headline)
                            .fontWeight(.medium)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 15)
                .padding(.bottom, 5)
                .background(Color(red: 0x09/255.0, green: 0x09/255.0, blue: 0x09/255.0))
                .frame(maxWidth: .infinity)
                .zIndex(1)

                // Scrollable Content Area
                GeometryReader { geometry in
                    let navBarHeight: CGFloat = 130
                    let headerHeight: CGFloat = 60
                    let availableHeight = geometry.size.height - navBarHeight
                    let spacing: CGFloat = 15

                    let contentHeight = availableHeight - (spacing * 3)
                    let videoAreaHeight = contentHeight * 0.35
                    let statusHeight = contentHeight * 0.15
                    let eventsHeight = contentHeight * 0.35
                    let sliderHeight = contentHeight * 0.15

                    let screenWidth = geometry.size.width
                    let videoWidth = min(screenWidth - 40, 400)
                    let videoHeight = videoWidth * 3/4

                    VStack(spacing: spacing) {

                            // Video Stream Area
                            VStack {
                                ZStack {
                                    Rectangle()
                                        .fill(Color.black)
                                        .frame(width: videoWidth, height: videoHeight)
                                        .cornerRadius(16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.gray, lineWidth: 2)
                                        )

                                    ZStack {
                                        Group {
                                            if let img = cameraViewModel.image {
                                                Image(uiImage: img)
                                                    .resizable()
                                                    .aspectRatio(4/3, contentMode: .fill)
                                                    .frame(width: videoWidth, height: videoHeight)
                                                    .cornerRadius(16)
                                                    .clipped()
                                            } else {
                                                VStack(spacing: 20) {
                                                    ProgressView()
                                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                        .scaleEffect(1.5)

                                                    Text("Loading stream...")
                                                        .foregroundColor(.white)
                                                        .font(.headline)
                                                }
                                            }
                                        }

                                    }
                                    .frame(width: videoWidth, height: videoHeight)
                                    .clipped()

                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(cameraViewModel.isConnected ? .green : .red)
                                            .frame(width: 8, height: 8)
                                        Text(cameraViewModel.isConnected ? "connected" : "disconnected")
                                            .foregroundColor(.white)
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(8)
                                    .frame(width: videoWidth, height: videoHeight, alignment: .topTrailing)
                                    .padding(.trailing, 12)
                                    .padding(.top, 14)

                                    if safeModeActivated {
                                        HStack(spacing: 4) {
                                            Image(systemName: "shield.fill")
                                                .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))
                                                .font(.system(size: 12, weight: .bold))

                                            Text("Guard Mode")
                                                .foregroundColor(.white)
                                                .font(.system(size: 10, weight: .medium))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.7))
                                        .cornerRadius(6)
                                        .frame(width: videoWidth, height: videoHeight, alignment: .topLeading)
                                        .padding(.leading, 12)
                                        .padding(.top, 12)
                                        .animation(.easeInOut(duration: 0.3), value: safeModeActivated)
                                    }

                                }
                            }
                            .frame(height: videoHeight + 20)
                            .padding(.top, -5)

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Camera")
                                        .foregroundColor(.gray)
                                        .font(.subheadline)
                                    Text("Active")
                                        .foregroundColor(.green)
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }

                                Spacer()

                                VStack(alignment: .center, spacing: 4) {
                                    Text("Stream")
                                        .foregroundColor(.gray)
                                        .font(.subheadline)
                                    Text(cameraViewModel.isStreaming ? "Live" : "Offline")
                                        .foregroundColor(cameraViewModel.isStreaming ? .blue : .gray)
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Quality")
                                        .foregroundColor(.gray)
                                        .font(.subheadline)
                                    Text(videoQuality)
                                        .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                            }
                            .padding(.horizontal, 20)
                            .frame(height: 60)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Events") 
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)

                                ScrollView(showsIndicators: false) {
                                    VStack(spacing: 8) {
                                        if securityManager.events.isEmpty {
                                            EventRow(time: "14:32", event: "Motion detected", status: "Warning", statusColor: .orange)
                                            EventRow(time: "13:45", event: "System started", status: "Normal", statusColor: .green)
                                            EventRow(time: "12:18", event: "Connection lost", status: "Error", statusColor: .red)
                                            EventRow(time: "11:30", event: "Settings updated", status: "Complete", statusColor: .blue)
                                        } else {
                                            ForEach(securityManager.events.prefix(8), id: \.id) { event in
                                                SecurityEventRow(event: event)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                }
                                .frame(height: 160)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(12)
                                .padding(.horizontal, 20)
                            }
                            .frame(height: 210)

                            iPhoneSliderView(
                                onComplete: {
                                    let selectionFeedback = UISelectionFeedbackGenerator()
                                    selectionFeedback.selectionChanged()
                                    print("Guard Mode UI Activated")
                                },
                                onStateChanged: { isActive in
                                    securityManager.setGuardMode(isActive)
                                }
                            )
                            .frame(height: 85)
                            .padding(.bottom, 60)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 80)
                }
            }
            .offset(y: -10)
        }
        .onAppear {
            cameraViewModel.start(urlString: urlString)

            if weatherViewModel.temperature == "--" || weatherViewModel.temperature == "--°C" {
                weatherViewModel.fetchWeather()
            }

            setupRecognitionHandler()
        }
        .onChange(of: urlString) { newURL in
            cameraViewModel.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                cameraViewModel.start(urlString: newURL)
            }
        }
    }

    private func extractIPFromURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return "192.168.1.199"
        }
        return host
    }

    private func getWeatherIconColor(_ iconName: String) -> Color {
        if iconName.contains("sun") {
            return .yellow
        } else if iconName.contains("moon") {
            return .indigo
        } else if iconName.contains("cloud") {
            return .gray
        } else if iconName.contains("rain") || iconName.contains("drizzle") {
            return .blue
        } else if iconName.contains("snow") {
            return .cyan
        } else if iconName.contains("bolt") {
            return .purple
        } else if iconName.contains("fog") {
            return .gray.opacity(0.7)
        } else {
            return .gray
        }
    }

    private func setupRecognitionHandler() {
        let baseURL = extractBaseURLFromMJPEG(urlString)
        recognitionHandler = FaceRecognitionHandler(
            statusManager: statusManager,
            securityManager: securityManager,
            baseURL: baseURL
        )
    }

    private func extractBaseURLFromMJPEG(_ mjpegURL: String) -> String {
        if let url = URL(string: mjpegURL),
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var path = components.path
            if path.hasSuffix("/mjpeg") {
                path.removeLast("/mjpeg".count)
                if path.isEmpty { path = "/" }
                components.path = path
            }
            if let baseURL = components.url {
                let scheme = components.scheme ?? "http"
                let host = components.host ?? "192.168.1.199"
                let port = components.port ?? 5000
                return "\(scheme)://\(host):\(port)"
            }
        }
        return "http://192.168.1.199:5000"
    }
}

struct SecurityEventRow: View {
    let event: SecurityEvent

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: event.timestamp)
    }

    private var eventColor: Color {
        switch event.type {
        case .unknownDetected:
            return .orange
        case .memberArrived:
            return .green
        case .memberLeft:
            return .blue
        case .securityAlert:
            return .red
        case .systemEvent:
            return .gray
        }
    }

    var body: some View {
        HStack {
            Text(timeString)
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 45)

            Image(systemName: event.type.icon)
                .foregroundColor(eventColor)
                .font(.caption)
                .frame(width: 16)

            Text(event.description)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)

            Spacer()

            Circle()
                .fill(eventColor)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct EventRow: View {
    let time: String
    let event: String
    let status: String
    let statusColor: Color

    var body: some View {
        HStack {
            Text(time)
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 45)

            Text(event)
                .font(.subheadline)
                .foregroundColor(.white)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(status)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
