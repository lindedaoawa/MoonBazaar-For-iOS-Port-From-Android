import Foundation
import Combine

// MARK: - 会话状态

enum AuthUi: Equatable {
    case unknown
    case loggedOut
    case loggedIn
}

/// 账号信息（GET /proxy/account/status）。
struct AccountInfo {
    var uid: String = ""
    var username: String = ""
    var emailMasked: String = ""
    var emailVerified: Bool = true
    var status: String = ""
    var registeredAt: String = ""
    var isBanned: Bool = false
    var banReason: String = ""
}

/// 首页 hero。
struct HomeUi {
    var loading: Bool = false
    var gc: String = "—"
    var account: AccountInfo = AccountInfo()
}

struct BanState {
    var banned: Bool = false
    var reason: String = ""
}

/// 交易流水一条（金额保留原始小数，不做取整）。
struct TransactionRecord: Identifiable {
    var id = UUID()
    var createdAt: String = ""
    var typeName: String = ""
    var description: String = ""
    var amountText: String = "0"
    var isGain: Bool = true

    /// 展示用：正数补 "+"，负数原样（本身带 "-"）。
    var displayAmount: String {
        if isGain && !amountText.hasPrefix("+") { return "+\(amountText)" }
        return amountText
    }
}

/// 提现商品卡。
struct WithdrawProduct: Identifiable {
    var id: Int64
    var methodZh: String
    var labelZh: String
    var categoryZh: String
    var descZh: String
    var unitZh: String
    var deliveryFieldZh: String
    var pricingType: String          // fixed | rate
    var fixedCostGc: String          // 空串则按 rate
    var gcPerUnit: String
    var minimumAmount: String
    var maximumAmount: String
    var apiOk: Bool
    var rawText: String

    var descriptionText: String {
        if descZh.isEmpty && categoryZh.isEmpty { return "" }
        var s = ""
        if !categoryZh.isEmpty { s += "[\(categoryZh)] " }
        s += descZh
        return s
    }

    var costLine: String {
        if pricingType == "rate" {
            return (gcPerUnit.isEmpty ? "按量计价" : gcPerUnit) + "/单位"
        }
        return "\(fixedCostGc.isEmpty ? "?" : fixedCostGc) GC"
    }
}

/// 问卷一条。
struct SurveyItem: Identifiable {
    var id = UUID()
    var provider: String = ""      // 展示用：提供商全名（provider_full，如 "CPX Research"）
    var providerKey: String = ""   // 原始 provider 字段（如 "cpx"），用于 provider_status 过滤
    var surveyId: String = ""
    var reward: String = "0"       // 单位 GC
    var loi: String = ""           // 问卷时长
    var url: String = ""
}

/// 主要问卷页面状态。
struct SurveysUiState {
    var loading: Bool = false
    var message: String = ""
    var countryCode: String = ""
    var qualityScore: Int = 0
    var surveys: [SurveyItem] = []
}

/// 兑换页状态。
struct RedemptionUiState {
    var submitting: Bool = false
    var done: Bool = false
    var okHttp: Bool = false
    var confirmationUrl: String = ""
    var error: String = ""
    var note: String = ""
    var body: String = ""
}

/// 邀请明细一行。
struct InviteeRow: Identifiable {
    var id: Int64 = 0
    var username: String = ""
    var createdAt: String = ""
    var isBanned: Bool = false
    var totalEarnedGc: String = "0"
    var milestoneAwarded: Bool = false
}

/// 邀请页状态。
struct ReferralUiState {
    var loading: Bool = false
    var message: String = ""
    var totalInvites: Int = 0
    var commissionEarnedGc: String = "0"
    var invites: [InviteeRow] = []
    var uidLink: String = ""       // 数值邀请链接（必有）
    var customCode: String = ""    // 自定义邀请码（可能未设置）
    var customLink: String = ""    // 自定义链接（可能未设置）
}

