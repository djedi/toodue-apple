import Foundation

/// Minimal Server-Sent Events listener for `/api/events`.
/// Emits decoded ServerEvents; the caller owns reconnection policy.
struct SSEClient: Sendable {
    let url: URL
    private let session: URLSession

    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    /// Connects and yields events until the connection drops or the task is
    /// cancelled. Throws on connect failure so callers can back off and retry.
    func events() -> AsyncThrowingStream<ServerEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 60 * 60 * 24
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw APIError.server(
                            status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                            message: "SSE connect failed"
                        )
                    }
                    var dataLines: [String] = []
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            let payload = dataLines.joined(separator: "\n")
                            dataLines = []
                            if let event = Self.parse(payload) {
                                continuation.yield(event)
                            }
                            continue
                        }
                        if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        }
                        // `:` comment lines and other fields are ignored.
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Payloads look like {"type":"task.upsert","data":{…}}; keepalives are "ping".
    static func parse(_ payload: String) -> ServerEvent? {
        guard !payload.isEmpty, payload != "ping",
              let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return nil }
        let inner = obj["data"].flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data("{}".utf8)
        return ServerEvent(type: type, data: inner)
    }
}
