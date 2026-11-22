import SwiftUI
import WebKit

/// Today, Cinema and Learn come from the live site (the hybrid approach, Nov 22 2026).
///
/// Setups, Watchlist, Record and Alerts stay native. These three sections
/// change most often on the web, so the app shows them straight from
/// nextshelfapp.com and every web change reaches the app without a new
/// build. The page loads with `?embed=ios`, which tells the site to hide
/// its own top bar, sidebar and bottom tabs (the app's tab bar replaces
/// them). The flag is kept for the session, so links inside the page stay
/// embedded too.
struct SitePageView: View {
    let title: String
    /// Path on the site, optionally with a fragment: "/app#today", "/learn".
    let path: String

    @State private var reloadToken = 0
    @State private var isLoading = true

    var body: some View {
        ZStack {
            SiteWebView(path: path, reloadToken: reloadToken, isLoading: $isLoading)
            if isLoading {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .background(NSColor.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    reloadToken += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Reload")
            }
        }
    }
}

/// A WKWebView signed in with the app's session.
///
/// Same cookie hand-off as `TickerWebView`: the API client signs in through
/// URLSession's shared cookie storage, and a WKWebView keeps its own
/// store, so the session cookie is copied in before the first load.
/// Without it the page would load signed out.
struct SiteWebView: UIViewRepresentable {
    let path: String
    var reloadToken: Int = 0
    @Binding var isLoading: Bool

    /// "/app#today" → https://nextshelfapp.com/app?embed=ios#today
    static func url(for path: String) -> URL {
        let parts = path.split(separator: "#", maxSplits: 1).map(String.init)
        var components = URLComponents(url: APIClient.baseURL, resolvingAgainstBaseURL: false)!
        components.path = parts.first ?? "/"
        components.queryItems = [URLQueryItem(name: "embed", value: "ios")]
        if parts.count > 1 { components.fragment = parts[1] }
        return components.url ?? APIClient.baseURL
    }

    func makeCoordinator() -> Coordinator { Coordinator(isLoading: $isLoading) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Cinema: films play inside the page, and start when the member taps play.
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.pulledToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        context.coordinator.webView = webView
        context.coordinator.lastReloadToken = reloadToken
        load(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            load(into: webView)
        }
    }

    private func load(into webView: WKWebView) {
        let target = Self.url(for: path)
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let shared = HTTPCookieStorage.shared.cookies ?? []
        let group = DispatchGroup()
        for cookie in shared {
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) {
            webView.load(URLRequest(url: target))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding var isLoading: Bool
        weak var webView: WKWebView?
        var lastReloadToken = 0

        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }

        @objc func pulledToRefresh(_ sender: UIRefreshControl) {
            webView?.reload()
        }

        private func setLoading(_ value: Bool) {
            DispatchQueue.main.async {
                self.isLoading = value
                if !value { self.webView?.scrollView.refreshControl?.endRefreshing() }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            setLoading(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            setLoading(false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            setLoading(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            setLoading(false)
        }

        /// NextShelf pages stay in the app. A top-level link to anywhere else
        /// (a broker, a news story) opens in Safari. Embedded frames, such as
        /// the Cinema player, always load in place.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if !isMainFrame || Self.isOwnSite(url) || url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
                return decisionHandler(.allow)
            }
            if url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" || url.scheme == "tel" {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        /// Links with target="_blank": our own pages load here, others go to Safari.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                if Self.isOwnSite(url) {
                    webView.load(URLRequest(url: url))
                } else {
                    UIApplication.shared.open(url)
                }
            }
            return nil
        }

        static func isOwnSite(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased(), let own = APIClient.baseURL.host?.lowercased() else { return false }
            return host == own || host == "www." + own
        }
    }
}
