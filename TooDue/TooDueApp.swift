import SwiftUI

@main
struct TooDueApp: App {
    @State private var app = AppState()
    @AppStorage("toodue-theme") private var theme = "system"
    @AppStorage(AppAccentPalette.storageKey) private var accent = AppAccentPalette.defaultName

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(AppAccentPalette.color(for: accent))
                .preferredColorScheme(colorScheme)
        }
    }

    private var colorScheme: ColorScheme? {
        switch theme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        switch app.phase {
        case .loading:
            ProgressView()
        case .needsAuth:
            AuthView()
        case .ready:
            MainTabView()
        }
    }
}
