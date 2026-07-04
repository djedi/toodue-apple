import Foundation

/// A PATCH field that distinguishes "leave unchanged" (omitted from JSON),
/// "clear on the server" (encoded as null), and "set to a value".
enum PatchField<T: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    case keep
    case clear
    case set(T)

    var isKeep: Bool { if case .keep = self { true } else { false } }

    /// The resulting value when applied over an existing optional.
    func applied(over current: T?) -> T? {
        switch self {
        case .keep: current
        case .clear: nil
        case .set(let v): v
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = container.decodeNil() ? .clear : .set(try container.decode(T.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .keep:
            break // callers skip .keep before encoding
        case .clear:
            try container.encodeNil()
        case .set(let v):
            try container.encode(v)
        }
    }
}

extension KeyedDecodingContainer {
    /// `decodeIfPresent` returns nil for both a JSON null (.clear) and a
    /// missing key (.keep), so patch decoding must check presence explicitly.
    func decodePatchField<T>(_: PatchField<T>.Type, forKey key: Key) throws -> PatchField<T> {
        guard contains(key) else { return .keep }
        return try decodeNil(forKey: key) ? .clear : .set(try decode(T.self, forKey: key))
    }
}

// MARK: - Task payloads

struct TaskDraft: Codable, Equatable, Sendable {
    var projectID: Int64?
    var parentID: Int64?
    var name: String
    var description: String
    var dueDate: String?
    var dueTime: String?
    var deadline: String?
    var priority: Int64

    enum CodingKeys: String, CodingKey {
        case name, description, deadline, priority
        case projectID = "project_id"
        case parentID = "parent_id"
        case dueDate = "due_date"
        case dueTime = "due_time"
    }
}

struct TaskPatch: Codable, Equatable, Sendable {
    var name: String?
    var description: String?
    var dueDate: PatchField<String> = .keep
    var dueTime: PatchField<String> = .keep
    var deadline: PatchField<String> = .keep
    var priority: Int64?
    var completed: Bool?
    var projectID: Int64?

    var isEmpty: Bool {
        name == nil && description == nil && dueDate.isKeep && dueTime.isKeep
            && deadline.isKeep && priority == nil && completed == nil && projectID == nil
    }

    enum CodingKeys: String, CodingKey {
        case name, description, deadline, priority, completed
        case dueDate = "due_date"
        case dueTime = "due_time"
        case projectID = "project_id"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        dueDate = try c.decodePatchField(PatchField<String>.self, forKey: .dueDate)
        dueTime = try c.decodePatchField(PatchField<String>.self, forKey: .dueTime)
        deadline = try c.decodePatchField(PatchField<String>.self, forKey: .deadline)
        priority = try c.decodeIfPresent(Int64.self, forKey: .priority)
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed)
        projectID = try c.decodeIfPresent(Int64.self, forKey: .projectID)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(description, forKey: .description)
        if !dueDate.isKeep { try c.encode(dueDate, forKey: .dueDate) }
        if !dueTime.isKeep { try c.encode(dueTime, forKey: .dueTime) }
        if !deadline.isKeep { try c.encode(deadline, forKey: .deadline) }
        try c.encodeIfPresent(priority, forKey: .priority)
        try c.encodeIfPresent(completed, forKey: .completed)
        try c.encodeIfPresent(projectID, forKey: .projectID)
    }

    /// Merge a newer patch into this one (newer wins per field), so repeated
    /// offline edits to the same task collapse into a single request.
    func merging(_ newer: TaskPatch) -> TaskPatch {
        var out = self
        if let v = newer.name { out.name = v }
        if let v = newer.description { out.description = v }
        if !newer.dueDate.isKeep { out.dueDate = newer.dueDate }
        if !newer.dueTime.isKeep { out.dueTime = newer.dueTime }
        if !newer.deadline.isKeep { out.deadline = newer.deadline }
        if let v = newer.priority { out.priority = v }
        if let v = newer.completed { out.completed = v }
        if let v = newer.projectID { out.projectID = v }
        return out
    }
}

// MARK: - Project payloads

struct ProjectDraft: Codable, Equatable, Sendable {
    var name: String
    var color: String?
    var parentID: Int64?

    enum CodingKeys: String, CodingKey {
        case name, color
        case parentID = "parent_id"
    }
}

struct ProjectPatch: Codable, Equatable, Sendable {
    var name: String?
    var color: String?
    var parentID: PatchField<Int64> = .keep

    enum CodingKeys: String, CodingKey {
        case name, color
        case parentID = "parent_id"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        parentID = try c.decodePatchField(PatchField<Int64>.self, forKey: .parentID)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(color, forKey: .color)
        if !parentID.isKeep { try c.encode(parentID, forKey: .parentID) }
    }
}

// MARK: - Auth payloads

struct LoginRequest: Codable, Sendable {
    var email: String
    var password: String
}

struct RegisterRequest: Codable, Sendable {
    var name: String
    var email: String
    var password: String
}

struct OKResponse: Codable, Sendable {
    var ok: Bool
}
