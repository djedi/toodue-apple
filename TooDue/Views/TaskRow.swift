import SwiftUI

/// One task in a list: priority-colored circular checkbox, name, description,
/// and metadata badges — a native take on the PWA's task item.
struct TaskRow: View {
    @Environment(AppState.self) private var app
    let task: TodoTask
    var showProject = false

    @State private var justCompleted = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            checkbox
            VStack(alignment: .leading, spacing: 3) {
                Text(task.name)
                    .font(.subheadline)
                    .strikethrough(justCompleted)
                    .foregroundStyle(justCompleted ? .secondary : .primary)
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                badges
            }
        }
        .padding(.vertical, 2)
        .opacity(task.isLocalOnly ? 0.75 : 1)
    }

    private var checkbox: some View {
        Button {
            guard !justCompleted else { return }
            justCompleted = true
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                app.setCompleted(task, true)
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(priority.color, lineWidth: 2)
                    .background(Circle().fill(justCompleted ? priority.color : .clear))
                if justCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .padding(.top, 1)
        .accessibilityLabel("Complete \(task.name)")
    }

    private var priority: Priority {
        Priority(rawValue: task.priority) ?? .p4
    }

    @ViewBuilder
    private var badges: some View {
        let hasAny = task.dueDate != nil || task.deadline != nil
            || (task.subtaskCount ?? 0) > 0 || (task.commentCount ?? 0) > 0
            || (task.attachmentCount ?? 0) > 0 || showProject || task.isLocalOnly
        if hasAny {
            HStack(spacing: 12) {
                if let due = task.dueDate {
                    badge(icon: "calendar", text: dueLabel(due), color: dueColor(due))
                }
                if let deadline = task.deadline {
                    badge(icon: "flag", text: DateUtil.relativeLabel(for: deadline), color: .deadlineFlag)
                }
                if let total = task.subtaskCount, total > 0 {
                    badge(icon: "arrow.triangle.branch", text: "\(task.subtaskDoneCount ?? 0)/\(total)", color: .secondary)
                }
                if let comments = task.commentCount, comments > 0 {
                    badge(icon: "message", text: "\(comments)", color: .secondary)
                }
                if let files = task.attachmentCount, files > 0 {
                    badge(icon: "paperclip", text: "\(files)", color: .secondary)
                }
                if task.isLocalOnly {
                    badge(icon: "arrow.triangle.2.circlepath", text: "pending", color: .secondary)
                }
                if showProject, let project = app.project(task.projectID) {
                    badge(icon: "number", text: project.name, color: .secondary)
                }
            }
            .padding(.top, 1)
        }
    }

    private func badge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(color)
    }

    private func dueLabel(_ due: String) -> String {
        var label = DateUtil.relativeLabel(for: due)
        if let time = task.dueTime {
            label += " \(DateUtil.timeLabel(time))"
        }
        return label
    }

    private func dueColor(_ due: String) -> Color {
        if DateUtil.isOverdue(due) { .overdue }
        else if DateUtil.isToday(due) { .dueToday }
        else { .secondary }
    }
}

/// Shared swipe actions for task rows.
extension View {
    func taskSwipeActions(_ task: TodoTask, app: AppState) -> some View {
        self
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    app.deleteTask(id: task.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    app.setCompleted(task, true)
                } label: {
                    Label("Done", systemImage: "checkmark.circle.fill")
                }
                .tint(.dueToday)
            }
    }
}
