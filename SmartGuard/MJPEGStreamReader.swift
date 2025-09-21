//
//  MJPEGStreamReader.swift
//  SmartGuard
//
//  Created by Brian Chan on 2025/9/20.
//

import Foundation
import UIKit

// status
enum MJPEGStreamState {
    case connecting
    case streaming
    case disconnected
    case error(Error)
}

// MJPEG Stream Reader
final class MJPEGStreamReader: NSObject {
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var boundary: Data = Data("--frame\r\n".utf8)

    var onFrame: ((UIImage) -> Void)?
    var onState: ((MJPEGStreamState) -> Void)?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config,
                             delegate: self,
                             delegateQueue: .main)
    }

    func start(url: URL) {
        stop()
        onState?(.connecting)
        var req = URLRequest(url: url)
        req.setValue("multipart/x-mixed-replace", forHTTPHeaderField: "Accept")
        task = session.dataTask(with: req)
        task?.resume()
    }

    func stop() {
        task?.cancel()
        task = nil
        buffer.removeAll(keepingCapacity: false)
        onState?(.disconnected)
    }
}

// MARK: - URLSessionDataDelegate
extension MJPEGStreamReader: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)

        if let http = dataTask.response as? HTTPURLResponse,
           let ct = http.value(forHTTPHeaderField: "Content-Type"),
           ct.contains("boundary="),
           let marker = ct.split(separator: "=").last {
            boundary = Data("--\(marker)\r\n".utf8)
        }

        // *Loop parsing JPEG
        while let start = buffer.range(of: Data([0xFF, 0xD8])),
              let end = buffer.range(of: Data([0xFF, 0xD9]), in: start.lowerBound..<buffer.endIndex) {
            let jpegData = buffer[start.lowerBound...end.upperBound-1]
            buffer.removeSubrange(..<end.upperBound)

            if let img = UIImage(data: jpegData) {
                onFrame?(img)
                onState?(.streaming)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onState?(.error(error))
        }
        onState?(.disconnected)
    }
}
