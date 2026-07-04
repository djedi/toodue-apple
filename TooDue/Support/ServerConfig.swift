import Foundation

/// The hosted TooDue service and self-hosted override handling.
enum ServerConfig {
    /// Official hosted server — the default; self-hosting is the opt-in path.
    static let defaultURLString = "https://app.toodue.com"

    /// Normalize user input into a server base URL: trims whitespace, assumes
    /// https for bare hostnames, strips trailing slashes.
    static func normalize(_ raw: String) throws -> URL {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else {
            throw APIError.network("Enter your server address")
        }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s = String(s.dropLast()) }
        guard let url = URL(string: s), let scheme = url.scheme,
              ["http", "https"].contains(scheme), url.host() != nil
        else {
            throw APIError.network("That doesn't look like a valid URL")
        }
        return url
    }
}
