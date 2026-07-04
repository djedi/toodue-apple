import Foundation

/// Everything the app persists for offline use: the last-known server state
/// plus the queue of writes that haven't reached the server yet.
struct Snapshot: Codable, Sendable {
    var user: User?
    var projects: [Project] = []
    var tasks: [TodoTask] = []
    var queue: [Mutation] = []
    /// Monotonically decreasing counter for temp (offline) ids.
    var nextTempID: Int64 = -1
}

/// JSON-file persistence in Application Support. All state fits comfortably
/// in memory for a personal task list; simplicity beats a database here.
struct LocalStore: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TooDue", isDirectory: true)
    }

    private var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }

    func load() -> Snapshot {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return Snapshot() }
        return snapshot
    }

    func save(_ snapshot: Snapshot) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: snapshotURL, options: .atomic)
        } catch {
            // Persistence is best-effort; the in-memory state remains authoritative.
            print("LocalStore save failed: \(error)")
        }
    }

    func wipe() {
        try? FileManager.default.removeItem(at: snapshotURL)
    }
}
