//
//  FaceRecognitionHandler.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/21.
//

import Foundation
import UIKit

class FaceRecognitionHandler: ObservableObject {
    private let statusManager: FamilyStatusManager
    private let securityManager: SecurityAlertManager
    private let baseURL: String

    private var lastRecognitionResults: [String] = []
    private var recognitionTimer: Timer?

    init(statusManager: FamilyStatusManager, securityManager: SecurityAlertManager, baseURL: String) {
        self.statusManager = statusManager
        self.securityManager = securityManager
        self.baseURL = baseURL
        startRecognitionPolling()
    }

    deinit {
        recognitionTimer?.invalidate()
    }

    private func startRecognitionPolling() {
        recognitionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.fetchRecognitionResults()
        }
    }

    private func fetchRecognitionResults() {
        fetchCurrentDetections { [weak self] detectedPeople in
            if !detectedPeople.isEmpty {
            }
            self?.processRecognitionResults(detectedPeople)
        }
    }

    private func simulateRecognitionAPI(completion: @escaping ([String]) -> Void) {

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            let mockResults: [String] = []
            completion(mockResults)
        }
    }

    private func processRecognitionResults(_ detectedNames: [String]) {
        DispatchQueue.main.async {
            for name in detectedNames {
                if !self.lastRecognitionResults.contains(name) {

                    self.statusManager.handleFaceDetection(for: name)

                    self.securityManager.processDetection(name: name)
                }
            }


            self.lastRecognitionResults = detectedNames
        }
    }

    func simulateDetection(for name: String) {
        statusManager.handleFaceDetection(for: name)
        securityManager.processDetection(name: name)
    }
}

// MARK: - Real API Implementation
extension FaceRecognitionHandler {

    private func fetchCurrentDetections(completion: @escaping ([String]) -> Void) {
        guard let url = URL(string: "\(baseURL)/recog/current") else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  error == nil else {
                completion([])
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let people = json["people"] as? [[String: Any]] {
                    let detectedNames = people.compactMap { person in
                        person["label"] as? String
                    }
                    completion(detectedNames)
                } else {
                    completion([])
                }
            } catch {
                completion([])
            }
        }.resume()
    }

    private func realRecognitionAPI(completion: @escaping ([String]) -> Void) {
        fetchCurrentDetections(completion: completion)
    }
}
