import SwiftUI

/// Self-hosted server picker, tucked behind a "Server" link (Bitwarden-style):
/// the app talks to the official hosted service unless someone deliberately
/// comes here and points it elsewhere.
struct ServerSetupView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private var official: String { ServerConfig.defaultURLString }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(official, text: $urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onSubmit(save)
                } header: {
                    Text("Server URL")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Only change this if you self-host TooDue. Plain hostnames default to https.")
                        if let error {
                            Text(error)
                                .foregroundStyle(Color.overdue)
                        }
                        if app.phase == .ready {
                            Text("Switching servers signs you out and clears local data for the current server.")
                                .foregroundStyle(Color.deadlineFlag)
                        }
                    }
                }

                if app.isCustomServer {
                    Section {
                        Button("Use the official server") {
                            urlString = official
                            save()
                        }
                    } footer: {
                        Text(verbatim: official)
                    }
                }
            }
            .navigationTitle("Self-hosted Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                urlString = app.serverURLString
                focused = true
            }
        }
    }

    private func save() {
        do {
            error = nil
            try app.setServer(urlString.isEmpty ? official : urlString)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