/// 交易页状态（分页）。
struct TxUi {
    var loading: Bool = false
    var records: [TransactionRecord] = []
    var total: Int = 0
    var limit: Int = 25
    var hasMore: Bool = false
    var message: String = ""
}

// MARK: - ViewModel

/// 全部界面状态与数据加载逻辑（对应 Android 的 `ui/MainViewModel.kt`）。
///
/// Android 的 `MainViewModel` 自己也持有 `accounts` / `currentKey` 两个 StateFlow；
/// iOS 侧把账号存储统一放在 `Session`（单例）里，这里通过转发 `objectWillChange`
/// 把 `Session` 的变化一并广播出去，视图只观察 `vm` 即可。
@MainActor
final class MainViewModel: ObservableObject {

    @Published var auth: AuthUi = .unknown
    @Published var authNote: String = ""
    @Published var home = HomeUi()
    @Published var ban = BanState()
    @Published var tx = TxUi()
    @Published var redeem = RedemptionUiState()
    @Published var referral = ReferralUiState()
    @Published var products: [WithdrawProduct] = []
    @Published var withdrawMsg: String = ""
    @Published var surveys = SurveysUiState()

    /// 账号存储（切换账号 / 登出等都在这里）。
    let session = Session.shared

    /// 便捷透传，保持与 Android 端 `vm.accounts` / `vm.currentKey` 一致的用法。
    var accounts: [Account] { session.accounts }
    var currentKey: String? { session.currentKey }

    private var bag = Set<AnyCancellable>()

    // 单次请求条数安全上限：total 超过它时回退为多页加载。
    private let txCap = 500
    private let refCap = 500

    init() {
        // 把 Session 的变化转发给观察 vm 的视图
        Session.shared.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)

