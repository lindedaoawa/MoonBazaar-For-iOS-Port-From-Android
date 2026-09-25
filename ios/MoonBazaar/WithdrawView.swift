import SwiftUI

// =============================== 提现（卡片）
/// 对应 Android `MoonApp.kt` 的 `WithdrawScreen`。
struct WithdrawView: View {
    @ObservedObject var vm: MainViewModel
    @Environment(\.moonColors) private var c

    @State private var selected: Int64 = -1
    @State private var amount = ""
    @State private var delivery = ""
    @State private var note = ""

    private var chosen: WithdrawProduct? {
        vm.products.first { $0.id == selected }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("提现")
                        .font(.title2).fontWeight(.bold)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    if vm.products.isEmpty {
                        Text(vm.withdrawMsg.isEmpty ? "加载中…" : vm.withdrawMsg)
                            .foregroundStyle(c.outline)
                            .padding(.horizontal, 16)
                    } else {
                        ForEach(vm.products) { p in
                            WithdrawCard(p: p, isSelected: p.id == selected) {
                                selected = p.id
                            }
                        }
                    }
                    Spacer().frame(height: 16)
                }
            }

            Divider()

            if let chosen = chosen {
                form(for: chosen)
            }
        }
    }

    @ViewBuilder
    private func form(for chosen: WithdrawProduct) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                chosen.pricingType == "rate"
                    ? "金额 / 数量"
                    : "固定价格 \(chosen.fixedCostGc) GC，无需输入金额",
                text: $amount
            )
            .textFieldStyle(.roundedBorder)
            .keyboardType(.decimalPad)
            .disabled(chosen.pricingType != "rate")

            TextField(chosen.deliveryFieldZh.isEmpty ? "接收信息" : chosen.deliveryFieldZh,
                      text: $delivery)
                .textFieldStyle(.roundedBorder)

            TextField("备注 (可选)", text: $note)
                .textFieldStyle(.roundedBorder)

            Button("提交提现 ▸ \(chosen.labelZh)") {
                vm.submitWithdrawal(chosen, amount: amount, delivery: delivery, note: note)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)

            if !vm.withdrawMsg.isEmpty {
                Text(vm.withdrawMsg)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(c.outline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
    }
}

private struct WithdrawCard: View {
    let p: WithdrawProduct
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.moonColors) private var c

    private var costLine: String {
        if p.pricingType == "rate" {
            return (p.gcPerUnit.isEmpty ? "按量计价" : p.gcPerUnit) + "/单位"
        }
        return "\(p.fixedCostGc.isEmpty ? "?" : p.fixedCostGc) GC"
    }

    var body: some View {
        MoonCard(selected: isSelected) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.labelZh.isEmpty ? "无名称" : p.labelZh)
                            .fontWeight(.semibold)
                        Text(p.methodZh.isEmpty ? "—" : p.methodZh)
                            .font(.caption2)
                            .foregroundStyle(c.outline)
                    }
                    Spacer()
                    Text(costLine)
                        .fontWeight(.bold)
                        .foregroundStyle(c.primary)
                }
                if !p.descriptionText.isEmpty {
                    Text(p.descriptionText).font(.caption).foregroundStyle(c.outline)
                }
                HStack(spacing: 8) {
                    if !p.deliveryFieldZh.isEmpty {
                        MoonTag(text: "接收: \(p.deliveryFieldZh)")
                    }
                    if !p.apiOk {
                        MoonTag(text: "需官网")
                    }
                }
                Spacer().frame(height: 2)
                Button(isSelected ? "已选择" : "选择并填写", action: onSelect)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            .padding(12)
        }
        .padding(.horizontal, 16)
    }
}