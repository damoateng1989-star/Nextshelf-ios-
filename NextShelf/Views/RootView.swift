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
        // Nov 22 2026 (hybrid): Today, Cinema and Learn come from the live
        // site (SitePageView), so web changes reach the app without a new
        // build; Setups, Watchlist, Record and Alerts stay native. Five tabs:
        // our own More list (not the system one, which doubles the
        // navigation bar around a NavigationStack) holds Learn, Record, Alerts.
        TabView {
            NavigationStack {
                SitePageView(title: "Today", path: "/app#today")
            }
            .tabItem { Label("Today", systemImage: "house") }

            NavigationStack {
                BoardView()
            }
            .tabItem { Label("Setups", systemImage: "square.grid.2x2") }

            NavigationStack {
                WatchlistView()
            }
            .tabItem { Label("Watchlist", systemImage: "star") }

            NavigationStack {
                SitePageView(title: "Cinema", path: "/app#cinema")
            }
            .tabItem { Label("Cinema", systemImage: "film") }

            NavigationStack {
                MoreView()
            }
            .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(NSColor.blue)
    }
}

/// The fifth tab: Learn (from the site), Record and Alerts (native).
struct MoreView: View {
    var body: some View {
        List {
            NavigationLink {
                SitePageView(title: "Learn", path: "/learn")
            } label: {
                Label("Learn", systemImage: "graduationcap")
            }
            NavigationLink {
                SitePageView(title: "Glossary", path: "/learn/glossary")
            } label: {
                Label("Glossary", systemImage: "character.book.closed")
            }
            NavigationLink {
                RecordView()
            } label: {
                Label("Record", systemImage: "chart.bar")
            }
            NavigationLink {
                AlertsSettingsView()
            } label: {
                Label("Alerts & account", systemImage: "bell")
            }
        }
        .navigationTitle("More")
    }
}
