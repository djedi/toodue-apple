import SwiftUI

// MARK: - Inbox

struct InboxView: View {
    @Environment(AppState.self) private var app
    @State private var selected: TodoTask?

    var body: some View {
        List {
            if let inbox = app.inboxProject {
                let items = app.activeTasks(inProject: inbox.id)
                if items.isEmpty {
                    EmptyStateView(icon: "tray", message: "Inbox zero. Nice.")
                }
                ForEach(items) { task in
                    Button { selected = task } label: { TaskRow(task: task) }
                        .buttonStyle(.plain)
                        .taskSwipeActions(task, app: app)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Inbox")
        .refreshable { await app.resync() }
        .sheet(item: $selected) { TaskDetailView(taskID: $0.id) }
    }
}

// MARK: - Today

struct TodayView: View {
    @Environment(AppState.self) private var app
    @State private var selected: TodoTask?

    var body: some View {
        List {
            let overdue = app.todayTasks.filter { $0.dueDate.map { DateUtil.isOverdue($0) } == true }
            let today = app.todayTasks.filter { $0.dueDate.map { DateUtil.isToday($0) } == true }

            if app.todayTasks.isEmpty {
                EmptyStateView(icon: "sun.max", message: "Nothing due today.")
            }
            if !overdue.isEmpty {
                Section {
                    ForEach(overdue) { task in row(task) }
                } header: {
                    sectionHeader("Overdue", color: .overdue)
                }
            }
            if !today.isEmpty {
                Section {
                    ForEach(today) { task in row(task) }
                } header: {
                    sectionHeader("Today", color: .dueToday)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Today")
        .refreshable { await app.resync() }
        .sheet(item: $selected) { TaskDetailView(taskID: $0.id) }
    }

    private func row(_ task: TodoTask) -> some View {
        Button { selected = task } label: { TaskRow(task: task, showProject: true) }
            .buttonStyle(.plain)
            .taskSwipeActions(task, app: app)
    }

    private func sectionHeader(_ title: String, color: Color) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1)
            .foregroundStyle(color)
    }
}

// MARK: - Upcoming

struct UpcomingView: View {
    @Environment(AppState.self) private var app
    @State private var selected: TodoTask?

    var body: some View {
        List {
            if app.upcomingByDay.isEmpty {
                EmptyStateView(icon: "calendar.badge.clock", message: "No upcoming dated tasks.")
            }
            ForEach(app.upcomingByDay, id: \.day) { group in
                Section {
                    ForEach(group.tasks) { task in
                        Button { selected = task } label: { TaskRow(task: task, showProject: true) }
                            .buttonStyle(.plain)
                            .taskSwipeActions(task, app: app)
                    }
                } header: {
                    Text(DateUtil.relativeLabel(for: group.day).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Color.upcomingAccent)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Upcoming")
        .refreshable { await app.resync() }
        .sheet(item: $selected) { TaskDetailView(taskID: $0.id) }
    }
}

// MARK: - Projects

struct ProjectsView: View {
    @Environment(AppState.self) private var app
    @State private var newProject = false

    var body: some View {
        List {
            ForEach(SyncLogic.flattenedProjects(app.projects), id: \.project.id) { entry in
                NavigationLink(value: entry.project.id) {
                    ProjectRow(project: entry.project, depth: entry.depth)
                }
                .swipeActions(edge: .trailing) {
                    if !entry.project.inbox {
                        Button(role: .destructive) {
                            app.deleteProject(id: entry.project.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Projects")
        .navigationDestination(for: Int64.self) { ProjectDetailView(projectID: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newProject = true } label: { Image(systemName: "plus") }
            }
        }
        .refreshable { await app.resync() }
        .sheet(isPresented: $newProject) {
            ProjectEditView(project: nil)
                .presentationDetents([.medium])
        }
    }
}

struct ProjectRow: View {
    let project: Project
    let depth: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: project.inbox ? "tray" : "number")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(project.inbox ? Color.brand : ProjectColor.color(for: project.color))
                .frame(width: 22)
            Text(project.name)
                .font(.subheadline)
            if let members = project.members, members.count > 1 {
                Image(systemName: "person.2")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let count = project.activeCount, count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, CGFloat(depth) * 20)
        .padding(.vertical, 2)
        .opacity(project.id < 0 ? 0.75 : 1)
    }
}

// MARK: - Shared empty state

struct EmptyStateView: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowSeparator(.hidden)
    }
}
