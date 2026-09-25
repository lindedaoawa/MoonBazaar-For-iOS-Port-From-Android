import SwiftUI

// =============================== 主要问卷
/// 对应 Android `MoonApp.kt` 的 `SurveysScreen`。
struct SurveysView: View {
    @ObservedObject var vm: MainViewModel
    @Environment(\.moonColors) private var c

    /// 进行中的问卷：非空时在该页内以内嵌 WebView 打开。
    @State private var activeSurvey: String?

    var body: some View {
        if let running = activeSurvey {
            SurveyWebScreen(startUrl: running) {
                activeSurvey = nil
                vm.loadSurveys()
            }
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("主要问卷").font(.title2).fontWeight(.bold)
                    Text(vm.surveys.message).font(.caption).foregroundStyle(c.outline)
                }
                Spacer()
                Button("刷新") { vm.loadSurveys() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(16)

            qualityCard
                .padding(.horizontal, 16)

            Spacer().frame(height: 10)

            if vm.surveys.surveys.isEmpty {
                Text(vm.surveys.loading ? "加载中…" : (vm.surveys.message.isEmpty ? "暂无可做问卷" : vm.surveys.message))
                    .font(.subheadline)
                    .foregroundStyle(c.outline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.surveys.surveys) { item in
                            SurveyCard(item: item) { url in activeSurvey = url }
                        }
                        Spacer().frame(height: 24)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var qualityCard: some View {
        MoonCard {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("质量分").font(.caption).foregroundStyle(c.outline)
                    Text("\(vm.surveys.qualityScore)")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(c.primary)
                }
                Spacer()
                if !vm.surveys.countryCode.isEmpty {
                    Text("地区 \(vm.surveys.countryCode)")
                        .font(.caption)
                        .foregroundStyle(c.outline)
                }
            }
            .padding(14)
        }
    }
}

private struct SurveyCard: View {
    let item: SurveyItem
    let onStart: (String) -> Void

    @Environment(\.moonColors) private var c

    var body: some View {
        MoonCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.provider.isEmpty ? "未知提供商" : item.provider)
                            .fontWeight(.semibold)
                        Text("ID \(item.surveyId.isEmpty ? "—" : item.surveyId)")
                            .font(.caption2)
                            .foregroundStyle(c.outline)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(item.reward) GC")
                            .fontWeight(.bold)
                            .foregroundStyle(c.primary)
                        Text("时长 \(item.loi.isEmpty ? "—" : item.loi)")
                            .font(.caption2)
                            .foregroundStyle(c.outline)
                    }
                }
                if !item.url.isEmpty {
                    Button("开始问卷") { onStart(item.url) }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
        }
        .padding(.horizontal, 12)
    }
}