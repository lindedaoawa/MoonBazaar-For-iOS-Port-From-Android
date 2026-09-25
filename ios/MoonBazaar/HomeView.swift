import SwiftUI

// =============================== 首页
/// 对应 Android `MoonApp.kt` 的 `HomeScreen`。
struct HomeView: View {
    @ObservedObject var vm: MainViewModel
    let onStartLogin: () -> Void
    let onOpenDrawer: () -> Void

    @Environment(\.moonColors) private var c

    private var loggedIn: Bool { vm.auth == .loggedIn }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                sessionBar
                if vm.home.account.isBanned {
                    BanBanner(desc: vm.home.account.banReason)
                    Spacer().frame(height: 8)
                }
                accountCard
                Spacer().frame(height: 40)
            }
        }
        // refreshable 的 action 是 @Sendable 的异步闭包（非 MainActor），
        // 而 loadHome() 是同步的 MainActor 方法，因此显式切回主线程调用。
        .refreshable { await MainActor.run { vm.loadHome() } }
    }

    // hero：渐变背景 + 可用 GC
    private var hero: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MoonBazaar")
                        .font(.title2).fontWeight(.bold)
                        .foregroundStyle(c.onPrimary)
                    Text("登录 · 兑换 · 邀请 · 提现")
                        .font(.caption)
                        .foregroundStyle(c.onPrimary.opacity(0.9))
                }
                Spacer(minLength: 12)
                Text(vm.home.gc)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(c.onPrimary)
            }
            HStack {
                Spacer()
                Text("可用 GC")
                    .font(.caption2)
                    .foregroundStyle(c.onPrimary.opacity(0.9))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(MoonTheme.heroGradient(c))
    }

    // session bar：登录态 + 操作按钮
    private var sessionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vm.authNote.isEmpty ? (loggedIn ? "已登录" : "未登录") : vm.authNote)
                .font(.subheadline)
                .foregroundStyle(loggedIn ? Color.primary : c.error)
            HStack(spacing: 8) {
                if !loggedIn {
                    Button("登录", action: onStartLogin)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("刷新") { vm.loadHome() }
                        .buttonStyle(.bordered)
                    Button("切换账号", action: onOpenDrawer)
                        .buttonStyle(.bordered)
                    Button("登出") { vm.logout() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // 账户信息（仅登录后展示，避免登出后残留上一个账号的内容）
    private var accountCard: some View {
        MoonCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("账户信息")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(c.primary)
                if !loggedIn {
                    Text("登录后可查看账号信息。")
                        .font(.subheadline)
                        .foregroundStyle(c.outline)
                } else {
                    FieldRow(label: "用户名", value: vm.home.account.username)
                    FieldRow(label: "UID", value: vm.home.account.uid)
                    FieldRow(label: "绑定邮箱", value: vm.home.account.emailMasked)
                    FieldRow(label: "状态", value: vm.home.account.status)
                    FieldRow(label: "注册时间", value: vm.home.account.registeredAt)
                }
            }
            .padding(14)
        }
        .padding(.horizontal, 16)
    }
}