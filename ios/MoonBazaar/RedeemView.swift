import SwiftUI

// =============================== 兑换
/// 对应 Android `MoonApp.kt` 的 `RedeemScreen`。
struct RedeemView: View {
    @ObservedObject var vm: MainViewModel
    let openUrl: (String) -> Void

    @Environment(\.moonColors) private var c
    @State private var code = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("兑换码").font(.title2).fontWeight(.bold)
                Spacer().frame(height: 6)
                Text("兑换结果若返回官方确认页，请在浏览器打开并确认后才能入账。")
                    .font(.subheadline)
                    .foregroundStyle(c.outline)
                Spacer().frame(height: 14)

                TextField("如 MOON-1234", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .disabled(vm.redeem.submitting)

                Spacer().frame(height: 12)
                Button(vm.redeem.submitting ? "提交中…" : "兑换") {
                    vm.redeem(code: code)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || vm.redeem.submitting)

                if vm.redeem.submitting || vm.redeem.done {
                    Spacer().frame(height: 16)
                    resultCard
                }
                Spacer().frame(height: 40)
            }
            .padding(16)
        }
    }

    private var resultCard: some View {
        MoonCard {
            VStack(alignment: .leading, spacing: 6) {
                if vm.redeem.submitting {
                    Text("处理中…").fontWeight(.bold)
                } else if vm.redeem.done && vm.redeem.okHttp {
                    Text("✅ 已受理" + (vm.redeem.confirmationUrl.isEmpty ? "" : "，需在官方确认页确认"))
                        .fontWeight(.bold)
                    if !vm.redeem.confirmationUrl.isEmpty {
                        Button("打开官方确认页") { openUrl(vm.redeem.confirmationUrl) }
                            .buttonStyle(.bordered)
                    }
                } else if vm.redeem.done {
                    Text("❌ \(vm.redeem.error.isEmpty ? "兑换失败" : vm.redeem.error)")
                        .foregroundStyle(c.error)
                }
                if vm.redeem.done && !vm.redeem.body.isEmpty {
                    JsonBox(title: "原始返回", text: vm.redeem.body)
                }
            }
            .padding(12)
        }
    }
}