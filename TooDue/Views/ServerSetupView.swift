import SwiftUI

/// First-run screen: point the app at a TooDue server (self-hosted or not).
struct ServerSetupView: View {
    @Environment(AppState.self) private var app
    @State private var urlString = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Color.brand)
                Text("TooDue")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("SERVER")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                TextField("toodue.example.com", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit(connect)
                Text("Enter the address of your TooDue server. Plain hostnames default to https.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Color.overdue)
                }
            }
            .padding(.horizontal, 8)

            Button(action: connect) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 8)

            Spacer()
            Spacer()
        }
        .padding(24)
        .onAppear {
            urlString = app.serverURLString
            focused = true
        }
    }

    private func connect() {
        do {
            error = nil
            try app.setServer(urlString)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
