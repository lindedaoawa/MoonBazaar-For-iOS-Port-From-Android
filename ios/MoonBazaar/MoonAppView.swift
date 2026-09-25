import SwiftUI

private enum Tab: String, CaseIterable, Identifiable {
    case home, surveys, tx, redeem, referral, withdraw

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "首页"
        case .surveys: return "问卷"
        case .tx: return "交易"
        case .redeem: return "兑换"
        case .referral: return "邀请"
        case .withdraw: return "提现"
        }
    }
}

/// 侧边抽屉 + 六个功能页。
/// 对应 Android `ui/MoonApp.kt` 的 `MoonApp`（Material3 `ModalNavigationDrawer` + `Scaffold`）。
///
/// iOS 没有 Material 的 ModalNavigationDrawer，这里用 `SideDrawer` 自绘：
/// 支持从屏幕左缘向右滑动拉开、在侧边栏上向左滑动收起；每次启动默认关闭。
struct MoonAppView: View {
    @ObservedObject var vm: MainViewModel
    let openUrl: (String) -> Void
    let onStartLogin: () -> Void

    @Environment(\.moonColors) private var c
    @State private var tab: Tab = .home
    @State private var drawerOpen = false

    private var current: Account? {
        vm.accounts.first { $0.key == vm.currentKey }
    }

    var body: some View {
        SideDrawer(isOpen: $drawerOpen) {
            VStack(spacing: 0) {
                appTopBar
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Color(.systemBackground))
        } drawer: {
            drawerContent
        }
        .onChange(of: vm.auth) { newValue in
            if newValue == .loggedIn { vm.reloadAll() }
        }
        .onChange(of: vm.ban.banned) { banned in
            if banned { vm.loadHome() }
        }
    }

    // MARK: - 顶栏

    private var appTopBar: some View {
        MoonBar {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { drawerOpen = true }
                } label: {
                    Text("☰  菜单").fontWeight(.bold)
                }
                Text(tab.label)
                    .font(.headline).fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 页面内容

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home:
            HomeView(vm: vm, onStartLogin: onStartLogin,
                     onOpenDrawer: { withAnimation { drawerOpen = true } })
        case .surveys:
            if vm.ban.banned {
                BannedScreen(reason: vm.ban.reason, feature: "问卷")
            } else {
                SurveysView(vm: vm)
            }
        case .tx:
            TransactionsView(vm: vm)
        case .redeem:
            if vm.ban.banned {
                BannedScreen(reason: vm.ban.reason, feature: "兑换")
            } else {
                RedeemView(vm: vm, openUrl: openUrl)
            }
        case .referral:
            if vm.ban.banned {
                BannedScreen(reason: vm.ban.reason, feature: "邀请")
            } else {
                ReferralView(vm: vm, openUrl: openUrl)
            }
        case .withdraw:
            if vm.ban.banned {
                BannedScreen(reason: vm.ban.reason, feature: "提现")
            } else {
                WithdrawView(vm: vm)
            }
        }
    }

    // MARK: - 抽屉

    private var drawerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 顶部：当前账号
                VStack(alignment: .leading, spacing: 2) {
                    Text("MoonBazaar").font(.title3).fontWeight(.bold)
                    Text(current?.displayName ?? "未登录")
                        .font(.subheadline)
                        .foregroundStyle(c.primary)
                    if let cur = current, !cur.uid.isEmpty {
                        Text("UID \(cur.uid)").font(.caption).foregroundStyle(c.outline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)

                Divider()
                Spacer().frame(height: 8)

                // 功能导航
                ForEach(Tab.allCases) { t in
                    DrawerItem(title: t.label, selected: tab == t) {
                        tab = t
                        closeDrawer()
                    }
                }

                Spacer().frame(height: 8)
                Divider()
                Spacer().frame(height: 8)

                Text("账户")
                    .font(.footnote).fontWeight(.medium)
                    .foregroundStyle(c.primary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 6)

                // 账户列表（点击切换）
                ForEach(vm.accounts) { a in
                    DrawerItem(
                        title: a.displayName,
                        subtitle: a.uid.isEmpty ? nil : "UID \(a.uid)",
                        selected: a.key == vm.currentKey
                    ) {
                        vm.switchAccount(a.key)
                        closeDrawer()
                    }
                }

                if vm.accounts.isEmpty {
                    Text("（暂无已登录账号）")
                        .font(.caption)
                        .foregroundStyle(c.outline)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 6)
                }

                DrawerItem(title: "＋ 添加账号", selected: false) {
                    onStartLogin()
                    closeDrawer()
                }

                if current != nil {
                    DrawerItem(title: "退出当前账号", selected: false) {
                        vm.logout()
                        closeDrawer()
                    }
                }

                Spacer().frame(height: 12)
            }
        }
    }

    private func closeDrawer() {
        withAnimation(.easeInOut(duration: 0.22)) { drawerOpen = false }
    }
}

// MARK: - 抽屉行

private struct DrawerItem: View {
    let title: String
    var subtitle: String? = nil
    let selected: Bool
    let action: () -> Void

    @Environment(\.moonColors) private var c

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(c.outline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? c.primary.opacity(0.16) : Color.clear)
            )
            .foregroundStyle(selected ? c.primary : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 自绘侧边抽屉

/// 轻量侧边抽屉：左侧边缘右滑打开，抽屉上左滑收起，点击遮罩关闭。
struct SideDrawer<Content: View, DrawerContent: View>: View {
    @Binding var isOpen: Bool
    @ViewBuilder var content: () -> Content
    @ViewBuilder var drawer: () -> DrawerContent

    private let duration: Double = 0.22

    var body: some View {
        GeometryReader { geo in
            let w = min(320, geo.size.width * 0.82)
            ZStack(alignment: .topLeading) {
                content()

                if isOpen {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: duration)) { isOpen = false }
                        }
                        .transition(.opacity)
                }

                drawer()
                    .frame(width: w, height: geo.size.height)
                    .background(Color(.systemBackground))
                    .offset(x: isOpen ? 0 : -w - 10)
                    .shadow(radius: isOpen ? 10 : 0)
                    .animation(.easeInOut(duration: duration), value: isOpen)
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onEnded { value in
                                if value.translation.width < -60 {
                                    withAnimation(.easeInOut(duration: duration)) { isOpen = false }
                                }
                            }
                    )
            }
            .overlay(alignment: .leading) {
                if !isOpen {
                    Color.clear
                        .frame(width: 18)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onEnded { value in
                                    if value.translation.width > 40 {
                                        withAnimation(.easeInOut(duration: duration)) { isOpen = true }
                                    }
                                }
                        )
                }
            }
        }
    }
}