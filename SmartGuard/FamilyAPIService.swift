//
//  FamilyAPIService.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/21.
//

import Foundation
import UIKit
import Combine

struct FamilyMember: Codable, Identifiable {
    let id = UUID()
    let name: String
    var relationship: String = "Family Member"
    var registeredDate: Date = Date()
    var lastSeen: Date?
    var recognitionCount: Int = 0
    var status: FamilyMemberStatus = .home

    enum CodingKeys: String, CodingKey {
        case name
    }

    init(name: String, relationship: String = "Family Member") {
        self.name = name
        self.relationship = relationship
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
    }
}

struct APIResponse: Codable {
    let ok: Bool
    let labels: [String]?
    let error: String?
    let saved: [String]?
    let running: Bool?
    let count: Int?
    let waited: Bool?
    let timeoutHit: Bool?

    enum CodingKeys: String, CodingKey {
        case ok, labels, error, saved, running, count, waited
        case timeoutHit = "timeout_hit"
    }
}

struct RegisterResponse: Codable {
    let ok: Bool
    let label: String?
    let saved: [String]?
    let retrained: Bool?
    let error: String?
    let count: Int?
}

class FamilyAPIService: ObservableObject {
    @Published var familyMembers: [FamilyMember] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    let statusManager: FamilyStatusManager
    private var statusObserver: AnyCancellable?

    // cache
    private let cacheKey = "CachedFamilyMembers"
    private var lastCacheTime: Date?

    init(statusManager: FamilyStatusManager) {
        self.statusManager = statusManager
        setupStatusObserver()
        loadCachedMembers()
    }

