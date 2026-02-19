import Foundation
#if canImport(FoundationNetworking) && canImport(FoundationXML)
import FoundationNetworking
import FoundationXML
#endif

class ResponsesServerSentEventsHandler: NSObject {
    var onEventReceived: ((Result<ResponseStreamEvent, OpenAIError>) -> Void)?
    var onComplete: (() -> Void)?

    private lazy var session: URLSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private var task: URLSessionDataTask?
    private var buffer = ""

    func connect(with request: URLRequest) {
        task = session.dataTask(with: request)
        task?.resume()
    }

    func disconnect() {
        task?.cancel()
    }

    private func processEvent(_ eventData: Data) {
        do {
            let event = try JSONDecoder().decode(ResponseStreamEvent.self, from: eventData)
            onEventReceived?(.success(event))
        } catch {
            onEventReceived?(.failure(.decodingError(error: error)))
        }
    }
}

extension ResponsesServerSentEventsHandler: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk

        let delimiter = "\n\n"
        while let range = buffer.range(of: delimiter) {
            let frame = String(buffer[..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])

            let lines = frame.split(separator: "\n", omittingEmptySubsequences: false)
            let payloadLines = lines.compactMap { line -> String? in
                guard line.hasPrefix("data:") else { return nil }
                return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
            guard !payloadLines.isEmpty else { continue }
            let payload = payloadLines.joined(separator: "\n")
            if payload == "[DONE]" { continue }

            if let payloadData = payload.data(using: .utf8) {
                processEvent(payloadData)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            onEventReceived?(.failure(.genericError(error: error)))
        } else {
            onComplete?()
        }
    }
}
