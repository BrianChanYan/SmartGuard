//
//  FamilyStatusManager.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/21.
//

import Foundation
import Combine

enum FamilyMemberStatus: String, CaseIterable, Codable {
    case home = "Home"
    case away = "Away"

    var color: String {
        switch self {
        case .home:
            return "green"
        case .away:
            return "orange"
        }
    }

    var icon: String {
        switch self {
        case .home:
            return "house.fill"
        case .away:
            return "figure.walk"
        }
    }
}

struct FamilyMemberStatusInfo {
    let name: String
    var status: FamilyMemberStatus
    var lastDetectionTime: Date?
    var lastStatusChangeTime: Date
    var detectionCooldownUntil: Date?

    init(name: String) {
        self.name = name
        self.status = .home
        self.lastDetectionTime = nil
        self.lastStatusChangeTime = Date()
        self.detectionCooldownUntil = nil
    }

    var isInDetectionCooldown: Bool {
        guard let cooldownUntil = detectionCooldownUntil else { return false }
        return Date() < cooldownUntil
    }
}

class FamilyStatusManager: ObservableObject {
    @Published private(set) var memberStatuses: [String: FamilyMemberStatusInfo] = [:]

    private let cooldownDuration: TimeInterval = 10.0

    var onStatusChanged: ((String, FamilyMemberStatus) -> Void)?

    // MARK: - Public Methods

    func addMember(_ name: String) {
        if memberStatuses[name] == nil {
            memberStatuses[name] = FamilyMemberStatusInfo(name: name)
            saveStatuses()
        }
    }

    func removeMember(_ name: String) {
        memberStatuses.removeValue(forKey: name)
        saveStatuses()
    }

    func getStatus(for name: String) -> FamilyMemberStatus {
        return memberStatuses[name]?.status ?? .home
    }

    func handleFaceDetection(for name: String) {
        guard var memberStatus = memberStatuses[name] else {
            addMember(name)
            handleFaceDetection(for: name)
            return
        }

        if memberStatus.isInDetectionCooldown {
            return
        }

        let oldStatus = memberStatus.status
        let newStatus: FamilyMemberStatus = memberStatus.status == .home ? .away : .home

        memberStatus.status = newStatus
        memberStatus.lastDetectionTime = Date()
        memberStatus.lastStatusChangeTime = Date()
        memberStatus.detectionCooldownUntil = Date().addingTimeInterval(cooldownDuration)

        memberStatuses[name] = memberStatus


        saveStatuses()

        onStatusChanged?(name, newStatus)

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    private func setStatus(for name: String, to status: FamilyMemberStatus) {
        guard var memberStatus = memberStatuses[name] else {
            addMember(name)
            setStatus(for: name, to: status)
            return
        }

        memberStatus.status = status
        memberStatus.lastStatusChangeTime = Date()
        memberStatuses[name] = memberStatus

        saveStatuses()

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func getAllStatuses() -> [String: FamilyMemberStatus] {
        return memberStatuses.mapValues { $0.status }
    }

    func cleanupExpiredCooldowns() {
        let now = Date()
        for (name, var status) in memberStatuses {
            if let cooldownUntil = status.detectionCooldownUntil, now >= cooldownUntil {
                status.detectionCooldownUntil = nil
                memberStatuses[name] = status
            }
        }
    }

    // MARK: - Persistence

    private func saveStatuses() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(memberStatuses) {
            UserDefaults.standard.set(data, forKey: "FamilyMemberStatuses")
        }
    }

    private func loadStatuses() {
        guard let data = UserDefaults.standard.data(forKey: "FamilyMemberStatuses") else { return }
        let decoder = JSONDecoder()
        if let statuses = try? decoder.decode([String: FamilyMemberStatusInfo].self, from: data) {
            memberStatuses = statuses
        }
    }

    // MARK: - Lifecycle

    init() {
        loadStatuses()

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.cleanupExpiredCooldowns()
        }
    }
}

// MARK: - Codable Support

extension FamilyMemberStatusInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case name, status, lastDetectionTime, lastStatusChangeTime, detectionCooldownUntil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.status = try container.decode(FamilyMemberStatus.self, forKey: .status)
        self.lastDetectionTime = try container.decodeIfPresent(Date.self, forKey: .lastDetectionTime)
        self.lastStatusChangeTime = try container.decode(Date.self, forKey: .lastStatusChangeTime)
        self.detectionCooldownUntil = try container.decodeIfPresent(Date.self, forKey: .detectionCooldownUntil)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(lastDetectionTime, forKey: .lastDetectionTime)
        try container.encode(lastStatusChangeTime, forKey: .lastStatusChangeTime)
        try container.encodeIfPresent(detectionCooldownUntil, forKey: .detectionCooldownUntil)
    }
}