    private func setupStatusObserver() {
        statusObserver = statusManager.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateMemberStatuses()
            }
        }
    }

    private func updateMemberStatuses() {
        for i in familyMembers.indices {
            let oldStatus = familyMembers[i].status
            let newStatus = statusManager.getStatus(for: familyMembers[i].name)
            if oldStatus != newStatus {
                print("📱 UI狀態更新: \(familyMembers[i].name) \(oldStatus.rawValue) → \(newStatus.rawValue)")
            }
            familyMembers[i].status = newStatus
        }
    }

    private func loadCachedMembers() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([String].self, from: data) {
            self.familyMembers = cached.map { name in
                statusManager.addMember(name)
                var member = FamilyMember(name: name, relationship: getRelationshipForName(name))
                member.status = statusManager.getStatus(for: name)
                return member
            }
            lastCacheTime = UserDefaults.standard.object(forKey: "\(cacheKey)_time") as? Date
        }
    }

    private func cacheMemberNames(_ names: [String]) {
        if let data = try? JSONEncoder().encode(names) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: "\(cacheKey)_time")
            lastCacheTime = Date()
        }
    }

    private var shouldRefreshCache: Bool {
        guard let lastTime = lastCacheTime else { return true }
        return Date().timeIntervalSince(lastTime) > 300 // 5 min cache
    }

    private var baseURL: String {
        let urlString = UserDefaults.standard.string(forKey: "mjpegURL") ?? "http://192.168.1.199:5000/mjpeg"
        // Extract base URL from MJPEG URL
        if let url = URL(string: urlString),
           let scheme = url.scheme,
           let host = url.host,
           let port = url.port {
            return "\(scheme)://\(host):\(port)"
        } else if let url = URL(string: urlString),
                  let scheme = url.scheme,
                  let host = url.host {
            // Default to port 5000 if not specified
            return "\(scheme)://\(host):5000"
        }
        return "http://192.168.1.199:5000"
    }

    func loadFamilyMembers(forceRefresh: Bool = false) {
        if !forceRefresh && !familyMembers.isEmpty && !shouldRefreshCache {
            return
        }

        isLoading = true
        errorMessage = nil


        guard let url = URL(string: "\(baseURL)/recog/labels") else {
            DispatchQueue.main.async {
                self.errorMessage = "Invalid URL"
                self.isLoading = false
            }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    if error.localizedDescription.contains("timed out") ||
                       error.localizedDescription.contains("Could not connect") ||
                       error.localizedDescription.contains("network connection") {
                        if self?.familyMembers.isEmpty == true {
                            self?.familyMembers = []
                        }
                        self?.errorMessage = nil
                    } else {
                        self?.errorMessage = "Network error: \(error.localizedDescription)"
                    }
                    return
                }

                guard let data = data else {
                    self?.familyMembers = []
                    self?.errorMessage = nil
                    return
                }

                do {
                    // Debug: Print raw response
                    if let jsonString = String(data: data, encoding: .utf8) {
                    }

                    let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
                    let memberNames = apiResponse.labels ?? []

                    self?.cacheMemberNames(memberNames)

                    self?.familyMembers = memberNames.map { name in
                        self?.statusManager.addMember(name)
                        var member = FamilyMember(name: name, relationship: self?.getRelationshipForName(name) ?? "Family Member")
                        member.status = self?.statusManager.getStatus(for: name) ?? .home
                        return member
                    }

                    print("Family members created: \(self?.familyMembers.map { $0.name } ?? [])")
                    self?.errorMessage = nil
                } catch {
                    print("Decode error: \(error)")
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("Raw JSON: \(json)")
                        if let labels = json["labels"] as? [String] {
                            print("found labels in raw JSON: \(labels)")
                            self?.cacheMemberNames(labels)

                            self?.familyMembers = labels.map { name in
                                        self?.statusManager.addMember(name)
                                var member = FamilyMember(name: name, relationship: self?.getRelationshipForName(name) ?? "Family Member")
                                member.status = self?.statusManager.getStatus(for: name) ?? .home
                                return member
                            }
                        } else {
                            self?.familyMembers = []
                        }
                    } else {
                        self?.familyMembers = []
                    }
                    self?.errorMessage = nil
                }
            }
        }.resume()
    }

    func reloadRecognizer(completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/recog/reload") else {
            completion(false, "Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, "Network error: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                completion(false, "No data received")
                return
            }

            do {
                let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
                completion(apiResponse.ok, apiResponse.error)
            } catch {
                completion(false, "Failed to decode response: \(error.localizedDescription)")
            }
        }.resume()
    }

    func registerFamilyMember(label: String, completion: @escaping (Bool, String?, Int?) -> Void) {
        guard let url = URL(string: "\(baseURL)/recog/register") else {
            completion(false, "Invalid URL", nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90.0

        let requestBody = ["label": label]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(false, "Failed to encode request", nil)
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, "Network error: \(error.localizedDescription)", nil)
                return
            }

            guard let data = data else {
                completion(false, "No data received", nil)
                return
            }

            do {
                let registerResponse = try JSONDecoder().decode(RegisterResponse.self, from: data)
                let photoCount = registerResponse.saved?.count ?? registerResponse.count ?? 0

                if registerResponse.ok {
                    completion(true, nil, photoCount)
                } else {
                    completion(false, registerResponse.error ?? "Registration failed", photoCount)
                }
            } catch {
                completion(false, "Failed to decode response: \(error.localizedDescription)", nil)
            }
        }.resume()
    }

    func updateMemberDetails(name: String, relationship: String, completion: @escaping (Bool, String?) -> Void) {
        // Save relationship mapping locally
        saveRelationshipMapping(name: name, relationship: relationship)

        // Reload family members to get updated list
        loadFamilyMembers()

        completion(true, nil)
    }

    func enrollFamilyMember(name: String, relationship: String, image: UIImage, completion: @escaping (Bool, String?) -> Void) {
        isLoading = true
        errorMessage = nil

        guard let url = URL(string: "\(baseURL)/recog/enroll") else {
            completion(false, "Invalid URL")
            isLoading = false
            return
        }

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(false, "Failed to convert image")
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add label field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"label\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(name)\r\n".data(using: .utf8)!)

        // Add image field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    completion(false, "Network error: \(error.localizedDescription)")
                    return
                }

                guard let data = data else {
                    completion(false, "No data received")
                    return
                }

                do {
                    let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
                    if apiResponse.ok {
                        // Save relationship mapping
                        self?.saveRelationshipMapping(name: name, relationship: relationship)
                        // Reload family members
                        self?.loadFamilyMembers()
                        completion(true, nil)
                    } else {
                        completion(false, apiResponse.error ?? "Registration failed")
                    }
                } catch {
                    completion(false, "Failed to decode response: \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    func saveRelationshipMapping(name: String, relationship: String) {
        UserDefaults.standard.set(relationship, forKey: "relationship_\(name)")
    }

    private func getRelationshipForName(_ name: String) -> String {
        return UserDefaults.standard.string(forKey: "relationship_\(name)") ?? "Family Member"
    }
}
