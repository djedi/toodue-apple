import SwiftUI

/// Full task editor. Works entirely from the local cache (offline-safe);
/// comments and attachments are fetched live when the server is reachable.
struct TaskDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppAccentPalette.storageKey) private var accent = AppAccentPalette.defaultName
    let taskID: Int64

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var dueDate: Date?
    @State private var dueTime: Date?
    @State private var deadline: Date?
    @State private var priority: Priority = .p4
    @State private var projectID: Int64?
    @State private var loaded = false

    @State private var comments: [Comment] = []
    @State private var newComment = ""
    @State private var newSubtask = ""

    private var task: TodoTask? { app.tasks.first { $0.id == taskID } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        completeButton
                        TextField("Task name", text: $name, axis: .vertical)
                            .font(.title3)
                    }
                    TextField("Description", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...6)
                        .font(.subheadline)
                }

                Section {
                    OptionalDatePicker(label: "Date", icon: "calendar", selection: $dueDate)
                    if dueDate != nil {
                        OptionalTimePicker(label: "Time", selection: $dueTime)
                    }
                    OptionalDatePicker(label: "Deadline", icon: "flag", selection: $deadline)
                    Picker(selection: $priority) {
                        ForEach(Priority.allCases) { p in Text(p.label).tag(p) }
                    } label: {
                        Label("Priority", systemImage: "flag.pattern.checkered")
                    }
                    Picker(selection: $projectID) {
                        ForEach(SyncLogic.flattenedProjects(app.projects), id: \.project.id) { entry in
                            Text(String(repeating: "  ", count: entry.depth) + entry.project.name)
                                .tag(Int64?.some(entry.project.id))
                        }
                    } label: {
                        Label("Project", systemImage: "number")
                    }
                }

                if task?.parentID == nil {
                    subtasksSection
                }

                commentsSection
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        app.deleteTask(id: taskID)
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear(perform: populate)
            .task { await loadComments() }
            .onDisappear(perform: saveChanges)
        }
    }

    private var completeButton: some View {
        Button {
            if let task {
                app.setCompleted(task, !task.isCompleted)
                dismiss()
            }
        } label: {
            Circle()
                .strokeBorder(priority.color, lineWidth: 2)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var subtasksSection: some View {
        Section("Sub-tasks") {
            ForEach(app.subtasks(of: taskID)) { sub in
                HStack(spacing: 10) {
                    Button {
                        app.setCompleted(sub, !sub.isCompleted)
                    } label: {
                        Image(systemName: sub.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(sub.isCompleted ? Color.dueToday
                                : (Priority(rawValue: sub.priority) ?? .p4).color)
                    }
                    .buttonStyle(.plain)
                    Text(sub.name)
                        .font(.subheadline)
                        .strikethrough(sub.isCompleted)
                        .foregroundStyle(sub.isCompleted ? .secondary : .primary)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        app.deleteTask(id: sub.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(accentColor)
                TextField("Add a sub-task", text: $newSubtask)
                    .onSubmit {
                        let trimmed = newSubtask.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        app.addTask(TaskDraft(projectID: nil, parentID: taskID, name: trimmed,
                                              description: "", priority: 4))
                        newSubtask = ""
                    }
            }
        }
    }

    private var commentsSection: some View {
        Section("Comments") {
            ForEach(comments) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(comment.userName)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(comment.createdAt.prefix(10))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(comment.body)
                        .font(.subheadline)
                }
                .padding(.vertical, 2)
            }
            ForEach(pendingComments, id: \.self) { body in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("You")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Label("pending", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(body)
                        .font(.subheadline)
                }
                .padding(.vertical, 2)
            }
            HStack(spacing: 10) {
                TextField("Add a comment", text: $newComment, axis: .vertical)
                Button {
                    let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    app.addComment(taskID: taskID, body: trimmed)
                    newComment = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var pendingComments: [String] {
        app.queue.compactMap {
            if case .addComment(let id, let body) = $0, id == taskID { body } else { nil }
        }
    }

    private func populate() {
        guard !loaded, let task else { return }
        loaded = true
        name = task.name
        descriptionText = task.description
        dueDate = task.dueDate.flatMap(DateUtil.parseDay)
        dueTime = task.dueTime.flatMap { time in
            let parts = time.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())
        }
        deadline = task.deadline.flatMap(DateUtil.parseDay)
        priority = Priority(rawValue: task.priority) ?? .p4
        projectID = task.projectID
    }

    private func loadComments() async {
        guard taskID > 0, app.isOnline, let api = app.api else { return }
        if let detail = try? await api.taskDetail(id: taskID) {
            comments = detail.comments
        }
    }

    private var accentColor: Color {
        AppAccentPalette.color(for: accent)
    }

    /// Diff the edited fields against the cached task and enqueue one patch.
    private func saveChanges() {
        guard loaded, let task else { return }
        var patch = TaskPatch()

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty, trimmedName != task.name { patch.name = trimmedName }
        if descriptionText != task.description { patch.description = descriptionText }

        let newDue = dueDate.map(DateUtil.dayString)
        if newDue != task.dueDate {
            patch.dueDate = newDue.map { .set($0) } ?? .clear
        }
        let newTime = dueDate != nil ? dueTime.map(DateUtil.timeString) : nil
        if newTime != task.dueTime {
            patch.dueTime = newTime.map { .set($0) } ?? .clear
        }
        let newDeadline = deadline.map(DateUtil.dayString)
        if newDeadline != task.deadline {
            patch.deadline = newDeadline.map { .set($0) } ?? .clear
        }
        if priority.rawValue != task.priority { patch.priority = priority.rawValue }
        if let projectID, projectID != task.projectID, task.parentID == nil {
            patch.projectID = projectID
        }

        guard !patch.isEmpty else { return }
        app.updateTask(id: taskID, patch: patch)
        loaded = false // repopulate if re-shown
    }
}
