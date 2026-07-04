import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("toodue-theme") private var theme = "system"

    @State private var feedURL: URL?
    @State private var copiedFeed = false
    @State private var confirmLogout = false
    @State private var showServerPicker = false

    var body: some View {
        NavigationStack {
            Form {
                if let user = app.user {
                    Section {
                        HStack(spacing: 12) {
                            Text(initials(user.name))
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.brand, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name)
                                    .font(.headline)
                                Text(user.email)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $theme) {
                        Text("Light").tag("light")
                        Text("System").tag("system")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Sync") {
                    LabeledContent("Server") {
                        Text(URL(string: app.serverURLString)?.host() ?? app.serverURLString)
                    }
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(app.isOnline ? Color.dueToday : Color.deadlineFlag)
                                .frame(width: 8, height: 8)
                            Text(app.isOnline ? "Online" : "Offline")
                        }
                    }
                    if app.pendingCount > 0 {
                        DisclosureGroup("\(app.pendingCount) pending \(app.pendingCount == 1 ? "change" : "changes")") {
                            ForEach(Array(app.queue.enumerated()), id: \.offset) { _, mutation in
                                Text(mutation.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Sync now") {
                            Task { await app.resync() }
                        }
                        .disabled(!app.isOnline)
                    }
                    if let error = app.syncError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Color.deadlineFlag)
                    }
                }

                Section {
                    if let feedURL {
                        Button {
                            UIPasteboard.general.string = feedURL.absoluteString
                            copiedFeed = true
                        } label: {
                            Label(copiedFeed ? "Copied!" : "Copy iCal feed URL",
                                  systemImage: copiedFeed ? "checkmark" : "doc.on.doc")
                        }
                    } else {
                        Text("Connect to the server to fetch your calendar feed URL.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Calendar feed")
                } footer: {
                    Text("Subscribe from Google Calendar or Fantastical; dated tasks appear as events. The URL contains a private token.")
                }

                Section {
                    Button("Self-hosted server…") {
                        showServerPicker = true
                    }
                    Button("Log out", role: .destructive) {
                        confirmLogout = true
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                feedURL = try? await app.api?.calendarFeedURL()
            }
            .sheet(isPresented: $showServerPicker) {
                ServerSetupView()
                    .presentationDetents([.medium])
            }
            .confirmationDialog(
                app.pendingCount > 0
                    ? "You have \(app.pendingCount) unsynced changes that will be lost."
                    : "Log out of TooDue?",
                isPresented: $confirmLogout,
                titleVisibility: .visible
            ) {
                Button("Log out", role: .destructive) {
                    Task {
                        await app.logout()
                        dismiss()
                    }
                }
            }
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}
