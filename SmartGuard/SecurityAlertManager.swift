//
//  SecurityAlertManager.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/21.
//

import Foundation
import Combine
import UserNotifications

// MARK: - Event Models
struct SecurityEvent {
    let id = UUID()
    let timestamp: Date
    let type: SecurityEventType
    let description: String

    init(type: SecurityEventType, description: String) {
        self.timestamp = Date()
        self.type = type
        self.description = description
    }
}

enum SecurityEventType {
    case unknownDetected
    case memberArrived
    case memberLeft
    case securityAlert
    case systemEvent

    var icon: String {
        switch self {
        case .unknownDetected:
            return "person.fill.questionmark"
        case .memberArrived:
            return "house.fill"
        case .memberLeft:
            return "figure.walk"
        case .securityAlert:
            return "exclamationmark.triangle.fill"
        case .systemEvent:
            return "gear"
        }
    }

    var color: String {
        switch self {
        case .unknownDetected:
            return "orange"
        case .memberArrived:
            return "green"
        case .memberLeft:
            return "blue"
        case .securityAlert:
            return "red"
        case .systemEvent:
            return "gray"
        }
    }
}

// MARK: - Security Alert Manager
class SecurityAlertManager: ObservableObject {
    @Published var events: [SecurityEvent] = []
    @Published var isGuardModeActive = false

    private var unknownDetections: [Date] = []
    private var lastUnknownDetection: Date?
    private let unknownDetectionCooldown: TimeInterval = 20.0
    private let alertWindow: TimeInterval = 180.0
    private let alertThreshold = 3

    private let notificationCenter = UNUserNotificationCenter.current()

    init() {
        requestNotificationPermission()
        loadEvents()

        if events.isEmpty {
            addInitialEvents()
        }
    }

    private func addInitialEvents() {
        let initialEvents = [
            SecurityEvent(type: .systemEvent, description: "System started"),
            SecurityEvent(type: .systemEvent, description: "Video stream started"),
            SecurityEvent(type: .systemEvent, description: "Network connected")
        ]

        for event in initialEvents {
            events.append(event)
        }
        saveEvents()
    }

    // MARK: - Guard Mode Management
    func setGuardMode(_ isActive: Bool) {
        isGuardModeActive = isActive
        let event = SecurityEvent(
            type: .systemEvent,
            description: isActive ? "Guard Mode activated" : "Guard Mode deactivated"
        )
        addEvent(event)

        if !isActive {
            unknownDetections.removeAll()
            lastUnknownDetection = nil
        }
    }

    // MARK: - Detection Processing
    func processDetection(name: String) {
        if name.lowercased() == "unknown" {
            handleUnknownDetection()
        } else {
            handleKnownPersonDetection(name: name)
        }
    }

    private func handleUnknownDetection() {
        let now = Date()

        if let lastDetection = lastUnknownDetection,
           now.timeIntervalSince(lastDetection) < unknownDetectionCooldown {
            return
        }

        lastUnknownDetection = now

        if isGuardModeActive {
            unknownDetections.append(now)

            unknownDetections = unknownDetections.filter {
                now.timeIntervalSince($0) <= alertWindow
            }

            // Don't add unknown detection to events display
            // Only trigger security alert when threshold is reached


            if unknownDetections.count >= alertThreshold {
                triggerSecurityAlert()
            }
        }
    }

    private func handleKnownPersonDetection(name: String) {
        // Don't add regular member detection to events
        // Only send notification
        sendNotification(
            title: "👋 Family member detected",
            body: "\(name) has been detected",
            isAlert: false
        )
    }

    func handleMemberStatusChange(name: String, newStatus: FamilyMemberStatus) {
        // Don't add member status changes to events
        // Only send notification
        let actionText = newStatus == .home ? "arrived home" : "left home"
        let emoji = newStatus == .home ? "🏠" : "🚶‍♂️"
        sendNotification(
            title: "\(emoji) Family member status update",
            body: "\(name) \(actionText)",
            isAlert: false
        )
    }

    private func triggerSecurityAlert() {
        let event = SecurityEvent(
            type: .securityAlert,
            description: "⚠️ Security Alert: Unknown person detected \(unknownDetections.count) times in 3 minutes"
        )
        addEvent(event)

        sendNotification(
            title: "🚨 Security Alert",
            body: "Unknown person detected multiple times. Please be alert!",
            isAlert: true
        )


        unknownDetections.removeAll()
    }

    // MARK: - Event Management
    private func addEvent(_ event: SecurityEvent) {
        DispatchQueue.main.async {
            self.events.insert(event, at: 0)
            if self.events.count > 100 {
                self.events = Array(self.events.prefix(100))
            }
            self.saveEvents()
        }
    }

    // MARK: - Notifications
    private func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else {
                print("Notification permission denied")
            }
        }
    }

    private func sendNotification(title: String, body: String, isAlert: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = isAlert ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("Notification sending failed: \(error)")
            }
        }
    }

    // MARK: - Persistence
    private func saveEvents() {
        let recentEvents = Array(events.prefix(20))
        let eventData = recentEvents.map { event in
            [
                "timestamp": event.timestamp.timeIntervalSince1970,
                "type": event.type.rawValue as Any,
                "description": event.description
            ]
        }

        UserDefaults.standard.set(eventData, forKey: "SecurityEvents")
    }

    private func loadEvents() {
        if let eventData = UserDefaults.standard.array(forKey: "SecurityEvents") as? [[String: Any]] {
            self.events = eventData.compactMap { data in
                guard let timestamp = data["timestamp"] as? TimeInterval,
                      let description = data["description"] as? String else {
                    return nil
                }

                return SecurityEvent(
                    type: .systemEvent,
                    description: description
                )
            }
        }
    }
}

// MARK: - SecurityEventType RawRepresentable
extension SecurityEventType: RawRepresentable {
    var rawValue: String {
        switch self {
        case .unknownDetected: return "unknown"
        case .memberArrived: return "arrived"
        case .memberLeft: return "left"
        case .securityAlert: return "alert"
        case .systemEvent: return "system"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "unknown": self = .unknownDetected
        case "arrived": self = .memberArrived
        case "left": self = .memberLeft
        case "alert": self = .securityAlert
        case "system": self = .systemEvent
        default: return nil
        }
    }
}