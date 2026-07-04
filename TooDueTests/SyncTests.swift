import Foundation
import Testing
@testable import TooDue

private func makeTask(id: Int64, projectID: Int64 = 1, parentID: Int64? = nil,
                      name: String = "Task", due: String? = nil) -> TodoTask {
    TodoTask(id: id, projectID: projectID, parentID: parentID, creatorID: 1,
             name: name, description: "", dueDate: due, dueTime: nil, deadline: nil,
             priority: 4, completedAt: nil, sortOrder: id,
             createdAt: "2026-07-01T00:00:00.000Z", updatedAt: "2026-07-01T00:00:00.000Z",
             commentCount: 0, attachmentCount: 0, subtaskCount: 0, subtaskDoneCount: 0)
}

private func makeProject(id: Int64, name: String = "P", parentID: Int64? = nil,
                         sortOrder: Int64 = 0, inbox: Bool = false) -> Project {
    Project(id: id, name: name, color: "slate", parentID: parentID, ownerID: 1,
            isInbox: inbox ? 1 : 0, sortOrder: sortOrder,
            createdAt: "2026-06-01T00:00:00.000Z", activeCount: 0, members: nil)
}

@Suite("Mutation queue compaction")
struct QueueLogicTests {
    @Test func consecutiveEditsMerge() {
        var first = TaskPatch(); first.name = "A"; first.priority = 2
        var second = TaskPatch(); second.priority = 1; second.dueDate = .set("2026-07-09")

        var queue = MutationQueueLogic.appending(.updateTask(id: 5, patch: first), to: [])
        queue = MutationQueueLogic.appending(.updateTask(id: 5, patch: second), to: queue)

        #expect(queue.count == 1)
        guard case .updateTask(let id, let merged) = queue[0] else {
            Issue.record("expected updateTask"); return
        }
        #expect(id == 5)
        #expect(merged.name == "A")           // preserved from first
        #expect(merged.priority == 1)         // newer wins
        #expect(merged.dueDate == .set("2026-07-09"))
    }

    @Test func editsToDifferentTasksDontMerge() {
        var patch = TaskPatch(); patch.name = "X"
        var queue = MutationQueueLogic.appending(.updateTask(id: 5, patch: patch), to: [])
        queue = MutationQueueLogic.appending(.updateTask(id: 6, patch: patch), to: queue)
        #expect(queue.count == 2)
    }

    @Test func deletingUnsyncedTaskCancelsItsQueue() {
        let draft = TaskDraft(projectID: 1, parentID: nil, name: "New", description: "", priority: 4)
        var patch = TaskPatch(); patch.name = "Renamed"

        var queue = MutationQueueLogic.appending(.createTask(tempID: -3, draft: draft), to: [])
        queue = MutationQueueLogic.appending(.updateTask(id: -3, patch: patch), to: queue)
        queue = MutationQueueLogic.appending(.deleteTask(id: -3), to: queue)

        #expect(queue.isEmpty) // server never needs to hear about it
    }

    @Test func deletingSyncedTaskStaysQueued() {
        let queue = MutationQueueLogic.appending(.deleteTask(id: 42), to: [])
        #expect(queue == [.deleteTask(id: 42)])
    }

    @Test func deletingUnsyncedProjectCancelsProjectAndItsDraftTasks() {
        let projectDraft = ProjectDraft(name: "Temp", color: nil, parentID: nil)
        let taskDraft = TaskDraft(projectID: -8, parentID: nil, name: "In temp", description: "", priority: 4)

        var queue = MutationQueueLogic.appending(.createProject(tempID: -8, draft: projectDraft), to: [])
        queue = MutationQueueLogic.appending(.createTask(tempID: -9, draft: taskDraft), to: queue)
        queue = MutationQueueLogic.appending(.deleteProject(id: -8), to: queue)

        #expect(queue.isEmpty)
    }

    @Test func remapTaskRewritesReferences() {
        var patch = TaskPatch(); patch.completed = true
        let mutations: [Mutation] = [
            .updateTask(id: -2, patch: patch),
            .addComment(taskID: -2, body: "hi"),
            .createTask(tempID: -5, draft: TaskDraft(projectID: 1, parentID: -2, name: "sub",
                                                     description: "", priority: 4)),
        ]
        let remapped = mutations.map { $0.remappingTask(from: -2, to: 100) }
        #expect(remapped[0] == .updateTask(id: 100, patch: patch))
        #expect(remapped[1] == .addComment(taskID: 100, body: "hi"))
        guard case .createTask(_, let draft) = remapped[2] else {
            Issue.record("expected createTask"); return
        }
        #expect(draft.parentID == 100)
    }

    @Test func remapProjectRewritesReferences() {
        let mutations: [Mutation] = [
            .createTask(tempID: -5, draft: TaskDraft(projectID: -7, parentID: nil, name: "t",
                                                     description: "", priority: 4)),
            .updateProject(id: -7, patch: ProjectPatch()),
            .deleteProject(id: -7),
        ]
        let remapped = mutations.map { $0.remappingProject(from: -7, to: 55) }
        guard case .createTask(_, let draft) = remapped[0] else {
            Issue.record("expected createTask"); return
        }
        #expect(draft.projectID == 55)
        #expect(remapped[1] == .updateProject(id: 55, patch: ProjectPatch()))
        #expect(remapped[2] == .deleteProject(id: 55))
    }
}

