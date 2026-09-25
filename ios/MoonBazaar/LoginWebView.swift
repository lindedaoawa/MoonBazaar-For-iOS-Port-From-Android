import SwiftUI
import WebKit

// ---- In-app WebView OAuth ----
// Worker 在 HTML 页面结束授权：/auth/done?auth=ok&uid=..&session_token=..
// 系统浏览器无法跳回 App，所以整个流程都放在 WebView 内；页面一落到 /auth/done
// 就抓取 token 并关闭。
//
// iOS 差异说明：Android 通过 `CookieManager.removeAllCookies()` 清空登录态，
// iOS 侧改用 `WKWebsiteDataStore.nonPersistent()`（非持久化数据存储），
// 效果等价——每次打开登录页都是全新的、无 Cookie 的会话。

/// 登录用的 WKWebView 封装。
struct LoginWebView: UIViewRepresentable {
    let startUrl: String
    @Binding var webView: WKWebView?
    let onLoading: (Bool) -> Void
    let onUrlChange: (String) -> Void
    /// token 为 nil 表示已到 /auth/done 但没有拿到 token（此时应直接关闭）。
    let onFinished: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 每次打开登录页（含「添加账号」）都用全新的非持久化存储，
        // 避免复用上一个账号的登录态、直接跳过授权。
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsLinkPreview = false

        DispatchQueue.main.async { webView = wv }

        if let url = URL(string: startUrl) {
            wv.load(URLRequest(url: url))
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LoginWebView
        /// 抓到 token 后封锁后续处理，避免重复回调。
        private var captured = false

        init(_ parent: LoginWebView) { self.parent = parent }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url?.absoluteString, handle(url) {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoading(true)
            if let u = webView.url?.absoluteString { parent.onUrlChange(u) }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if let u = webView.url?.absoluteString {
                parent.onUrlChange(u)
                _ = handle(u)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoading(false)
            if let u = webView.url?.absoluteString {
                parent.onUrlChange(u)
                _ = handle(u)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onLoading(false)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            parent.onLoading(false)
        }

        /// 命中 /auth/done 时抓取 session_token；返回 true 表示已处理（应停止加载）。
        @discardableResult
        private func handle(_ urlString: String) -> Bool {
            guard let comps = URLComponents(string: urlString),
                  comps.scheme?.lowercased() == "https",
                  comps.host?.lowercased() == AppConfig.BASE_HOST.lowercased(),
                  comps.path.hasPrefix("/auth/done") else { return false }

            if captured { return true }
            captured = true
            parent.onLoading(false)
            let token = comps.queryItems?.first { $0.name == "session_token" }?.value
            if let token = token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parent.onFinished(token)
            } else {
                parent.onFinished(nil)   // 到了 done 但没有 token
            }
            return true
        }
    }
}

/// 登录页：顶栏 + 登录用 WebView。对应 Android `ui/LoginWebView.kt` 的 `WebLoginScreen`。
struct WebLoginScreen: View {
    let startUrl: String
    let onToken: (String) -> Void
    let onClose: () -> Void

    @State private var loading = true
    @State private var shownUrl: String
    @State private var webView: WKWebView?

    init(startUrl: String,
         onToken: @escaping (String) -> Void,
         onClose: @escaping () -> Void) {
        self.startUrl = startUrl
        self.onToken = onToken
        self.onClose = onClose
        _shownUrl = State(initialValue: startUrl)
    }

    var body: some View {
        VStack(spacing: 0) {
            WebViewTopBar(
                title: hostOf(shownUrl),
                loading: loading,
                onRefresh: { webView?.reload() },
                onClose: onClose,
                closeText: "✕ 退出"
            )
            ZStack {
                if loading {
                    ProgressView()
                        .tint(MoonTheme.hex(0x6650A4))
                }
                LoginWebView(
                    startUrl: startUrl,
                    webView: $webView,
                    onLoading: { loading = $0 },
                    onUrlChange: { shownUrl = $0 },
                    onFinished: { token in
                        if let token = token {
                            onToken(token)
                        } else {
                            onClose()
                        }
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}