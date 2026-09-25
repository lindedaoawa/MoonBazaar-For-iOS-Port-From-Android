import SwiftUI

/// 所有内嵌 WebView 共用的顶栏：退出 + 当前地址 + 刷新。
/// 对应 Android `ui/WebViewBar.kt` 的 `WebViewTopBar`。
struct WebViewTopBar: View {
    @Environment(\.moonColors) private var c

    let title: String
    let loading: Bool
    let onRefresh: () -> Void
    let onClose: () -> Void
    var closeText: String = "← 返回"

    var body: some View {
        MoonBar {
            HStack(spacing: 6) {
                Button(closeText, action: onClose)
                    .font(.subheadline)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(c.outline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if loading {
                    ProgressView().controlSize(.mini)
                }
                Button("刷新", action: onRefresh)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

/// 从 URL 取 host 用于顶栏展示。
func hostOf(_ urlString: String) -> String {
    if let host = URL(string: urlString)?.host, !host.isEmpty { return host }
    return urlString
}