@Suite("Offline overlay")
struct OverlayTests {
    @Test func pendingCreateSurvivesRefresh() {
        let serverTasks = [makeTask(id: 1), makeTask(id: 2)]
        let draft = TaskDraft(projectID: 1, parentID: nil, name: "Offline add", description: "", priority: 2)
        let queue: [Mutation] = [.createTask(tempID: -1, draft: draft)]

        let (tasks, _) = SyncLogic.overlay(queue: queue, onTasks: serverTasks,
                                           projects: [makeProject(id: 1)], creatorID: 1)
        #expect(tasks.count == 3)
        let added = tasks.first { $0.id == -1 }
        #expect(added?.name == "Offline add")
        #expect(added?.priority == 2)
    }

    @Test func pendingEditWinsOverServerState() {
        var patch = TaskPatch(); patch.name = "Local rename"; patch.dueDate = .clear
        let queue: [Mutation] = [.updateTask(id: 1, patch: patch)]
        let (tasks, _) = SyncLogic.overlay(queue: queue,
                                           onTasks: [makeTask(id: 1, name: "Server name", due: "2026-07-04")],
                                           projects: [], creatorID: 1)
        #expect(tasks[0].name == "Local rename")
        #expect(tasks[0].dueDate == nil)
    }

    @Test func pendingDeleteHidesServerTask() {
        let queue: [Mutation] = [.deleteTask(id: 2)]
        let (tasks, _) = SyncLogic.overlay(queue: queue,
                                           onTasks: [makeTask(id: 1), makeTask(id: 2),
                                                     makeTask(id: 3, parentID: 2)],
                                           projects: [], creatorID: 1)
        #expect(tasks.map(\.id) == [1]) // subtask 3 goes with its parent
    }

    @Test func pendingCompleteRemovesFromActiveList() {
        var patch = TaskPatch(); patch.completed = true
        let queue: [Mutation] = [.updateTask(id: 1, patch: patch)]
        let (tasks, _) = SyncLogic.overlay(queue: queue, onTasks: [makeTask(id: 1)],
                                           projects: [], creatorID: 1)
        #expect(tasks.isEmpty)
    }

    @Test func clearingDueDateClearsTime() {
        var task = makeTask(id: 1, due: "2026-07-04")
        task.dueTime = "10:00"
        var patch = TaskPatch(); patch.dueDate = .clear
        let updated = task.applying(patch)
        #expect(updated.dueDate == nil)
        #expect(updated.dueTime == nil)
    }
}

@Suite("Project tree")
struct ProjectTreeTests {
    @Test func flattensDepthFirstWithInboxFirst() {
        let projects = [
            makeProject(id: 10, name: "Work", sortOrder: 1),
            makeProject(id: 1, name: "Inbox", sortOrder: 99, inbox: true),
            makeProject(id: 11, name: "Work/Sub", parentID: 10, sortOrder: 0),
            makeProject(id: 12, name: "Home", sortOrder: 2),
        ]
        let flat = SyncLogic.flattenedProjects(projects)
        #expect(flat.map(\.project.name) == ["Inbox", "Work", "Work/Sub", "Home"])
        #expect(flat.map(\.depth) == [0, 0, 1, 0])
    }

    @Test func orphanedChildBecomesRoot() {
        let projects = [makeProject(id: 5, name: "Orphan", parentID: 999)]
        let flat = SyncLogic.flattenedProjects(projects)
        #expect(flat.count == 1)
        #expect(flat[0].depth == 0)
    }
}

@Suite("Date labels")
struct DateUtilTests {
    private let reference = DateUtil.parseDay("2026-07-04")!

    @Test func relativeLabels() {
        #expect(DateUtil.relativeLabel(for: "2026-07-04", reference: reference) == "Today")
        #expect(DateUtil.relativeLabel(for: "2026-07-05", reference: reference) == "Tomorrow")
        // 2026-07-06 is a Monday, within the next week → weekday name
        #expect(DateUtil.relativeLabel(for: "2026-07-06", reference: reference) == "Monday")
        // Beyond a week → abbreviated date, no year when same year
        #expect(DateUtil.relativeLabel(for: "2026-07-20", reference: reference).contains("20"))
        #expect(!DateUtil.relativeLabel(for: "2026-07-20", reference: reference).contains("2026"))
        #expect(DateUtil.relativeLabel(for: "2027-01-05", reference: reference).contains("2027"))
    }

    @Test func overdueAndToday() {
        #expect(DateUtil.isOverdue("2026-07-03", reference: reference))
        #expect(!DateUtil.isOverdue("2026-07-04", reference: reference))
        #expect(DateUtil.isToday("2026-07-04", reference: reference))
        #expect(!DateUtil.isToday("2026-07-05", reference: reference))
    }

    @Test func dayStringRoundTrip() {
        let date = DateUtil.parseDay("2026-12-25")
        #expect(date != nil)
        #expect(DateUtil.dayString(date!) == "2026-12-25")
    }
}
