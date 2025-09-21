//
//  AddFamilyMemberView.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/21.
//

import SwiftUI
import UIKit
import Combine

// Registration ViewModel - Based on test folder implementation
@MainActor
final class RegistrationViewModel: ObservableObject {
    @Published var image: UIImage?
    @Published var statusText: String = ""
    @Published var isRegistering: Bool = false
    @Published var countdown: Int = 0
    @Published var currentPhotoCount: Int = 0
    @Published var totalPhotoCount: Int = 30

    private var baseURL: String = ""
    private let reader = MJPEGStreamReader()
    private var countdownTimer: Timer?

    init() {
        reader.onFrame = { [weak self] (img: UIImage) in self?.image = img }
        reader.onState = { [weak self] state in
            switch state {
            case .connecting:   self?.statusText = "Connecting to camera..."
            case .streaming:    self?.statusText = "Camera ready"
            case .disconnected: self?.statusText = "Camera disconnected"
            case .error(let e): self?.statusText = "Error: \(e.localizedDescription)"
            }
        }
    }

    func setBaseURL(fromMjpegURL mjpeg: String) {
        if let url = URL(string: mjpeg),
           var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var path = comps.path
            if path.hasSuffix("/mjpeg") {
                path.removeLast("/mjpeg".count)
                if path.isEmpty { path = "/" }
                comps.path = path
            }
            if let u = comps.url {
                baseURL = u.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let host = comps.host {
                    let scheme = comps.scheme ?? "http"
                    let port = (comps.port != nil) ? ":\(comps.port!)" : ""
                    baseURL = "\(scheme)://\(host)\(port)"
                }
            }
        }
    }

    func start(urlString: String) {
        setBaseURL(fromMjpegURL: urlString)
        guard let url = URL(string: urlString) else {
            statusText = "Invalid camera URL"
            return
        }
        reader.start(url: url)
    }

    func stop() {
        reader.stop()
        countdownTimer?.invalidate()
    }

    func register(label: String, completion: @escaping (Bool, String) -> Void) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusText = "Please enter a name"
            completion(false, "Please enter a name")
            return
        }
        guard !baseURL.isEmpty else {
            statusText = "Please connect to camera first"
            completion(false, "Camera not connected")
            return
        }
        guard let url = URL(string: "\(baseURL)/recog/register") else {
            statusText = "Invalid server URL"
            completion(false, "Invalid server URL")
            return
        }

        isRegistering = true
        currentPhotoCount = 0
        startCountdown()
        statusText = "Starting registration..."

        Task {
            defer {
                isRegistering = false
                countdownTimer?.invalidate()
            }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: Any] = [
                    "label": trimmed,
                    "target_count": totalPhotoCount,
                    "interval_ms": 200,
                    "wait": true,
                    "retrain": true,
                    "face": true
                ]

                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                // Extended timeout for capturing and training
                let cfg = URLSessionConfiguration.default
                cfg.timeoutIntervalForRequest = 120
                cfg.timeoutIntervalForResource = 120
                let session = URLSession(configuration: cfg)

                let (data, resp) = try await session.data(for: request)
                guard let http = resp as? HTTPURLResponse else {
                    statusText = "Invalid server response"
                    completion(false, "Invalid server response")
                    return
                }

                if (200..<300).contains(http.statusCode) {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let ok = json["ok"] as? Bool {
                        if ok {
                            let count = (json["saved"] as? [String])?.count ?? 0
                            statusText = "Success! Captured \(count) photos and retrained model"
                            completion(true, "Successfully registered \(trimmed)! \(count) photos captured and model retrained.")
                        } else {
                            let error = json["error"] as? String ?? "Unknown error"
                            statusText = "Registration failed: \(error)"
                            completion(false, "Registration failed: \(error)")
                        }
                    }
                } else if http.statusCode == 409 {
                    statusText = "Device busy, please try again later"
                    completion(false, "Device is currently busy with another registration. Please try again later.")
                } else {
                    let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                    statusText = "Server error: \(msg)"
                    completion(false, "Server error: \(msg)")
                }
            } catch {
                statusText = "Network error: \(error.localizedDescription)"
                completion(false, "Network error: \(error.localizedDescription)")
            }
        }
    }

    private func startCountdown() {
        countdown = 3
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            DispatchQueue.main.async {
                if self.countdown > 0 {
                    self.statusText = "Starting in \(self.countdown)..."
                    self.countdown -= 1
                } else {
                    self.statusText = "Capturing photos..."
                    self.startPhotoCapture()
                    timer.invalidate()
                }
            }
        }
    }

    private func startPhotoCapture() {
        // Simulate photo capture progress
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            DispatchQueue.main.async {
                if self.currentPhotoCount < self.totalPhotoCount && self.isRegistering {
                    self.currentPhotoCount += 1
                    self.statusText = "Capturing photo \(self.currentPhotoCount)/\(self.totalPhotoCount)..."

                    // Add some variation to make it feel more real
                    if self.currentPhotoCount >= self.totalPhotoCount - 3 {
                        self.statusText = "Processing and training model..."
                    }
                } else {
                    timer.invalidate()
                }
            }
        }
    }
}

