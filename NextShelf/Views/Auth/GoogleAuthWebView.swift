import SwiftUI
import WebKit

/// Google sign-in, v1 approach.
///
/// The server's Google flow is a redirect flow, not a native SDK:
///   /auth/google → accounts.google.com → /auth/google/callback → 302 /app
/// There is no custom URL scheme to catch, so the app runs the flow in a
/// WKWebView and watches for the landing on /app. On success it copies
/// the session cookie (`hs_session`) out of the web view's cookie store
/// into the shared HTTPCookieStorage, so the API client is signed in.
///
/// This is the reverse of TickerWebView, which copies cookies INTO the
/// web view so the embedded ticker page loads authenticated.
struct GoogleAuthView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let onDone: () -> Void

    @State private var error: String?
    @State private var finished = false

    var body: some View {
        NavigationStack {
            ZStack {
                GoogleAuthWebView(onSuccess: {
                    guard !finished else { return }
                    finished = true
                    Task {
                        await session.refreshMe()
                        onDone()
                        dismiss()
                    }
                }, onError: { message in
                    error = message
                })
                .ignoresSafeArea(edges: .bottom)

                if let error {
                    VStack {
                        Spacer()
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(NSColor.down)
                            .padding(12)
                            .background(NSColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding()
                    }
                }
            }
            .navigationTitle("Continue with Google")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone(); dismiss() }
                }
            }
        }
    }
}

private struct GoogleAuthWebView: UIViewRepresentable {
    var onSuccess: () -> Void
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // A fresh, non-persistent store would lose the cookie on the
        // redirect round-trip; use the default store and copy out after.
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: APIClient.googleAuthURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: GoogleAuthWebView
        private var completed = false

        init(parent: GoogleAuthWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !completed, let url = webView.url else { return }
            if url.path == "/app" || url.path == "/" {
                // Landed on the app after the Google callback: the
                // server set the session cookie on this web view.
                completed = true
                copyCookiesOut(of: webView) { [weak self] in
                    self?.parent.onSuccess()
                }
            } else if url.path == "/login",
                      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "error" })?.value?
                        .replacingOccurrences(of: "+", with: " ") {
                completed = true
                parent.onError(query)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !completed else { return }
            completed = true
            parent.onError(error.localizedDescription)
        }

        /// Move every cookie from the web view's store into the shared
        /// storage the API client reads. `hs_session` is httponly — the
        /// store still hands it over via getAllCookies.
        private func copyCookiesOut(of webView: WKWebView, completion: @escaping () -> Void) {
            let store = WKWebsiteDataStore.default().httpCookieStore
            store.getAllCookies { cookies in
                for cookie in cookies {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                completion()
            }
        }
    }
}
