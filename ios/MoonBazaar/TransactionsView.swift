import SwiftUI

// =============================== 交易流水（分页）
/// 对应 Android `MoonApp.kt` 的 `TransactionsScreen`。
struct TransactionsView: View {
    @ObservedObject var vm: MainViewModel
    @Environment(\.moonColors) private var c

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("交易流水").font(.title2).fontWeight(.bold)
                    Text(vm.tx.message).font(.caption).foregroundStyle(c.outline)
                }
                Spacer()
                if !vm.tx.records.isEmpty {
                    Button("刷新") { vm.loadTransactions(0) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(16)

            if vm.tx.records.isEmpty {
                Spacer().frame(height: 24)
                Text(vm.tx.loading ? "加载中…" : (vm.tx.message.isEmpty ? "暂无流水" : vm.tx.message))
                    .font(.subheadline)
                    .foregroundStyle(c.outline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.tx.records) { rec in
                            TxCardRow(rec: rec)
                        }
                        footer
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        Text(footerText)
            .font(.caption)
            .foregroundStyle(c.outline)
            .frame(maxWidth: .infinity)
            .padding(8)
            .onAppear {
                // 滚动到底部时加载下一页
                if vm.tx.hasMore && !vm.tx.loading {
                    vm.loadTransactions(vm.tx.records.count)
                }
            }
    }

    private var footerText: String {
        if vm.tx.loading { return "加载中…" }
        if vm.tx.hasMore { return "继续下滑加载更多" }
        return "已全部加载 (\(vm.tx.total))"
    }
}

private struct TxCardRow: View {
    let rec: TransactionRecord
    @Environment(\.moonColors) private var c

    var body: some View {
        MoonCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.typeName.isEmpty ? "交易" : rec.typeName)
                            .fontWeight(.semibold)
                        Text(rec.createdAt)
                            .font(.caption2)
                            .foregroundStyle(c.outline)
                    }
                    Spacer()
                    Text(rec.displayAmount)
                        .fontWeight(.bold)
                        .foregroundStyle(rec.isGain ? c.gain : c.loss)
                }
                if !rec.description.isEmpty {
                    Text(rec.description)
                        .font(.caption)
                        .foregroundStyle(c.outline)
                }
            }
            .padding(12)
        }
        .padding(.horizontal, 12)
    }
}