import Foundation

// MARK: - User

struct User: Codable, Equatable, Sendable {
    var id: Int64
    var email: String
    var name: String
}

// MARK: - Project

struct Project: Codable, Equatable, Identifiable, Sendable {
    var id: Int64
    var name: String
    var color: String
    var parentID: Int64?
    var ownerID: Int64
    var isInbox: Int64
    var sortOrder: Int64
    var createdAt: String
    var activeCount: Int64?
    var members: [Member]?

    var inbox: Bool { isInbox != 0 }

    enum CodingKeys: String, CodingKey {
        case id, name, color, members
        case parentID = "parent_id"
        case ownerID = "owner_id"
        case isInbox = "is_inbox"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case activeCount = "active_count"
    }
}

struct Member: Codable, Equatable, Identifiable, Sendable {
    var id: Int64
    var name: String
    var email: String
    var role: String
    var projectID: Int64

    enum CodingKeys: String, CodingKey {
        case id, name, email, role
        case projectID = "project_id"
    }
}

// MARK: - Task

/// Named TodoTask to avoid colliding with Swift Concurrency's `Task`.
struct TodoTask: Codable, Equatable, Identifiable, Sendable {
    var id: Int64
    var projectID: Int64
    var parentID: Int64?
    var creatorID: Int64
    var name: String
    var description: String
    /// YYYY-MM-DD
    var dueDate: String?
    /// HH:MM (24h), only meaningful when dueDate is set
    var dueTime: String?
    /// YYYY-MM-DD
    var deadline: String?
    /// 1 (urgent) … 4 (normal)
    var priority: Int64
    var completedAt: String?
    var sortOrder: Int64
    var createdAt: String
    var updatedAt: String
    var commentCount: Int64?
    var attachmentCount: Int64?
    var subtaskCount: Int64?
    var subtaskDoneCount: Int64?

    var isCompleted: Bool { completedAt != nil }
    /// Locally-created tasks that haven't reached the server yet use negative ids.
    var isLocalOnly: Bool { id < 0 }

    enum CodingKeys: String, CodingKey {
        case id, name, description, deadline, priority
        case projectID = "project_id"
        case parentID = "parent_id"
        case creatorID = "creator_id"
        case dueDate = "due_date"
        case dueTime = "due_time"
        case completedAt = "completed_at"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case commentCount = "comment_count"
        case attachmentCount = "attachment_count"
        case subtaskCount = "subtask_count"
        case subtaskDoneCount = "subtask_done_count"
    }
}

// MARK: - Comment

struct Comment: Codable, Equatable, Identifiable, Sendable {
    var id: Int64
    var taskID: Int64
    var userID: Int64
    var userName: String
    var body: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, body
        case taskID = "task_id"
        case userID = "user_id"
        case userName = "user_name"
        case createdAt = "created_at"
    }
}

// MARK: - Attachment

struct Attachment: Codable, Equatable, Identifiable, Sendable {
    var id: Int64
    var taskID: Int64
    var userID: Int64
    var filename: String
    var mime: String
    var size: Int64
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, filename, mime, size
        case taskID = "task_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

// MARK: - Task detail (GET /tasks/{id})

struct TaskDetail: Codable, Sendable {
    var task: TodoTask
    var subtasks: [TodoTask]
    var comments: [Comment]
    var attachments: [Attachment]
}

// MARK: - SSE events

struct ServerEvent: Sendable {
    var type: String
    var data: Data

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}

struct IDPayload: Codable, Sendable {
    var id: Int64
    var taskID: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case taskID = "task_id"
    }
}

// MARK: - Priority helpers

enum Priority: Int64, CaseIterable, Identifiable, Sendable {
    case p1 = 1, p2 = 2, p3 = 3, p4 = 4

    var id: Int64 { rawValue }

    var label: String {
        switch self {
        case .p1: "P1 · Urgent"
        case .p2: "P2 · High"
        case .p3: "P3 · Medium"
        case .p4: "P4 · Normal"
        }
    }

    var shortLabel: String { "P\(rawValue)" }
}
