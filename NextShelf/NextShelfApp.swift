import SwiftUI

/// NextShelf iOS v1 — M1–M4.
///
/// A native SwiftUI client for the NextShelf API (https://nextshelfapp.com).
/// Auth is a cookie session, exactly like the web app: URLSession's shared
/// cookie storage carries `hs_session`, no backend change needed.
///
/// M5 (push) is NOT in this build: it needs the backend `/api/me/device`
/// patch plus an APNs setup. See README.md.
@main
struct NextShelfApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}
