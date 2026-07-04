import Foundation

enum APIError: Error, LocalizedError, Equatable {
    /// Server answered with a non-2xx status and (usually) an {"error": …} body.
    case server(status: Int, message: String)
    /// Couldn't reach the server at all — the trigger for offline mode.
    case network(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .server(_, let message): message
        case .network(let message): message
        case .invalidResponse: "Unexpected response from server"
        }
    }

    var isUnauthorized: Bool {
        if case .server(let status, _) = self { status == 401 } else { false }
    }

    /// 4xx rejections are permanent — retrying the same request won't help.
    var isPermanentRejection: Bool {
        if case .server(let status, _) = self { (400...499).contains(status) } else { false }
    }
}

private struct ErrorBody: Decodable {
    var error: String
}

/// Thin client for the TooDue REST API. Auth is the `toodue_session` cookie,
/// which URLSession's shared cookie storage carries and persists automatically.
struct APIClient: Sendable {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: Auth

    func login(email: String, password: String) async throws -> User {
        try await post("/auth/login", body: LoginRequest(email: email, password: password))
    }

    func register(name: String, email: String, password: String) async throws -> User {
        try await post("/auth/register", body: RegisterRequest(name: name, email: email, password: password))
    }

    func logout() async throws {
        let _: OKResponse = try await post("/auth/logout")
    }

    func me() async throws -> User {
        try await get("/auth/me")
    }

    // MARK: Projects

    func projects() async throws -> [Project] {
        try await get("/projects")
    }

    func createProject(_ draft: ProjectDraft) async throws -> Project {
        try await post("/projects", body: draft)
    }

    func updateProject(id: Int64, patch: ProjectPatch) async throws -> Project {
        try await patchRequest("/projects/\(id)", body: patch)
    }

    func deleteProject(id: Int64) async throws {
        let _: OKResponse = try await delete("/projects/\(id)")
    }

    // MARK: Tasks

    func tasks(projectID: Int64? = nil, completed: Bool? = nil) async throws -> [TodoTask] {
        var query: [URLQueryItem] = []
        if let projectID { query.append(.init(name: "project_id", value: String(projectID))) }
        if let completed { query.append(.init(name: "completed", value: String(completed))) }
        return try await get("/tasks", query: query)
    }

    func createTask(_ draft: TaskDraft) async throws -> TodoTask {
        try await post("/tasks", body: draft)
    }

    func taskDetail(id: Int64) async throws -> TaskDetail {
        try await get("/tasks/\(id)")
    }

    func updateTask(id: Int64, patch: TaskPatch) async throws -> TodoTask {
        try await patchRequest("/tasks/\(id)", body: patch)
    }

    func deleteTask(id: Int64) async throws {
        let _: OKResponse = try await delete("/tasks/\(id)")
    }

    // MARK: Comments

    func addComment(taskID: Int64, body: String) async throws -> Comment {
        struct Body: Codable { var body: String }
        return try await post("/tasks/\(taskID)/comments", body: Body(body: body))
    }

    func deleteComment(id: Int64) async throws {
        let _: OKResponse = try await delete("/comments/\(id)")
    }

    // MARK: Calendar feed

    func calendarFeedURL() async throws -> URL? {
        struct FeedResponse: Codable { var url: String }
        let feed: FeedResponse = try await get("/me/calendar")
        return URL(string: feed.url, relativeTo: baseURL)?.absoluteURL
    }

    // MARK: Core request machinery

    func apiURL(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = components.path.trimmingSuffix("/") + "/api" + path
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await run(request(path, method: "GET", query: query))
    }

    private func post<T: Decodable>(_ path: String) async throws -> T {
        try await run(request(path, method: "POST"))
    }

    private func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try await run(request(path, method: "POST", body: body))
    }

    private func patchRequest<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try await run(request(path, method: "PATCH", body: body))
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        try await run(request(path, method: "DELETE"))
    }

    private func request(_ path: String, method: String, query: [URLQueryItem] = []) -> URLRequest {
        var req = URLRequest(url: apiURL(path, query: query))
        req.httpMethod = method
        req.timeoutInterval = 15
        return req
    }

    private func request(_ path: String, method: String, body: some Encodable) -> URLRequest {
        var req = request(path, method: method)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(body)
        return req
    }

    private func run<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
                ?? "Server error (\(http.statusCode))"
            throw APIError.server(status: http.statusCode, message: message)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
