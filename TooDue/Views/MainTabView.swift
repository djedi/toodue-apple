import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var quickAdd = false
    @State private var showSettings = false

    var body: some View {
        TabView {
            tab("Inbox", icon: "tray", badge: app.inboxCount) { InboxView() }
            tab("Today", icon: "calendar", badge: app.todayTasks.count) { TodayView() }
            tab("Upcoming", icon: "calendar.badge.clock", badge: 0) { UpcomingView() }
            tab("Projects", icon: "number", badge: 0) { ProjectsView() }
        }
        .overlay(alignment: .bottomTrailing) {
            quickAddButton
        }
        .sheet(isPresented: $quickAdd) {
            QuickAddView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.connectSSE()
                Task { await app.resync() }
            } else if phase == .background {
                app.disconnectSSE()
            }
        }
    }

    private func tab(_ title: String, icon: String, badge: Int, @ViewBuilder content: () -> some View) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                    if !app.isOnline || app.pendingCount > 0 {
                        ToolbarItem(placement: .topBarLeading) {
                            OfflineBadge()
                        }
                    }
                }
        }
        .tabItem { Label(title, systemImage: icon) }
        .badge(badge)
    }

    private var quickAddButton: some View {
        Button {
            quickAdd = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.brand, in: Circle())
                .shadow(color: Color.brand.opacity(0.3), radius: 12, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 64)
        .accessibilityLabel("Add task")
    }
}

/// Small pill showing offline state / queued changes, like a sync indicator.
struct OfflineBadge: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: app.isOnline ? "arrow.triangle.2.circlepath" : "wifi.slash")
                .font(.system(size: 11, weight: .semibold))
            if app.pendingCount > 0 {
                Text("\(app.pendingCount)")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundStyle(app.isOnline ? Color.secondary : Color.deadlineFlag)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
        .accessibilityLabel(app.isOnline ? "\(app.pendingCount) changes syncing" : "Offline")
    }
}
