import Foundation
import Network
import Observation

/// Central app state: server config, auth, cached data, the offline mutation
/// queue, connectivity, and the SSE stream. Views read this observably and
/// call its mutation methods; every write is optimistic-local-first.
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case loading
        case needsAuth
        case ready
    }

    // MARK: Observable state

    private(set) var phase: Phase = .loading
    private(set) var user: User?
    private(set) var projects: [Project] = []
    private(set) var tasks: [TodoTask] = []
    private(set) var queue: [Mutation] = []
    private(set) var isOnline = true
    private(set) var isSyncing = false
    var syncError: String?

    /// The active server — the hosted service unless a self-hosted override is stored.
    var serverURLString: String {
        UserDefaults.standard.string(forKey: Self.serverURLKey) ?? ServerConfig.defaultURLString
    }

    var isCustomServer: Bool {
        UserDefaults.standard.string(forKey: Self.serverURLKey) != nil
    }

    var pendingCount: Int { queue.count }

    // MARK: Internals

    private static let serverURLKey = "toodue-server-url"

    private let store: LocalStore
    private(set) var api: APIClient?
    private var nextTempID: Int64 = -1
    private var isFlushing = false
    private var sseTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?

    init(store: LocalStore = LocalStore()) {
        self.store = store
        let snapshot = store.load()
        user = snapshot.user
        projects = snapshot.projects
        tasks = snapshot.tasks
        queue = snapshot.queue
        nextTempID = snapshot.nextTempID

        let url = Self.storedServerURL() ?? URL(string: ServerConfig.defaultURLString)!
        api = APIClient(baseURL: url)
        phase = user != nil ? .ready : .needsAuth
        startPathMonitor()
        if phase == .ready {
            Task { await self.resync() }
        }
    }

    private static func storedServerURL() -> URL? {
        guard let s = UserDefaults.standard.string(forKey: serverURLKey) else { return nil }
        return URL(string: s)
    }

    // MARK: Server selection

    /// Validate, normalize, and store the server URL. Entering the official
    /// server removes the self-hosted override. Switching servers while
    /// signed in discards the (server-specific) session, cache, and queue.
    func setServer(_ raw: String) throws {
        let url = try ServerConfig.normalize(raw)
        guard url.absoluteString != serverURLString else { return }
        if url.absoluteString == ServerConfig.defaultURLString {
            UserDefaults.standard.removeObject(forKey: Self.serverURLKey)
        } else {
            UserDefaults.standard.set(url.absoluteString, forKey: Self.serverURLKey)
        }
        disconnectSSE()
        api = APIClient(baseURL: url)
        if phase == .ready {
            user = nil
            projects = []
            tasks = []
            queue = []
            store.wipe()
            phase = .needsAuth
        }
    }

    // MARK: Auth

    func login(email: String, password: String) async throws {
        guard let api else { throw APIError.network("No server configured") }
        user = try await api.login(email: email, password: password)
        persist()
        phase = .ready
        await resync()
    }

    func register(name: String, email: String, password: String) async throws {
        guard let api else { throw APIError.network("No server configured") }
        user = try await api.register(name: name, email: email, password: password)
        persist()
        phase = .ready
        await resync()
    }

    func logout() async {
        disconnectSSE()
        if let api {
            try? await api.logout()
            // Drop the session cookie so the next user starts clean.
            let storage = HTTPCookieStorage.shared
            for cookie in storage.cookies(for: api.baseURL) ?? [] {
                storage.deleteCookie(cookie)
            }
        }
        user = nil
        projects = []
        tasks = []
        queue = []
        store.wipe()
        phase = .needsAuth
    }

    private func handleUnauthorized() {
        guard phase == .ready else { return }
        disconnectSSE()
        user = nil
        phase = .needsAuth
    }

    // MARK: Refresh & sync

    /// Full sync: replay the offline queue, then refetch, then (re)connect SSE.
    func resync() async {
        await flushQueue()
        await refreshAll()
        connectSSE()
    }

    /// Refetch everything from the server and overlay unsynced local changes.
    func refreshAll() async {
        guard let api, phase == .ready else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            async let projectsReq = api.projects()
            async let tasksReq = api.tasks()
            let (serverProjects, serverTasks) = try await (projectsReq, tasksReq)
            let merged = SyncLogic.overlay(
                queue: queue,
                onTasks: serverTasks,
                projects: serverProjects,
                creatorID: user?.id ?? 0
            )
            tasks = merged.tasks
            projects = merged.projects
            isOnline = true
            syncError = nil
            persist()
        } catch let error as APIError where error.isUnauthorized {
            handleUnauthorized()
        } catch let error as APIError {
            if case .network = error { isOnline = false }
        } catch {
            // keep cached state
        }
    }

    /// Replay queued mutations in order. Stops on network failure (stays
    /// queued); drops mutations the server permanently rejects.
    func flushQueue() async {
        guard let api, phase == .ready, !isFlushing, !queue.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        while !queue.isEmpty {
            let mutation = queue[0]
            do {
                try await perform(mutation, api: api)
                if !queue.isEmpty { queue.removeFirst() }
                persist()
            } catch let error as APIError where error.isUnauthorized {
                handleUnauthorized()
                return
            } catch let error as APIError where error.isPermanentRejection {
                syncError = error.localizedDescription
                if !queue.isEmpty { queue.removeFirst() }
                persist()
            } catch {
                isOnline = false
                return
            }
        }
        isOnline = true
    }

    private func perform(_ mutation: Mutation, api: APIClient) async throws {
        switch mutation {
        case .createTask(let tempID, let draft):
            let created = try await api.createTask(draft)
            remapTask(from: tempID, to: created.id)
            if let i = tasks.firstIndex(where: { $0.id == created.id }) {
                tasks[i] = created
            }
        case .updateTask(let id, let patch):
            guard id > 0 else { return } // create was dropped/rejected earlier
            let updated = try await api.updateTask(id: id, patch: patch)
            upsertTask(updated)
        case .deleteTask(let id):
            guard id > 0 else { return }
            try await api.deleteTask(id: id)
        case .createProject(let tempID, let draft):
            let created = try await api.createProject(draft)
            remapProject(from: tempID, to: created.id)
            if let i = projects.firstIndex(where: { $0.id == created.id }) {
                projects[i] = created
            }
        case .updateProject(let id, let patch):
            guard id > 0 else { return }
            let updated = try await api.updateProject(id: id, patch: patch)
            upsertProject(updated)
        case .deleteProject(let id):
            guard id > 0 else { return }
            try await api.deleteProject(id: id)
        case .addComment(let taskID, let body):
            guard taskID > 0 else { return }
            _ = try await api.addComment(taskID: taskID, body: body)
        }
    }

    private func remapTask(from tempID: Int64, to realID: Int64) {
        queue = queue.map { $0.remappingTask(from: tempID, to: realID) }
        for i in tasks.indices where tasks[i].id == tempID { tasks[i].id = realID }
        for i in tasks.indices where tasks[i].parentID == tempID { tasks[i].parentID = realID }
    }

    private func remapProject(from tempID: Int64, to realID: Int64) {
        queue = queue.map { $0.remappingProject(from: tempID, to: realID) }
        for i in projects.indices where projects[i].id == tempID { projects[i].id = realID }
        for i in projects.indices where projects[i].parentID == tempID { projects[i].parentID = realID }
        for i in tasks.indices where tasks[i].projectID == tempID { tasks[i].projectID = realID }
    }

    // MARK: Mutations (optimistic)

    private func enqueue(_ mutation: Mutation) {
        queue = MutationQueueLogic.appending(mutation, to: queue)
        persist()
        Task { await self.flushQueue() }
    }

    private func takeTempID() -> Int64 {
        defer { nextTempID -= 1 }
        return nextTempID
    }

    @discardableResult
    func addTask(_ draft: TaskDraft) -> TodoTask {
        let tempID = takeTempID()
        var draft = draft
        if draft.projectID == nil && draft.parentID == nil {
            draft.projectID = inboxProject?.id
        }
        if let parentID = draft.parentID,
           let parent = tasks.first(where: { $0.id == parentID }) {
            draft.projectID = parent.projectID
        }
        let task = SyncLogic.placeholderTask(tempID: tempID, draft: draft, creatorID: user?.id ?? 0)
        tasks.append(task)
        if let parentID = task.parentID, let i = tasks.firstIndex(where: { $0.id == parentID }) {
            tasks[i].subtaskCount = (tasks[i].subtaskCount ?? 0) + 1
        }
        enqueue(.createTask(tempID: tempID, draft: draft))
        return task
    }

    func updateTask(id: Int64, patch: TaskPatch) {
        guard !patch.isEmpty else { return }
        if let i = tasks.firstIndex(where: { $0.id == id }) {
            tasks[i] = tasks[i].applying(patch)
        }
        enqueue(.updateTask(id: id, patch: patch))
    }

    func setCompleted(_ task: TodoTask, _ completed: Bool) {
        var patch = TaskPatch()
        patch.completed = completed
        updateTask(id: task.id, patch: patch)
    }

    func deleteTask(id: Int64) {
        tasks.removeAll { $0.id == id || $0.parentID == id }
        enqueue(.deleteTask(id: id))
    }

    @discardableResult
    func addProject(name: String, color: String?, parentID: Int64?) -> Project {
        let tempID = takeTempID()
        let draft = ProjectDraft(name: name, color: color, parentID: parentID)
        let project = SyncLogic.placeholderProject(tempID: tempID, draft: draft, owner: user)
        projects.append(project)
        enqueue(.createProject(tempID: tempID, draft: draft))
        return project
    }

    func updateProject(id: Int64, patch: ProjectPatch) {
        if let i = projects.firstIndex(where: { $0.id == id }) {
            projects[i] = projects[i].applying(patch)
        }
        enqueue(.updateProject(id: id, patch: patch))
    }

    func deleteProject(id: Int64) {
        projects.removeAll { $0.id == id }
        tasks.removeAll { $0.projectID == id }
        enqueue(.deleteProject(id: id))
    }

    func addComment(taskID: Int64, body: String) {
        if let i = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[i].commentCount = (tasks[i].commentCount ?? 0) + 1
        }
        enqueue(.addComment(taskID: taskID, body: body))
    }

    // MARK: Upserts (SSE + replay results)

    private func upsertTask(_ task: TodoTask) {
        // A pending local edit outranks what the server just told us.
        var incoming = task
        for mutation in queue {
            if case .updateTask(let id, let patch) = mutation, id == task.id {
                incoming = incoming.applying(patch)
            }
        }
        if incoming.isCompleted {
            tasks.removeAll { $0.id == incoming.id }
        } else if let i = tasks.firstIndex(where: { $0.id == incoming.id }) {
            tasks[i] = incoming
        } else {
            tasks.append(incoming)
        }
    }

    private func upsertProject(_ project: Project) {
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects[i] = project
        } else {
            projects.append(project)
        }
    }

    // MARK: SSE

    func connectSSE() {
        guard let api, phase == .ready, sseTask == nil else { return }
        let client = SSEClient(url: api.apiURL("/events"))
        sseTask = Task { [weak self] in
            var delay: Duration = .seconds(1)
            while !Task.isCancelled {
                do {
                    for try await event in client.events() {
                        delay = .seconds(1)
                        self?.handle(event)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    // fall through to backoff
                }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, .seconds(30))
            }
        }
    }

    func disconnectSSE() {
        sseTask?.cancel()
        sseTask = nil
    }

    private func handle(_ event: ServerEvent) {
        switch event.type {
        case "task.upsert":
            if let task = event.decode(TodoTask.self) { upsertTask(task) }
        case "task.remove":
            if let p = event.decode(IDPayload.self) {
                tasks.removeAll { $0.id == p.id || $0.parentID == p.id }
            }
        case "tasks.refresh", "projects.refresh":
            Task { await self.refreshAll() }
        case "project.upsert":
            if let project = event.decode(Project.self) { upsertProject(project) }
        case "project.remove":
            if let p = event.decode(IDPayload.self) {
                projects.removeAll { $0.id == p.id }
                tasks.removeAll { $0.projectID == p.id }
            }
        case "comment.new", "comment.remove", "attachment.new", "attachment.remove":
            if let p = event.decode(IDPayload.self), let taskID = p.taskID {
                Task {
                    if let detail = try? await self.api?.taskDetail(id: taskID) {
                        self.upsertTask(detail.task)
                    }
                }
            }
        default:
            break
        }
        persist()
    }

    // MARK: Connectivity

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOnline = self.isOnline
                self.isOnline = online
                if online && !wasOnline && self.phase == .ready {
                    self.disconnectSSE()
                    await self.resync()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "toodue.pathmonitor"))
    }

    // MARK: Persistence

    private func persist() {
        store.save(Snapshot(
            user: user,
            projects: projects,
            tasks: tasks,
            queue: queue,
            nextTempID: nextTempID
        ))
    }

    // MARK: View helpers

    var inboxProject: Project? {
        projects.first { $0.inbox }
    }

    func project(_ id: Int64) -> Project? {
        projects.first { $0.id == id }
    }

    /// Active top-level tasks in a project, in server order.
    func activeTasks(inProject projectID: Int64) -> [TodoTask] {
        tasks.filter { $0.projectID == projectID && !$0.isCompleted && $0.parentID == nil }
            .sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) }
    }

    func subtasks(of taskID: Int64) -> [TodoTask] {
        tasks.filter { $0.parentID == taskID }
            .sorted { ($0.isCompleted ? 1 : 0, $0.sortOrder, $0.id) < ($1.isCompleted ? 1 : 0, $1.sortOrder, $1.id) }
    }

    var inboxCount: Int {
        guard let inbox = inboxProject else { return 0 }
        return activeTasks(inProject: inbox.id).count
    }

    var todayTasks: [TodoTask] {
        tasks.filter { task in
            guard !task.isCompleted, let due = task.dueDate else { return false }
            return DateUtil.isToday(due) || DateUtil.isOverdue(due)
        }
        .sorted { taskDaySortKey($0) < taskDaySortKey($1) }
    }

    var upcomingByDay: [(day: String, tasks: [TodoTask])] {
        let future = tasks.filter { task in
            guard !task.isCompleted, let due = task.dueDate else { return false }
            return !DateUtil.isToday(due) && !DateUtil.isOverdue(due)
        }
        let grouped = Dictionary(grouping: future) { $0.dueDate ?? "" }
        return grouped.keys.sorted().map { day in
            (day, grouped[day]!.sorted { taskDaySortKey($0) < taskDaySortKey($1) })
        }
    }

    private func taskDaySortKey(_ t: TodoTask) -> (String, String, Int64, Int64) {
        (t.dueDate ?? "9999-99-99", t.dueTime ?? "99:99", t.priority, t.id)
    }
}
