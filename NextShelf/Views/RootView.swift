import SwiftUI

/// Root routing: welcome → main tab shell (Board / Watchlist / Record /
/// Alerts). Same pattern as Regulur's tab-bar shell (UserMainView),
/// content fully replaced.
struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            switch session.state {
            case .unknown:
                LoadingView(message: "Checking your session…")
            case .signedOut:
                WelcomeView()
            case .signedIn, .guest:
                MainTabView()
            }
        }
        .background(NSColor.paper)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        TabView {
            NavigationStack {
                BoardView()
            }
            .tabItem { Label("Setups", systemImage: "square.grid.2x2") }

            NavigationStack {
                WatchlistView()
            }
            .tabItem { Label("Watchlist", systemImage: "star") }

            NavigationStack {
                RecordView()
            }
            .tabItem { Label("Record", systemImage: "chart.bar") }

            NavigationStack {
                AlertsSettingsView()
            }
            .tabItem { Label("Alerts", systemImage: "bell") }
        }
        .tint(NSColor.blue)
    }
}
