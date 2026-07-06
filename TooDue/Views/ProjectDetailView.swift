import SwiftUI

struct ProjectDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let projectID: Int64

    @State private var selected: TodoTask?
    @State private var editing = false
    @State private var newTaskName = ""
    @FocusState private var addFocused: Bool

    private var project: Project? { app.project(projectID) }

    var body: some View {
        List {
            let children = SyncLogic.flattenedProjects(app.projects)
                .filter { $0.project.parentID == projectID && $0.depth > 0 }
                .map(\.project)
            if !children.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(children) { child in
                            NavigationLink(value: child.id) {
                                HStack(spacing: 4) {
                                    Image(systemName: "number")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(ProjectColor.color(for: child.color))
                                    Text(child.name)
                                        .font(.caption)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }

            ForEach(app.activeTasks(inProject: projectID)) { task in
                Button { selected = task } label: { TaskRow(task: task) }
                    .buttonStyle(.plain)
                    .taskSwipeActions(task, app: app)
            }

            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.brand)
                TextField("Add a task", text: $newTaskName)
                    .focused($addFocused)
                    .onSubmit(addTask)
            }
            .listRowSeparator(.hidden)
            .padding(.top, 4)
        }
        .listStyle(.plain)
        .navigationTitle(project?.name ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let project, !project.inbox {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = true } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .refreshable { await app.resync() }
        .sheet(item: $selected) { TaskDetailView(taskID: $0.id) }
        .sheet(isPresented: $editing) {
            ProjectEditView(project: project)
                .presentationDetents([.medium])
        }
        .onChange(of: project == nil) { _, gone in
            if gone { dismiss() } // project deleted (possibly remotely)
        }
    }

    private func addTask() {
        let name = newTaskName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        app.addTask(TaskDraft(projectID: projectID, parentID: nil, name: name, description: "", priority: 4))
        newTaskName = ""
        addFocused = true
    }
}

/// Create or edit a project: name, color, parent.
struct ProjectEditView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let project: Project?

    @State private var name = ""
    @State private var color = "sky"
    @State private var parentID: Int64?

    private let colorColumns = [
        GridItem(.adaptive(minimum: 64), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Project name", text: $name)

                Section("Color") {
                    LazyVGrid(columns: colorColumns, spacing: 12) {
                        ForEach(ProjectColor.named, id: \.name) { entry in
                            Button {
                                color = entry.name
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle()
                                            .fill(entry.color)
                                            .frame(width: 28, height: 28)
                                        if color == entry.name {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    Text(entry.name.capitalized)
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(color == entry.name ? entry.color.opacity(0.14) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(color == entry.name ? entry.color : Color.secondary.opacity(0.22), lineWidth: color == entry.name ? 2 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(entry.name.capitalized) project color")
                            .accessibilityAddTraits(color == entry.name ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Picker("Parent project", selection: $parentID) {
                    Text("None").tag(Int64?.none)
                    ForEach(parentCandidates, id: \.project.id) { entry in
                        Text(String(repeating: "  ", count: entry.depth) + entry.project.name)
                            .tag(Int64?.some(entry.project.id))
                    }
                }
            }
            .navigationTitle(project == nil ? "New Project" : "Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(project == nil ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let project {
                    name = project.name
                    color = project.color
                    parentID = project.parentID
                }
            }
        }
    }

    /// Projects that could be this project's parent: not the inbox, not itself,
    /// not its own descendants.
    private var parentCandidates: [(project: Project, depth: Int)] {
        var excluded: Set<Int64> = []
        if let project {
            excluded.insert(project.id)
            var changed = true
            while changed {
                changed = false
                for p in app.projects where p.parentID.map({ excluded.contains($0) }) == true {
                    if excluded.insert(p.id).inserted { changed = true }
                }
            }
        }
        return SyncLogic.flattenedProjects(app.projects).filter {
            !$0.project.inbox && !excluded.contains($0.project.id)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let project {
            var patch = ProjectPatch()
            if trimmed != project.name { patch.name = trimmed }
            if color != project.color { patch.color = color }
            if parentID != project.parentID {
                patch.parentID = parentID.map { .set($0) } ?? .clear
            }
            app.updateProject(id: project.id, patch: patch)
        } else {
            app.addProject(name: trimmed, color: color, parentID: parentID)
        }
        dismiss()
    }
}
