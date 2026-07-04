import Foundation
import Testing
@testable import TooDue

@Suite("Server URL normalization")
struct ServerConfigTests {
    @Test func bareHostnameGetsHTTPS() throws {
        #expect(try ServerConfig.normalize("toodue.example.com").absoluteString == "https://toodue.example.com")
    }

    @Test func trailingSlashesStripped() throws {
        #expect(try ServerConfig.normalize("https://td.example.com///").absoluteString == "https://td.example.com")
    }

    @Test func whitespaceTrimmed() throws {
        #expect(try ServerConfig.normalize("  app.toodue.com \n").absoluteString == "https://app.toodue.com")
    }

    @Test func plainHTTPAllowedForLANServers() throws {
        #expect(try ServerConfig.normalize("http://192.168.1.5:8080").absoluteString == "http://192.168.1.5:8080")
    }

    @Test func rejectsEmptyAndGarbage() {
        #expect(throws: APIError.self) { try ServerConfig.normalize("") }
        #expect(throws: APIError.self) { try ServerConfig.normalize("   ") }
        #expect(throws: APIError.self) { try ServerConfig.normalize("ftp://example.com") }
        #expect(throws: APIError.self) { try ServerConfig.normalize("https://") }
    }

    @Test func officialServerRoundTrips() throws {
        // Typing the official URL by hand must normalize to exactly the
        // default, so AppState clears the self-hosted override.
        #expect(try ServerConfig.normalize("https://app.toodue.com/").absoluteString
                == ServerConfig.defaultURLString)
        #expect(try ServerConfig.normalize("app.toodue.com").absoluteString
                == ServerConfig.defaultURLString)
    }
}
