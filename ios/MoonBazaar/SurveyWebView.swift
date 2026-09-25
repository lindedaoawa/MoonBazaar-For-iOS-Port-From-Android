import SwiftUI
import WebKit

// ============================ 问卷 WebView ============================
// 问卷在 App 内打开，并对请求做重写 / 拦截，避免依赖被墙的域名。
//
// iOS 实现方式与 Android 不同（WKWebView 没有 `shouldInterceptRequest` 等价钩子）：
//   1. 拦截：编译 `WKContentRuleList`（内容拦截规则），原生阻止被墙域名的子资源加载；
//   2. 重写：注入 document-start 脚本，改写 fetch / XHR / 元素 src|href / 动态添加的节点；
//   3. 主框架导航：由 `WKNavigationDelegate` 直接拦截与重写。
// 规则集本身与 Android 完全一致，见 `SurveyUrlRules`。

/// 问卷用的 WKWebView 封装。
struct SurveyWebView: UIViewRepresentable {
    let startUrl: String
    @Binding var webView: WKWebView?
    let onLoading: (Bool) -> Void
    let onUrlChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        // Android 侧是 UA + " MoonBazaarAndroid"，这里用同等方式追加应用标识
        config.applicationNameForUserAgent = "MoonBazaarIOS"

        let ucc = config.userContentController
        // ② 子资源重写：document start 注入
        ucc.addUserScript(WKUserScript(
            source: SurveyUrlRules.rewriteUserScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        // ① 子资源拦截：编译内容规则（编译是异步的，完成后即生效）
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "MoonBazaarBlockRules",
            encodedContentRuleList: SurveyUrlRules.contentRuleListJSON
        ) { list, _ in
            if let list = list { ucc.add(list) }
        }

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true

        DispatchQueue.main.async { webView = wv }

        if let url = URL(string: startUrl) {
            wv.load(URLRequest(url: url))
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: SurveyWebView

        init(_ parent: SurveyWebView) { self.parent = parent }

        // 主框架导航：拦截 & 重写
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url?.absoluteString, !url.isEmpty else {
                decisionHandler(.allow)
                return
            }
            if SurveyUrlRules.isBlocked(url) {
                decisionHandler(.cancel)          // 直接拦截，不加载
                return
            }
            let rewritten = SurveyUrlRules.rewrite(url)
            if rewritten != url, let newURL = URL(string: rewritten) {
                webView.load(URLRequest(url: newURL))
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // target=_blank / window.open：保持单窗口（等价 Android setSupportMultipleWindows(false)）
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoading(true)
            if let u = webView.url?.absoluteString { parent.onUrlChange(u) }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if let u = webView.url?.absoluteString { parent.onUrlChange(u) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoading(false)
            if let u = webView.url?.absoluteString { parent.onUrlChange(u) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onLoading(false)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            parent.onLoading(false)
        }
    }
}

/// 问卷页：顶栏 + 问卷 WebView。对应 Android `ui/SurveyWebView.kt` 的 `SurveyWebScreen`。
struct SurveyWebScreen: View {
    let startUrl: String
    let onClose: () -> Void

    @State private var loading = true
    @State private var shownUrl: String
    @State private var webView: WKWebView?

    init(startUrl: String, onClose: @escaping () -> Void) {
        self.startUrl = startUrl
        self.onClose = onClose
        _shownUrl = State(initialValue: startUrl)
    }

    var body: some View {
        VStack(spacing: 0) {
            WebViewTopBar(
                title: hostOf(shownUrl),
                loading: loading,
                onRefresh: { webView?.reload() },
                onClose: onClose
            )
            SurveyWebView(
                startUrl: startUrl,
                webView: $webView,
                onLoading: { loading = $0 },
                onUrlChange: { shownUrl = $0 }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}