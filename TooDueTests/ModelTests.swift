import Foundation
import Testing
@testable import TooDue

@Suite("Wire format")
struct ModelTests {
    // Shapes copied from the server's actual JSON responses.
    static let taskJSON = """
    {
      "id": 42,
      "project_id": 3,
      "parent_id": null,
      "creator_id": 1,
      "name": "Buy milk",
      "description": "2%",
      "due_date": "2026-07-04",
      "due_time": "14:30",
      "deadline": "2026-07-10",
      "priority": 2,
      "completed_at": null,
      "sort_order": 5,
      "created_at": "2026-07-01T10:00:00.000Z",
      "updated_at": "2026-07-02T11:30:00.000Z",
      "comment_count": 2,
      "attachment_count": 0,
      "subtask_count": 3,
      "subtask_done_count": 1
    }
    """

    static let projectJSON = """
    {
      "id": 3,
      "name": "Groceries",
      "color": "emerald",
      "parent_id": 2,
      "owner_id": 1,
      "is_inbox": 0,
      "sort_order": 10,
      "created_at": "2026-06-01T09:00:00.000Z",
      "active_count": 4,
      "members": [
        {"id": 1, "name": "Dustin", "email": "d@example.com", "role": "owner", "project_id": 3}
      ]
    }
    """

    @Test func decodesTask() throws {
        let task = try JSONDecoder().decode(TodoTask.self, from: Data(Self.taskJSON.utf8))
        #expect(task.id == 42)
        #expect(task.projectID == 3)
        #expect(task.parentID == nil)
        #expect(task.dueDate == "2026-07-04")
        #expect(task.dueTime == "14:30")
        #expect(task.deadline == "2026-07-10")
        #expect(task.priority == 2)
        #expect(!task.isCompleted)
        #expect(task.subtaskCount == 3)
        #expect(task.subtaskDoneCount == 1)
    }

    @Test func decodesProject() throws {
        let project = try JSONDecoder().decode(Project.self, from: Data(Self.projectJSON.utf8))
        #expect(project.id == 3)
        #expect(project.color == "emerald")
        #expect(project.parentID == 2)
        #expect(!project.inbox)
        #expect(project.members?.count == 1)
        #expect(project.members?.first?.role == "owner")
    }

    @Test func taskDraftEncodesSnakeCase() throws {
        let draft = TaskDraft(projectID: 7, parentID: nil, name: "X", description: "",
                              dueDate: "2026-07-05", dueTime: "09:00", deadline: nil, priority: 1)
        let obj = try encodeToDictionary(draft)
        #expect(obj["project_id"] as? Int64 == 7)
        #expect(obj["due_date"] as? String == "2026-07-05")
        #expect(obj["due_time"] as? String == "09:00")
        #expect(obj["priority"] as? Int64 == 1)
        #expect(obj["deadline"] == nil)
    }

    @Test func patchOmitsKeepEncodesClearAsNull() throws {
        var patch = TaskPatch()
        patch.name = "Renamed"
        patch.dueDate = .clear
        patch.deadline = .set("2026-08-01")
        // dueTime stays .keep and must be absent entirely
        let obj = try encodeToDictionary(patch)
        #expect(obj["name"] as? String == "Renamed")
        #expect(obj.keys.contains("due_date"))
        #expect(obj["due_date"] is NSNull)
        #expect(obj["deadline"] as? String == "2026-08-01")
        #expect(!obj.keys.contains("due_time"))
        #expect(!obj.keys.contains("priority"))
    }

    @Test func projectPatchClearParent() throws {
        var patch = ProjectPatch()
        patch.parentID = .clear
        let obj = try encodeToDictionary(patch)
        #expect(obj.keys.contains("parent_id"))
        #expect(obj["parent_id"] is NSNull)
    }

    @Test func placeholderProjectDefaultsToSky() {
        let project = SyncLogic.placeholderProject(
            tempID: -1,
            draft: ProjectDraft(name: "New Project", color: nil, parentID: nil),
            owner: nil
        )
        #expect(project.color == "sky")
    }

    @Test func mutationQueueRoundTripsThroughJSON() throws {
        var patch = TaskPatch()
        patch.completed = true
        patch.dueDate = .clear
        let queue: [Mutation] = [
            .createTask(tempID: -1, draft: TaskDraft(projectID: 1, parentID: nil, name: "A",
                                                     description: "", priority: 4)),
            .updateTask(id: -1, patch: patch),
            .deleteProject(id: 9),
            .addComment(taskID: 42, body: "hello"),
        ]
        let data = try JSONEncoder().encode(queue)
        let decoded = try JSONDecoder().decode([Mutation].self, from: data)
        #expect(decoded == queue)
    }

    @Test func sseParsing() {
        let event = SSEClient.parse(#"{"type":"task.remove","data":{"id":5}}"#)
        #expect(event?.type == "task.remove")
        #expect(event?.decode(IDPayload.self)?.id == 5)
        #expect(SSEClient.parse("ping") == nil)
        #expect(SSEClient.parse("") == nil)
    }

    private func encodeToDictionary(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