struct AddFamilyMemberView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var apiService: FamilyAPIService

    @State private var name = ""
    @State private var relationship = "Family Member"
    @State private var isRegistering = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var registrationSuccess = false
    @State private var showSuccessOverlay = false

    @AppStorage("mjpegURL") private var urlString: String = "http://192.168.1.199:5000/mjpeg"
    @StateObject private var registrationViewModel = RegistrationViewModel()

    let relationships = ["Father", "Mother", "Son", "Daughter", "Grandfather", "Grandmother", "Brother", "Sister", "Other"]

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0x09/255.0, green: 0x09/255.0, blue: 0x09/255.0)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    headerView

                    ScrollView {
                        VStack(spacing: 24) {
                            // Camera Stream Section
                            cameraStreamView

                            // Registration Status
                            if isRegistering {
                                registrationStatusView
                            }

                            // Input Form
                            inputFormView

                            // Registration Button
                            registrationButtonView
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }

                // Success overlay
                if showSuccessOverlay {
                    ZStack {
                        Color.black.opacity(0.8)
                            .ignoresSafeArea()

                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 80, height: 80)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundColor(.white)
                            }

                            VStack(spacing: 8) {
                                Text("Registration Successful!")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)

                                Text("\(name) has been added to your family")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .scaleEffect(showSuccessOverlay ? 1.0 : 0.5)
                        .opacity(showSuccessOverlay ? 1.0 : 0.0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showSuccessOverlay)
                    }
                }
            }
            .navigationBarHidden(true)
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(registrationSuccess ? "Registration Successful" : "Registration Failed"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK")) {
                        // Always dismiss the view when alert is closed
                        dismiss()
                    }
                )
            }
            .onAppear {
                registrationViewModel.start(urlString: urlString)
            }
            .onDisappear {
                registrationViewModel.stop()
            }
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 4) {
                Text("Add Family Member")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Register face for recognition")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            // Placeholder for alignment
            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
    }

    // MARK: - Camera Stream View
    private var cameraStreamView: some View {
        VStack(spacing: 12) {
            ZStack {
                if let img = registrationViewModel.image {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(4/3, contentMode: .fill)
                        .frame(height: 280)
                        .clipped()
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black)
                        .frame(height: 280)
                        .overlay(
                            VStack(spacing: 16) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 255/255, green: 129/255, blue: 79/255)))
                                    .scaleEffect(1.2)
                                Text("Connecting to camera...")
                                    .foregroundColor(.white)
                                    .font(.subheadline)
                            }
                        )
                }

                // Face guide overlay
                if !isRegistering && registrationViewModel.image != nil {
                    RoundedRectangle(cornerRadius: 60)
                        .stroke(style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                        .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255).opacity(0.8))
                        .frame(width: 160, height: 200)
                        .overlay(
                            VStack {
                                Spacer()
                                Text("Position face here")
                                    .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.bottom, 8)
                            }
                        )
                }

                // Countdown overlay
                if isRegistering && registrationViewModel.countdown > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.8))
                            .frame(width: 100, height: 100)

                        Text("\(registrationViewModel.countdown)")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))
                    }
                }
            }

            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(registrationViewModel.image != nil ? .green : .red)
                    .frame(width: 8, height: 8)

                Text(registrationViewModel.statusText)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    // MARK: - Registration Status View
    private var registrationStatusView: some View {
        VStack(spacing: 16) {
            // Progress Ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: CGFloat(registrationViewModel.currentPhotoCount) / CGFloat(registrationViewModel.totalPhotoCount))
                    .stroke(
                        Color(red: 255/255, green: 129/255, blue: 79/255),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: registrationViewModel.currentPhotoCount)

                VStack {
                    Text("\(registrationViewModel.currentPhotoCount)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Text("/ \(registrationViewModel.totalPhotoCount)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            VStack(spacing: 8) {
                Text("📸 Capturing Photos")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("Please stay still and look at the camera")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }

    // MARK: - Input Form View
    private var inputFormView: some View {
        VStack(spacing: 20) {
            // Name Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))
                    .font(.subheadline)
                    .fontWeight(.semibold)

                TextField("Enter family member name", text: $name)
                    .textFieldStyle(CustomTextFieldStyle())
                    .autocapitalization(.words)
                    .disabled(isRegistering)
            }

            // Relationship Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Relationship")
                    .foregroundColor(Color(red: 255/255, green: 129/255, blue: 79/255))
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Menu {
                    ForEach(relationships, id: \.self) { rel in
                        Button(rel) {
                            relationship = rel
                        }
                    }
                } label: {
                    HStack {
                        Text(relationship)
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                }
                .disabled(isRegistering)
            }
        }
    }

    // MARK: - Registration Button View
    private var registrationButtonView: some View {
        Button(action: startRegistration) {
            HStack(spacing: 12) {
                if isRegistering {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.9)
                    Text("Registering...")
                } else {
                    Image(systemName: "camera.fill")
                        .font(.headline)
                    Text("Start Registration")
                }
            }
            .foregroundColor(.white)
            .font(.headline)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if name.isEmpty || isRegistering {
                        Color.gray.opacity(0.6)
                    } else {
                        LinearGradient(
                            colors: [
                                Color(red: 255/255, green: 129/255, blue: 79/255),
                                Color(red: 255/255, green: 100/255, blue: 50/255)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
            )
            .cornerRadius(16)
            .shadow(color: Color(red: 255/255, green: 129/255, blue: 79/255).opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(name.isEmpty || isRegistering)
        .scaleEffect(isRegistering ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isRegistering)
    }

    private func startRegistration() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            alertMessage = "Please enter a name"
            showAlert = true
            return
        }

        isRegistering = true

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Register using the test folder approach
        registrationViewModel.register(label: trimmedName) { success, message in
            DispatchQueue.main.async {
                self.isRegistering = false

                if success {
                    // Save relationship mapping
                    self.apiService.saveRelationshipMapping(name: trimmedName, relationship: self.relationship)

                    // Success feedback
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)

                    // Delay to allow server to complete training, then reload family members
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        print("✅ Registration success, reloading family members...")
                        self.apiService.loadFamilyMembers()
                    }

                    // Show success overlay
                    self.showSuccessOverlay = true

                    // Auto-dismiss after successful registration with a slight delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        dismiss()
                    }

                    self.registrationSuccess = true
                    self.alertMessage = message
                } else {
                    self.registrationSuccess = false
                    self.alertMessage = message

                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)

                    // Only show alert for errors
                    self.showAlert = true
                }
            }
        }
    }
}

// MARK: - Custom TextField Style
struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
            .foregroundColor(.white)
    }
}