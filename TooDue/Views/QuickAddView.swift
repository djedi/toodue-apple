import SwiftUI

/// The floating "+" sheet: name, description, date/time/deadline/priority
/// chips, and a project picker — same fields as the PWA quick-add.
struct QuickAddView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var dueDate: Date?
    @State private var dueTime: Date?
    @State private var deadline: Date?
    @State private var priority: Priority = .p4
    @State private var projectID: Int64?
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task name", text: $name, axis: .vertical)
                        .font(.title3)
                        .focused($nameFocused)
                    TextField("Description", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.subheadline)
                }

                Section {
                    OptionalDatePicker(label: "Date", icon: "calendar", selection: $dueDate)
                    if dueDate != nil {
                        OptionalTimePicker(label: "Time", selection: $dueTime)
                    }
                    OptionalDatePicker(label: "Deadline", icon: "flag", selection: $deadline)

                    Picker(selection: $priority) {
                        ForEach(Priority.allCases) { p in
                            Text(p.label).tag(p)
                        }
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
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { submit() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                projectID = projectID ?? app.inboxProject?.id
                nameFocused = true
            }
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        app.addTask(TaskDraft(
            projectID: projectID,
            parentID: nil,
            name: trimmed,
            description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: dueDate.map(DateUtil.dayString),
            dueTime: dueDate != nil ? dueTime.map(DateUtil.timeString) : nil,
            deadline: deadline.map(DateUtil.dayString),
            priority: priority.rawValue
        ))
        dismiss()
    }
}

/// A date row that supports "no date": shows a toggle-style add button, then a
/// compact picker plus clear button.
struct OptionalDatePicker: View {
    let label: String
    let icon: String
    @Binding var selection: Date?

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            if let value = selection {
                DatePicker("", selection: Binding(
                    get: { value },
                    set: { selection = $0 }
                ), displayedComponents: .date)
                .labelsHidden()
                Button {
                    selection = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Button("Add") { selection = DateUtil.today() }
                    .font(.subheadline)
            }
        }
    }
}

struct OptionalTimePicker: View {
    let label: String
    @Binding var selection: Date?

    var body: some View {
        HStack {
            Label(label, systemImage: "clock")
            Spacer()
            if let value = selection {
                DatePicker("", selection: Binding(
                    get: { value },
                    set: { selection = $0 }
                ), displayedComponents: .hourAndMinute)
                .labelsHidden()
                Button {
                    selection = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Button("Add") {
                    selection = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
                }
                .font(.subheadline)
            }
        }
    }
}
