import Foundation

extension TodoTask {
    /// Optimistically apply a patch the way the server would.
    func applying(_ patch: TaskPatch, now: Date = Date()) -> TodoTask {
        var t = self
        if let v = patch.name { t.name = v }
        if let v = patch.description { t.description = v }
        t.dueDate = patch.dueDate.applied(over: t.dueDate)
        t.dueTime = patch.dueTime.applied(over: t.dueTime)
        if t.dueDate == nil { t.dueTime = nil } // server clears time with date
        t.deadline = patch.deadline.applied(over: t.deadline)
        if let v = patch.priority { t.priority = min(4, max(1, v)) }
        if let v = patch.completed {
            t.completedAt = v ? ISO8601DateFormatter().string(from: now) : nil
        }
        if let v = patch.projectID { t.projectID = v }
        return t
    }
}

extension Project {
    func applying(_ patch: ProjectPatch) -> Project {
        var p = self
        if let v = patch.name { p.name = v }
        if let v = patch.color { p.color = v }
        p.parentID = patch.parentID.applied(over: p.parentID)
        return p
    }
}

/// Pure state transforms shared by optimistic updates and post-refresh
/// reconciliation. No I/O — fully unit-testable.
enum SyncLogic {
    /// Build the local placeholder for a task created offline.
    static func placeholderTask(tempID: Int64, draft: TaskDraft, creatorID: Int64, now: Date = Date()) -> TodoTask {
        let ts = ISO8601DateFormatter().string(from: now)
        return TodoTask(
            id: tempID,
            projectID: draft.projectID ?? 0,
            parentID: draft.parentID,
            creatorID: creatorID,
            name: draft.name,
            description: draft.description,
            dueDate: draft.dueDate,
            dueTime: draft.dueTime,
            deadline: draft.deadline,
            priority: min(4, max(1, draft.priority)),
            completedAt: nil,
            sortOrder: Int64.max, // sorts last, like the server would append
            createdAt: ts,
            updatedAt: ts,
            commentCount: 0,
            attachmentCount: 0,
            subtaskCount: 0,
            subtaskDoneCount: 0
        )
    }

    static func placeholderProject(tempID: Int64, draft: ProjectDraft, owner: User?, now: Date = Date()) -> Project {
        Project(
            id: tempID,
            name: draft.name,
            color: draft.color ?? "sky",
            parentID: draft.parentID,
            ownerID: owner?.id ?? 0,
            isInbox: 0,
            sortOrder: Int64.max,
            createdAt: ISO8601DateFormatter().string(from: now),
            activeCount: 0,
            members: owner.map { [Member(id: $0.id, name: $0.name, email: $0.email, role: "owner", projectID: tempID)] }
        )
    }

    /// Re-derive local state after fetching fresh server data: server truth,
    /// with every still-pending mutation replayed on top so unsynced work
    /// doesn't vanish from the UI.
    static func overlay(
        queue: [Mutation],
        onTasks serverTasks: [TodoTask],
        projects serverProjects: [Project],
        creatorID: Int64
    ) -> (tasks: [TodoTask], projects: [Project]) {
        var tasks = serverTasks
        var projects = serverProjects
        for mutation in queue {
            switch mutation {
            case .createTask(let tempID, let draft):
                tasks.append(placeholderTask(tempID: tempID, draft: draft, creatorID: creatorID))
            case .updateTask(let id, let patch):
                if let i = tasks.firstIndex(where: { $0.id == id }) {
                    tasks[i] = tasks[i].applying(patch)
                    if patch.completed == true {
                        tasks.remove(at: i) // active lists don't show completed
                    }
                }
            case .deleteTask(let id):
                tasks.removeAll { $0.id == id || $0.parentID == id }
            case .createProject(let tempID, let draft):
                projects.append(placeholderProject(tempID: tempID, draft: draft, owner: nil))
            case .updateProject(let id, let patch):
                if let i = projects.firstIndex(where: { $0.id == id }) {
                    projects[i] = projects[i].applying(patch)
                }
            case .deleteProject(let id):
                projects.removeAll { $0.id == id }
                tasks.removeAll { task in
                    task.projectID == id
                }
            case .addComment:
                break
            }
        }
        return (tasks, projects)
    }

    /// Flatten the project tree depth-first (inbox first, then sort_order),
    /// returning each project with its nesting depth for indented display.
    static func flattenedProjects(_ projects: [Project]) -> [(project: Project, depth: Int)] {
        let sorted = projects.sorted { sortKey($0) < sortKey($1) }
        let valid = Set(sorted.map(\.id))
        var children: [Int64?: [Project]] = [:]
        for p in sorted {
            // Treat orphans (parent not visible to us) as roots.
            let parent = p.parentID.flatMap { valid.contains($0) ? $0 : nil }
            children[parent, default: []].append(p)
        }
        var out: [(Project, Int)] = []
        func walk(_ parent: Int64?, depth: Int) {
            for p in children[parent] ?? [] {
                out.append((p, depth))
                walk(p.id, depth: depth + 1)
            }
        }
        walk(nil, depth: 0)
        return out
    }

    private static func sortKey(_ p: Project) -> (Int64, Int64, Int64) {
        (-p.isInbox, p.sortOrder, p.id)
    }
}
