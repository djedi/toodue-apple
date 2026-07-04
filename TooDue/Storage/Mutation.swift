import Foundation

/// A write the user made that must eventually reach the server. Queued while
/// offline (or after a network failure) and replayed in order once online.
///
/// Offline-created tasks/projects get negative temporary ids; when the create
/// replays and the server assigns a real id, every later mutation in the queue
/// that references the temp id is rewritten via `remapping…`.
enum Mutation: Codable, Equatable, Sendable {
    case createTask(tempID: Int64, draft: TaskDraft)
    case updateTask(id: Int64, patch: TaskPatch)
    case deleteTask(id: Int64)
    case createProject(tempID: Int64, draft: ProjectDraft)
    case updateProject(id: Int64, patch: ProjectPatch)
    case deleteProject(id: Int64)
    case addComment(taskID: Int64, body: String)

    /// Human label for the settings screen's pending-changes list.
    var summary: String {
        switch self {
        case .createTask(_, let draft): "Add task “\(draft.name)”"
        case .updateTask(let id, _): "Edit task #\(id)"
        case .deleteTask(let id): "Delete task #\(id)"
        case .createProject(_, let draft): "Add project “\(draft.name)”"
        case .updateProject(let id, _): "Edit project #\(id)"
        case .deleteProject(let id): "Delete project #\(id)"
        case .addComment: "Add comment"
        }
    }

    func remappingTask(from tempID: Int64, to realID: Int64) -> Mutation {
        func fix(_ id: Int64) -> Int64 { id == tempID ? realID : id }
        switch self {
        case .createTask(let t, var draft):
            if let p = draft.parentID { draft.parentID = fix(p) }
            return .createTask(tempID: t, draft: draft)
        case .updateTask(let id, let patch):
            return .updateTask(id: fix(id), patch: patch)
        case .deleteTask(let id):
            return .deleteTask(id: fix(id))
        case .addComment(let taskID, let body):
            return .addComment(taskID: fix(taskID), body: body)
        case .createProject, .updateProject, .deleteProject:
            return self
        }
    }

    func remappingProject(from tempID: Int64, to realID: Int64) -> Mutation {
        func fix(_ id: Int64) -> Int64 { id == tempID ? realID : id }
        switch self {
        case .createTask(let t, var draft):
            if let p = draft.projectID { draft.projectID = fix(p) }
            return .createTask(tempID: t, draft: draft)
        case .updateTask(let id, var patch):
            if let p = patch.projectID { patch.projectID = fix(p) }
            return .updateTask(id: id, patch: patch)
        case .createProject(let t, var draft):
            if let p = draft.parentID { draft.parentID = fix(p) }
            return .createProject(tempID: t, draft: draft)
        case .updateProject(let id, var patch):
            if case .set(let p) = patch.parentID { patch.parentID = .set(fix(p)) }
            return .updateProject(id: fix(id), patch: patch)
        case .deleteProject(let id):
            return .deleteProject(id: fix(id))
        case .deleteTask, .addComment:
            return self
        }
    }

    /// Does this mutation reference the given (possibly temp) task id?
    func referencesTask(_ id: Int64) -> Bool {
        switch self {
        case .createTask(let tempID, let draft): tempID == id || draft.parentID == id
        case .updateTask(let taskID, _): taskID == id
        case .deleteTask(let taskID): taskID == id
        case .addComment(let taskID, _): taskID == id
        default: false
        }
    }
}

/// Pure queue-compaction helpers, kept free of I/O so they're easy to test.
enum MutationQueueLogic {
    /// Append `mutation`, collapsing where safe:
    /// - consecutive-in-effect updates to the same task merge into one patch
    /// - deleting a never-synced (temp id) item cancels its create and edits
    static func appending(_ mutation: Mutation, to queue: [Mutation]) -> [Mutation] {
        var queue = queue

        switch mutation {
        case .updateTask(let id, let patch):
            if let i = queue.lastIndex(where: {
                if case .updateTask(let existingID, _) = $0 { existingID == id } else { false }
            }), case .updateTask(_, let existing) = queue[i],
               // Only merge when nothing after i also touches this task,
               // otherwise we'd reorder effects.
               !queue[(i + 1)...].contains(where: { $0.referencesTask(id) }) {
                queue[i] = .updateTask(id: id, patch: existing.merging(patch))
                return queue
            }

        case .deleteTask(let id) where id < 0:
            // The server never saw this task; drop everything about it.
            queue.removeAll { $0.referencesTask(id) }
            return queue

        case .deleteProject(let id) where id < 0:
            queue.removeAll {
                switch $0 {
                case .createProject(let tempID, _): tempID == id
                case .updateProject(let pid, _): pid == id
                default: false
                }
            }
            // Tasks drafted into the dead project can't be created anymore.
            queue.removeAll {
                if case .createTask(_, let draft) = $0 { draft.projectID == id } else { false }
            }
            return queue

        default:
            break
        }

        queue.append(mutation)
        return queue
    }
}
