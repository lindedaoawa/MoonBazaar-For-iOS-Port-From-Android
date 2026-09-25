import SwiftUI
import SafariServices

@main
struct MoonBazaarApp: App {
    @StateObject private var vm = MainViewModel()

    var body: some Scene {
        WindowGroup {
            MoonThemeRoot {
                RootView(vm: vm)
            }
        }
    }
}

/// 根视图：主界面 + 全屏登录页 + 外链浏览器。
/// 对应 Android `MainActivity.Root()`。
struct RootView: View {
    @ObservedObject var vm: MainViewModel

    @State private var showLogin = false
    @State private var safariTarget: SafariTarget?

    var body: some View {
        MoonAppView(
            vm: vm,
            openUrl: { urlString in
                if let url = URL(string: urlString) { safariTarget = SafariTarget(url: url) }
            },
            onStartLogin: { showLogin = true }
        )
        .fullScreenCover(isPresented: $showLogin) {
            WebLoginScreen(
                startUrl: AppConfig.loginUrl,
                onToken: { token in
                    // 新登录：加入账号列表并设为当前，再拉取数据
                    Session.shared.addAndSelect(token: token)
                    vm.refreshAuthState()
                    vm.reloadAll()
                    showLogin = false
                },
                onClose: { showLogin = false }
            )
        }
        .sheet(item: $safariTarget) { target in
            SafariView(url: target.url)
                .ignoresSafeArea()
        }
        .onOpenURL { url in
            captureSession(from: url)
        }
    }

    /// 仍然接受携带 token 的深链（mnb://auth/callback?session_token=...）——防御性逻辑。
    private func captureSession(from url: URL) {
        guard url.scheme?.lowercased() == AppConfig.CALLBACK_SCHEME.lowercased() else { return }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = comps.queryItems?.first(where: { $0.name == "session_token" })?.value,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Session.shared.addAndSelect(token: token)
        vm.refreshAuthState()
        vm.reloadAll()
    }
}

/// `.sheet(item:)` 需要一个 Identifiable；URL 本身不是，这里包一层。
private struct SafariTarget: Identifiable {
    let id = UUID()
    let url: URL
}

/// 应用内浏览器（对应 Android 的 CustomTabsIntent）。
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(MoonTheme.hex(0x6650A4))
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}