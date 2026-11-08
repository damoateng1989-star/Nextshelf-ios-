import SwiftUI

/// The app's auth state. Owned by the App, passed down as an
/// environment object. All mutations happen on the main actor.
///
/// Flow (same routing pattern as Regulur's AppDelegate splash →
/// login → main shell, rewritten for SwiftUI):
///   unknown → /api/me → signedIn | signedOut (welcome screen)
///   guest   → the user tapped "Browse as guest": board in guest mode
@MainActor
final class SessionStore: ObservableObject {
    enum AuthState { case unknown, signedIn, signedOut, guest }

    @Published private(set) var state: AuthState = .unknown
    @Published private(set) var me: MeResponse?
    @Published private(set) var authConfig: AuthConfig?
    @Published var isBusy = false
    @Published var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
        Task { await bootstrap() }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        async let meTask: MeResponse? = try? api.me()
        async let configTask: AuthConfig? = try? api.authConfig()
        let (me, config) = await (meTask, configTask)
        self.authConfig = config
        apply(me: me)
    }

    /// Re-read /api/me after any auth change (login, logout, Google).
    func refreshMe() async {
        if let me = try? await api.me() {
            apply(me: me)
        } else {
            apply(me: nil)
        }
    }

    private func apply(me: MeResponse?) {
        self.me = me
        if let me, !me.isGuest {
            state = .signedIn
        } else if state == .guest {
            // Stay in guest mode; keep the guest payload for tier UI.
            self.me = me
        } else {
            state = .signedOut
        }
    }

    var isSignedIn: Bool { state == .signedIn }
    var isGuest: Bool { state == .guest }
    var isPro: Bool { me?.isPro == true }

    // MARK: - Auth actions

    func enterAsGuest() {
        state = .guest
        Task { await refreshMe() }
    }

    func signIn(email: String, password: String) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            _ = try await api.login(email: email, password: password)
            await refreshMe()
            return state == .signedIn
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func signUp(email: String, password: String, name: String, invite: String) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            _ = try await api.signup(email: email, password: password, name: name, invite: invite)
            await refreshMe()
            return state == .signedIn
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func forgotPassword(email: String) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            _ = try await api.forgot(email: email)
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func signOut() async {
        isBusy = true
        defer { isBusy = false }
        _ = try? await api.logout()
        me = nil
        state = .signedOut
    }
}
