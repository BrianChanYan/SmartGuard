//
//  CameraViewModel.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/20.
//

import SwiftUI
import Combine
import Foundation
import UIKit

@MainActor
final class CameraViewModel: ObservableObject {
    @Published var image: UIImage?
    @Published var statusText: String = ""
    @Published var isConnected: Bool = false
    @Published var isStreaming: Bool = false

    private let reader = MJPEGStreamReader()

    init() {
        reader.onFrame = { [weak self] (img: UIImage) in self?.image = img }
        reader.onState = { [weak self] state in
            switch state {
            case .connecting:
                self?.statusText = "Connecting…"
                self?.isConnected = false
                self?.isStreaming = false
            case .streaming:
                self?.statusText = "Streaming"
                self?.isConnected = true
                self?.isStreaming = true
            case .disconnected:
                self?.statusText = "Disconnected"
                self?.isConnected = false
                self?.isStreaming = false
            case .error(let e):
                self?.statusText = "Error: \(e.localizedDescription)"
                self?.isConnected = false
                self?.isStreaming = false
            }
        }
    }

    func start(urlString: String) {
        guard let url = URL(string: urlString) else {
            statusText = "Bad URL"; return
        }
        reader.start(url: url)
    }

    func stop() { reader.stop() }
}
