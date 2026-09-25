import SwiftUI

// =============================== 邀请
/// 对应 Android `MoonApp.kt` 的 `ReferralScreen`。
struct ReferralView: View {
    @ObservedObject var vm: MainViewModel
    let openUrl: (String) -> Void

    @Environment(\.moonColors) private var c
    @State private var toast: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text("邀请好友").font(.title2).fontWeight(.bold)
                    Spacer()
                    Button("刷新") { vm.loadReferral() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if !vm.referral.message.isEmpty {
                    Spacer().frame(height: 4)
                    Text(vm.referral.message).font(.caption).foregroundStyle(c.error)
                }

                // 统计
                Spacer().frame(height: 12)
                HStack(spacing: 10) {
                    statCard(title: "总邀请人数", value: "\(vm.referral.totalInvites)")
                    statCard(title: "累计佣金 (GC)",
                             value: vm.referral.commissionEarnedGc.isEmpty ? "0" : vm.referral.commissionEarnedGc)
                }

                // 邀请链接
                Spacer().frame(height: 18)
                Text("我的邀请链接").font(.headline)
                Spacer().frame(height: 6)
                if vm.referral.uidLink.isEmpty {
                    Text("（暂无数据，请先登录或稍后重试）")
                        .font(.caption).foregroundStyle(c.outline)
                } else {
                    LinkBox(link: vm.referral.uidLink)
                    Spacer().frame(height: 6)
                    HStack(spacing: 8) {
                        Button("复制链接") { doCopy(vm.referral.uidLink) }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        Button("在浏览器打开") { openUrl(vm.referral.uidLink) }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }
                }

                // 自定义链接（可能未设置）
                Spacer().frame(height: 14)
                Text("自定义邀请链接").font(.headline)
                Spacer().frame(height: 6)
                if vm.referral.customLink.isEmpty {
                    Text("未设置自定义邀请链接（可用上方默认链接）")
                        .font(.caption).foregroundStyle(c.outline)
                } else {
                    if !vm.referral.customCode.isEmpty {
                        Text("邀请码：\(vm.referral.customCode)")
                            .font(.subheadline).fontWeight(.medium)
                        Spacer().frame(height: 4)
                    }
                    LinkBox(link: vm.referral.customLink)
                    Spacer().frame(height: 6)
                    Button("复制自定义链接") { doCopy(vm.referral.customLink) }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }

                // 明细
                Spacer().frame(height: 20)
                Text("邀请明细 (\(vm.referral.invites.count)/\(vm.referral.totalInvites))")
                    .font(.headline)
                Spacer().frame(height: 6)
                if vm.referral.invites.isEmpty {
                    Text(vm.referral.loading ? "加载中…" : "暂无邀请记录")
                        .font(.caption).foregroundStyle(c.outline)
                } else {
                    ForEach(vm.referral.invites) { inv in
                        InviteeCard(inv: inv)
                        Spacer().frame(height: 8)
                    }
                }
                Spacer().frame(height: 40)
            }
            .padding(16)
        }
        .moonToast($toast)
    }

    private func statCard(title: String, value: String) -> some View {
        MoonCard {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(c.outline)
                Text(value)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(c.primary)
            }
            .padding(14)
        }
    }

    private func doCopy(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        copyToClipboard(text)
        toast = "已复制"
    }
}

private struct InviteeCard: View {
    let inv: InviteeRow
    @Environment(\.moonColors) private var c

    var body: some View {
        MoonCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(inv.username.isEmpty ? "（未知用户）" : inv.username)
                            .fontWeight(.semibold)
                        Text(inv.createdAt)
                            .font(.caption2)
                            .foregroundStyle(c.outline)
                    }
                    Spacer()
                    Text("\(inv.totalEarnedGc) GC")
                        .fontWeight(.bold)
                        .foregroundStyle(c.primary)
                }
                if inv.isBanned || inv.milestoneAwarded {
                    HStack(spacing: 8) {
                        if inv.milestoneAwarded {
                            Text("里程碑奖励已发放").font(.caption2).foregroundStyle(c.gain)
                        }
                        if inv.isBanned {
                            Text("该用户已被封禁").font(.caption2).foregroundStyle(c.error)
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}