        refreshAuthState()
        loadHome()
        loadSurveys()
        loadTransactions(0)
        loadReferral()
        loadProducts()
    }

    // MARK: - 会话

    func refreshAuthState() {
        authNote = "检查会话…"
        Task {
            let (s, err) = await MoonRepository.status()
            if s == nil {
                auth = .loggedOut
                authNote = err.isEmpty ? "无法获取会话" : err
            } else if !(s!.sessionValid) || !(s!.hasTokens) {
                auth = .loggedOut
                authNote = s!.sessionValid ? "已有会话，尚无用户令牌" : "会话无效，请登录"
            } else {
                auth = .loggedIn
                authNote = "已登录"
            }
        }
    }

    /// 清空所有与账号相关的界面数据（切换账号 / 登出时必须调用）。
    private func clearAccountUiState(_ note: String) {
        home = HomeUi()
        ban = BanState()
        tx = TxUi()
        redeem = RedemptionUiState()
        referral = ReferralUiState()
        products = []
        withdrawMsg = ""
        surveys = SurveysUiState()
        authNote = note
    }

    /// 重新拉取当前账号的全部数据。
    func reloadAll() {
        loadHome()
        loadSurveys()
        loadTransactions(0)
        loadReferral()
        loadProducts()
    }

    /// 退出当前账号：吊销服务端 session 并移除本地该账号；若还有其它账号则自动切过去。
    func logout() {
        let key = Session.shared.currentKey
        Task {
            _ = await MoonRepository.logout()   // 尽力吊销当前账号的 Worker session
            if let key = key {
                Session.shared.removeByKey(key)
            } else {
                Session.shared.clear()
            }
            clearAccountUiState("未登录")
            if Session.shared.currentKey != nil {
                refreshAuthState()
                reloadAll()
            } else {
                auth = .loggedOut
            }
        }
    }

    /// 切换到指定账号（uid key）。
    func switchAccount(_ key: String) {
        guard key != Session.shared.currentKey else { return }
        Session.shared.selectByKey(key)
        clearAccountUiState("正在切换账号…")
        auth = .unknown
        refreshAuthState()
        reloadAll()
    }

    /// 移除指定账号；若移除的是当前账号会自动切换到其它账号。
    func removeAccount(_ key: String) {
        let wasCurrent = key == Session.shared.currentKey
        Session.shared.removeByKey(key)
        guard wasCurrent else { return }
        clearAccountUiState("已移除该账号")
        if Session.shared.currentKey != nil {
            auth = .unknown
            refreshAuthState()
            reloadAll()
        } else {
            auth = .loggedOut
        }
    }

    // MARK: - 首页

    func loadHome() {
        guard Session.shared.isValid else { return }
        home.loading = true
        Task {
            let (acct, _) = await MoonRepository.accountStatus()
            let (bal, _) = await MoonRepository.accountBalance()
            let avail = findVal(bal, ["available", "available_gascoin", "balance", "gascoin"])
            let acctData = J.dict(sub(acct, "data")) ?? acct
            let banned = J.bool(acctData, "is_banned", false)
            var banReason = J.str(acctData, "ban_reason")
            if banReason.isEmpty && banned { banReason = "账号已被封禁" }
            let info = AccountInfo(
                uid: J.str(acctData, "uid"),
                username: J.str(acctData, "username"),
                emailMasked: J.str(acctData, "email_masked"),
                emailVerified: J.bool(acctData, "email_verified", true),
                status: J.str(acctData, "status"),
                registeredAt: J.str(acctData, "registered_at"),
                isBanned: banned,
                banReason: banReason
            )
            ban = BanState(banned: banned, reason: info.banReason)
            home = HomeUi(loading: false, gc: MoonRepository.gcInteger(avail), account: info)
            // 回填账号信息（uid / username），用于账号列表显示
            if !info.uid.isEmpty {
                Session.shared.identify(uid: info.uid, username: info.username)
            }
        }
    }

    // MARK: - 交易流水（动态 limit：先探测 total，再按总数拉取）

    /// - Parameter offset: 偏移。传 0 表示「刷新」：先用 limit=1 探测 total，
    ///   再用 `limit = min(total, txCap)` 拉取记录。
    func loadTransactions(_ offset: Int = 0) {
        guard Session.shared.isValid else { return }
        if ban.banned {
            tx = TxUi(message: ban.reason.isEmpty ? "账号已封禁，无法查看" : ban.reason)
            return
        }
        let cur = tx
        if offset > 0 && (cur.loading || !cur.hasMore) { return }
        tx.loading = true
        if offset == 0 { tx.message = "正在获取记录总数…" }

        Task {
            // ① 探测请求：拿总数
            var total = cur.total
            if offset == 0 {
                let (probe, probeErr) = await MoonRepository.transactions(limit: 1, offset: 0)
                let pd = J.dict(sub(probe, "data")) ?? probe
                guard let pd = pd else {
                    tx = TxUi(message: probeErr.isEmpty ? "无法获取交易记录" : probeErr)
                    return
                }
                total = J.int(pd, "total", 0)
                if total <= 0 {
                    tx = TxUi(message: "暂无交易记录")
                    return
                }
            }

            // ② 正式请求：limit = min(total, 上限)；翻页时沿用同一页大小
            let pageSize = offset == 0 ? min(total, txCap) : cur.limit
            let (data, err) = await MoonRepository.transactions(limit: pageSize, offset: offset)
            let d = J.dict(sub(data, "data")) ?? data
            guard let records = J.arr(sub(d, "records")) else {
                tx.loading = false
                tx.message = err.isEmpty ? "暂无交易数据" : err
                return
            }
            let list: [TransactionRecord] = records.map { raw in
                let j = J.dict(raw) ?? [:]
                let amountRaw = j["amount_gc"]
                let amountText = numText(amountRaw).isEmpty ? "0" : numText(amountRaw)
                let gain = J.anyDouble(amountRaw).map { $0 >= 0 } ?? true
                return TransactionRecord(
                    createdAt: J.str(j, "created_at"),
                    typeName: J.str(j, "type_name"),
                    description: J.str(j, "description"),
                    amountText: amountText,
                    isGain: gain
                )
            }
            let combined = offset == 0 ? list : cur.records + list
            tx = TxUi(loading: false, records: combined, total: total,
                      limit: pageSize, hasMore: combined.count < total,
                      message: "共 \(total) 条记录")
        }
    }

    // MARK: - 兑换

    func redeem(code: String) {
        let b = ban
        if b.banned {
            redeem = RedemptionUiState(done: true, okHttp: false,
                                       error: b.reason.isEmpty ? "账号已封禁，无法兑换" : b.reason)
            return
        }
        guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        redeem = RedemptionUiState(submitting: true)
        Task {
            let r = await MoonRepository.redeemCode(code)
            let dataObj = J.dict(sub(r.json, "data"))
            let confirmation = J.str(dataObj, "confirmation_url").isEmpty
                ? J.str(r.json, "confirmation_url")
                : J.str(dataObj, "confirmation_url")
            if r.okHttp {
                redeem = RedemptionUiState(done: true, okHttp: true, confirmationUrl: confirmation,
                                           note: confirmation.isEmpty ? "受理成功" : "已受理，请打开官方确认页完成兑换",
                                           body: r.body)
            } else {
                redeem = RedemptionUiState(done: true, okHttp: false,
                                           error: r.errorMsg.isEmpty ? "HTTP \(r.http)" : r.errorMsg,
                                           body: r.body)
            }
        }
    }

    func resetRedeem() { redeem = RedemptionUiState() }

    // MARK: - 邀请

    func loadReferral() {
        guard Session.shared.isValid else { return }
        if ban.banned {
            referral = ReferralUiState(message: ban.reason.isEmpty ? "账号已封禁，无法查看" : ban.reason)
            return
        }
        referral.loading = true
        Task {
            // 邀请链接（uid_link 必有；custom_link 可能未设置）
            let (linkData, linkErr) = await MoonRepository.referralLink()
            let ld = J.dict(sub(linkData, "data")) ?? linkData
            let uidLink = J.str(ld, "uid_link")
            let customCode = J.str(ld, "custom_code")
            let customLink = J.str(ld, "custom_link")

            // 邀请统计 + 明细（先探测总数再按总数拉取）
            var invites: [InviteeRow] = []
            var totalInvites = 0
            var commission = ""
            var listErrMsg = ""

            let (probe, probeErr) = await MoonRepository.referrals(limit: 1, offset: 0)
            let pd = J.dict(sub(probe, "data")) ?? probe
            if let pd = pd {
                totalInvites = J.int(pd, "total_invites", 0)
                commission = numText(pd["commission_earned_gc"])
                if totalInvites > 0 {
                    let pageSize = min(totalInvites, refCap)
                    let (listData, listErr) = await MoonRepository.referrals(limit: pageSize, offset: 0)
                    let d = J.dict(sub(listData, "data")) ?? listData
                    if let arr = J.arr(sub(d, "invites")) {
                        for raw in arr {
                            let j = J.dict(raw) ?? [:]
                            invites.append(InviteeRow(
                                id: J.int64(j, "id"),
                                username: J.str(j, "username"),
                                createdAt: J.str(j, "created_at"),
                                isBanned: J.bool(j, "is_banned", false),
                                totalEarnedGc: numText(j["total_earned_gc"]),
                                milestoneAwarded: J.bool(j, "milestone_awarded", false)
                            ))
                        }
                    } else {
                        listErrMsg = listErr.isEmpty ? "邀请明细为空" : listErr
                    }
                }
            } else {
                listErrMsg = probeErr.isEmpty ? "无法获取邀请数据" : probeErr
            }
            if listErrMsg.isEmpty && !linkErr.isEmpty { listErrMsg = linkErr }

            referral = ReferralUiState(
                loading: false,
                message: listErrMsg,
                totalInvites: totalInvites,
                commissionEarnedGc: commission.isEmpty ? "0" : commission,
                invites: invites,
                uidLink: uidLink,
                customCode: customCode,
                customLink: customLink
            )
        }
    }

    // MARK: - 主要问卷

    func loadSurveys() {
        guard Session.shared.isValid else { return }
        if ban.banned {
            surveys = SurveysUiState(message: ban.reason.isEmpty ? "账号已封禁，无法查看问卷" : ban.reason)
            return
        }
        surveys.loading = true
        surveys.message = ""
        Task {
            let (data, err) = await MoonRepository.surveys()
            let d = J.dict(sub(data, "data")) ?? data
            guard let d = d else {
                surveys = SurveysUiState(loading: false, message: err.isEmpty ? "无法获取问卷" : err)
                return
            }
            let country = J.str(d, "country_code")
            let quality = J.int(d, "quality_score", 0)

            // provider_status: { "cpx": true, ... } —— 为 false 的提供商问卷不显示
            let statusObj = J.dict(d["provider_status"])
            func providerEnabled(_ p: String) -> Bool {
                guard let statusObj = statusObj else { return true }
                for (k, v) in statusObj where k.lowercased() == p.lowercased() {
                    return J.anyBool(v) ?? true
                }
                return true   // 未列出的提供商不隐藏
            }

            var list: [SurveyItem] = []
            if let arr = J.arr(d["surveys"]) {
                for raw in arr {
                    let j = J.dict(raw) ?? [:]
                    // 过滤用原始 key（provider_status 里的键，如 "cpx"）
                    let providerKey = J.str(j, "provider")
                    if !providerEnabled(providerKey) { continue }
                    // 展示用全名：provider_full（如 "CPX Research"），缺失时回退原始值
                    let providerName = J.str(j, "provider_full").isEmpty
                        ? providerKey : J.str(j, "provider_full")
                    // 真实字段：id / payout / link；同时对示例里的旧键名做兜底
                    let payout: Any? = j["payout"] ?? j["reward"]
                    let surveyId = j["id"].map { J.anyStr($0) } ?? J.anyStr(j["survey_id"])
                    let link = J.str(j, "link").isEmpty ? J.str(j, "url") : J.str(j, "link")
                    list.append(SurveyItem(
                        provider: providerName,
                        providerKey: providerKey,
                        surveyId: surveyId,
                        reward: numText(payout).isEmpty ? "0" : numText(payout),
                        loi: numText(j["loi"]),
                        url: link
                    ))
                }
            }
            surveys = SurveysUiState(
                loading: false,
                message: list.isEmpty ? "当前没有可做的问卷" : "共 \(list.count) 份可做问卷",
                countryCode: country,
                qualityScore: quality,
                surveys: list
            )
        }
    }

    // MARK: - 提现商品

    func loadProducts() {
        guard Session.shared.isValid else { return }
        if ban.banned {
            products = []
            withdrawMsg = ban.reason.isEmpty ? "账号已封禁，无法提现" : ban.reason
            return
        }
        Task {
            withdrawMsg = "加载中…"
            let (data, err) = await MoonRepository.products()
            let d = J.dict(sub(data, "data")) ?? data
            guard let methods = J.arr(sub(d, "methods")) else {
                products = []
                withdrawMsg = err.isEmpty ? prettyJSON(d) : err
                if withdrawMsg.isEmpty { withdrawMsg = "无提现产品" }
                return
            }
            var out: [WithdrawProduct] = []
            for m in methods {
                let method = J.dict(m) ?? [:]
                let methodZh = text(method, "name")
                let apiOk = J.bool(method, "api_withdraw_supported", true)
                guard let productsArr = J.arr(method["products"]) else { continue }
                for raw in productsArr {
                    let j = J.dict(raw) ?? [:]
                    let pricing = J.str(j, "pricing_type").isEmpty ? "fixed" : J.str(j, "pricing_type")
                    out.append(WithdrawProduct(
                        id: J.int64(j, "id"),
                        methodZh: methodZh,
                        labelZh: text(j, "label"),
                        categoryZh: text(j, "category"),
                        descZh: text(j, "description"),
                        unitZh: text(j, "unit"),
                        deliveryFieldZh: text(j, "delivery_field"),
                        pricingType: pricing,
                        fixedCostGc: numStr(j, "fixed_cost_gc"),
                        gcPerUnit: numStr(j, "gc_per_unit"),
                        minimumAmount: numStr(j, "minimum_amount"),
                        maximumAmount: numStr(j, "maximum_amount"),
                        apiOk: apiOk,
                        rawText: prettyJSON(j)
                    ))
                }
            }
            products = out
            withdrawMsg = out.isEmpty ? "（暂无可用提现产品）" : "共 \(out.count) 个可提现产品"
        }
    }

    func submitWithdrawal(_ product: WithdrawProduct?, amount: String, delivery: String, note: String) {
        guard let product = product, product.id > 0 else {
            withdrawMsg = "请选择一个提现产品。"
            return
        }
        if ban.banned {
            withdrawMsg = "❌ \(ban.reason.isEmpty ? "账号已封禁，无法提现" : ban.reason)"
            return
        }
        if delivery.trimmingCharacters(in: .whitespaces).isEmpty {
            withdrawMsg = "需填写\(product.deliveryFieldZh.isEmpty ? "接收信息" : product.deliveryFieldZh)。"
            return
        }
        if product.pricingType == "rate" && amount.trimmingCharacters(in: .whitespaces).isEmpty {
            withdrawMsg = "该产品按数量/金额计，请填写金额。"
            return
        }
        Task {
            withdrawMsg = "提交中…"
            let r = await MoonRepository.submitWithdrawal(
                productId: product.id,
                amount: product.pricingType == "rate" ? amount : nil,
                deliveryDetails: delivery,
                note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note
            )
            let st = findStr(r.json, ["status"]) ?? "已提交"
            if r.okHttp {
                withdrawMsg = "✅ 已提交，状态 \(st)\n\(r.body)"
            } else {
                withdrawMsg = "❌ \(r.errorMsg)\n\(r.body)"
            }
        }
    }

    func clearWithdrawMsg() { withdrawMsg = "" }

    // MARK: - JSON 小工具

    /// 双语对象取中文。
    private func text(_ obj: JObj?, _ key: String) -> String {
        guard let obj = obj else { return "" }
        let v = obj[key]
        if let s = v as? String { return s }
        if let d = J.dict(v) {
            let zh = J.str(d, "zh")
            return zh.isEmpty ? J.str(d, "en") : zh
        }
        return J.str(obj, key)
    }

    private func numStr(_ obj: JObj?, _ key: String) -> String {
        guard let obj = obj else { return "" }
        return numText(obj[key])
    }

    private func findVal(_ obj: JObj?, _ keys: [String]) -> Any? {
        guard let obj = obj else { return nil }
        for k in keys {
            if let v = obj[k], !(v is NSNull) { return v }
        }
        if let d = J.dict(obj["data"]) {
            for k in keys {
                if let v = d[k], !(v is NSNull) { return v }
            }
        }
        return nil
    }

    /// 安全读取可选字典的某个键（避免 `opt?["k"]` 的双层可选歧义）。
    private func sub(_ obj: JObj?, _ key: String) -> Any? {
        guard let obj = obj else { return nil }
        return obj[key]
    }

    private func findStr(_ obj: JObj?, _ keys: [String]) -> String? {
        guard let v = findVal(obj, keys) else { return nil }
        return J.anyStr(v)
    }

    func pickString(_ obj: JObj, _ keys: String...) -> String {
        guard let v = findVal(obj, keys) else { return "" }
        return J.anyStr(v)
    }
}