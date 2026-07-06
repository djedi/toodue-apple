import SwiftUI

/// Login / register, mirroring the PWA's auth screen.
struct AuthView: View {
    @Environment(AppState.self) private var app
    @State private var registering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var submitting = false
    @State private var showServerPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image("TooDueLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    Text("TooDue")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                }
                .padding(.top, 64)

                Text(registering ? "Create your account" : "Welcome back")
                    .font(.title3.weight(.semibold))

                VStack(spacing: 12) {
                    if registering {
                        TextField("Name", text: $name)
                            .textContentType(.name)
                    }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password (8+ characters)", text: $password)
                        .textContentType(registering ? .newPassword : .password)
                        .onSubmit(submit)
                }
                .textFieldStyle(.roundedBorder)

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Color.overdue)
                }

                Button(action: submit) {
                    Text(submitting ? "One moment…" : (registering ? "Sign up" : "Log in"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(submitting || !formValid)

                Button(registering ? "Already have an account? Log in"
                                   : "Don't have an account? Sign up") {
                    registering.toggle()
                    error = nil
                }
                .font(.subheadline)

                // Bitwarden-style: the hosted service by default, self-hosting
                // one deliberate tap away.
                Button {
                    showServerPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "server.rack")
                        Text("Logging in on: **\(serverHost)**")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 16)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showServerPicker) {
            ServerSetupView()
                .presentationDetents([.medium])
        }
    }

    private var formValid: Bool {
        let emailOK = email.contains("@")
        let passwordOK = password.count >= 8
        return registering ? (!name.trimmingCharacters(in: .whitespaces).isEmpty && emailOK && passwordOK)
                           : (emailOK && !password.isEmpty)
    }

    private var serverHost: String {
        URL(string: app.serverURLString)?.host() ?? app.serverURLString
    }

    private func submit() {
        guard formValid, !submitting else { return }
        submitting = true
        error = nil
        Task {
            defer { submitting = false }
            do {
                if registering {
                    try await app.register(name: name, email: email, password: password)
                } else {
                    try await app.login(email: email, password: password)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
