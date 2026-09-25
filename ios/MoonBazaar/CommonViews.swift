import SwiftUI

// MARK: - 卡片

/// 统一的圆角卡片容器（对应 Material `Card`）。
struct MoonCard<Content: View>: View {
    @Environment(\.moonColors) private var c
    var selected: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? c.primary : Color.clear, lineWidth: selected ? 2 : 0)
            )
    }
}

/// 底部/顶部的「面（Surface）」条，用于顶栏。
struct MoonBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .overlay(alignment: .bottom) {
                Divider()
            }
    }
}

// MARK: - 小组件

/// 一行「标签 —— 值」。
struct FieldRow: View {
    @Environment(\.moonColors) private var c
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(c.outline)
            Spacer(minLength: 8)
            Text(value.isEmpty ? "—" : value).fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 2)
    }
}

/// 小标签（次要色）。
struct MoonTag: View {
    @Environment(\.moonColors) private var c
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(c.secondary)
    }
}

/// 只读链接展示框。
struct LinkBox: View {
    @Environment(\.moonColors) private var c
    let link: String

    var body: some View {
        MoonCard {
            Text(link)
                .font(.subheadline)
                .foregroundStyle(c.primary)
                .textSelection(.enabled)
                .padding(12)
        }
    }
}

/// JSON 调试框（超长时折叠）。
struct JsonBox: View {
    let title: String
    let text: String
    @State private var open = false

    private var shown: String {
        if text.isEmpty { return "（空）" }
        if open || text.count <= 1200 { return text }
        return String(text.prefix(900)) + "…"
    }

    var body: some View {
        MoonCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.footnote).fontWeight(.medium)
                Text(shown)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if text.count > 1200 {
                    Button(open ? "收起" : "展开") { open.toggle() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(12)
        }
    }
}

/// 封禁提示条（首页）。
struct BanBanner: View {
    @Environment(\.moonColors) private var c
    let desc: String

    var body: some View {
        MoonCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("账号已被封禁").fontWeight(.bold).foregroundStyle(c.onErrorContainer)
                Text(desc.isEmpty ? "封禁期间无法进行兑换 / 邀请 / 提现等操作。" : desc)
                    .font(.caption)
                    .foregroundStyle(c.onErrorContainer)
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c.errorContainer)
        )
        .padding(.horizontal, 16)
    }
}

/// 封禁时投递的只读页（问卷 / 兑换 / 邀请 / 提现）。
struct BannedScreen: View {
    @Environment(\.moonColors) private var c
    let reason: String
    let feature: String

    var body: some View {
        ScrollView {
            MoonCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(feature) 已停用")
                        .fontWeight(.bold)
                        .foregroundStyle(c.onErrorContainer)
                    Text(reason.isEmpty ? "账号已被封禁，无法进行该操作。" : reason)
                        .foregroundStyle(c.onErrorContainer)
                    Text("如需详情请联系 MoonBazaar 处理。")
                        .font(.caption)
                        .foregroundStyle(c.outline)
                }
                .padding(16)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(c.errorContainer)
            )
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 轻量 Toast（替代 Android 的 Toast）

private struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if let m = message, !m.isEmpty {
                Text(m)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.82)))
                    .padding(.bottom, 48)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .onAppear {
                        let shown = m
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            if message == shown { message = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: message)
    }
}

extension View {
    /// 在底部弹出一条短暂提示。
    func moonToast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

/// 复制到系统剪贴板（对应 Android 的 ClipboardManager）。
func copyToClipboard(_ text: String) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    UIPasteboard.general.string = text
}