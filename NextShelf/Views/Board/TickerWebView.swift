import SwiftUI
import WebKit

/// The v1 chart: the existing ticker page (`/t/{symbol}`) in a WKWebView.
///
/// A bare web-view wrapper of the whole site would fail App Store review;
/// v1 is native screens with the web view used ONLY for the chart, per
/// spec §8.
///
/// Cookie direction matters: the API client signs in via URLSession's
/// shared cookie storage, but a WKWebView has its own cookie store. So
/// before loading, this view copies the session cookie INTO the web
/// view's store — otherwise the ticker page's own `/api/chart` call
/// would load as a guest and the chart would come back empty.
/// (GoogleAuthWebView does the reverse: it copies cookies OUT.)
struct TickerWebView: UIViewRepresentable {
    let symbol: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = true
        loadAuthenticated(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private func loadAuthenticated(into webView: WKWebView) {
        let target = APIClient.tickerPageURL(symbol: symbol)
        let store = WKWebsiteDataStore.default().httpCookieStore
        let shared = HTTPCookieStorage.shared.cookies ?? []
        guard !shared.isEmpty else {
            webView.load(URLRequest(url: target))
            return
        }
        let group = DispatchGroup()
        for cookie in shared {
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) {
            webView.load(URLRequest(url: target))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // The surrounding view shows its own error state via the
            // loading flag; navigation errors here are non-fatal.
        }
    }
}
