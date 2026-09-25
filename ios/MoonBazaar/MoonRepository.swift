import Foundation

/// Worker 各接口的封装与幂等键生成（对应 Android 的 `data/MoonRepository.kt`）。
///
/// 每次调用都走 Worker，因此 App 既不持有 MoonBazaar API Key，也不持有用户 token；
/// `Session` 由 `MoonWorkerApi` 以 `X-Client-Session` 头发送。
@MainActor
enum MoonRepository {

    private static let api = MoonWorkerApi()

    // MARK: - /status

    struct SessionStatus {
        var okResponse: Bool = false
        var sessionValid: Bool = false
        var hasTokens: Bool = false
        var uid: String?
        var apiKeyConfigured: Bool = false
        var rawText: String = ""
    }

    /// 返回 (状态, 错误信息)。状态为 nil 时看错误信息。
    static func status() async -> (SessionStatus?, String) {
        let r = await api.get("/status")
        guard r.ok else { return (nil, r.readable.isEmpty ? "HTTP \(r.httpStatus)" : r.readable) }
        guard let j = r.json else { return (nil, "无法解析返回 JSON") }
        let s = SessionStatus(
            okResponse: J.bool(j, "ok"),
            sessionValid: J.bool(j, "session_valid"),
            hasTokens: J.bool(j, "has_tokens"),
            uid: J.str(j, "uid").isEmpty ? nil : J.str(j, "uid"),
            apiKeyConfigured: J.bool(j, "api_key_configured"),
            rawText: r.body
        )
        return (s, "")
    }

    // MARK: - /proxy/account/*

    static func accountStatus() async -> (JObj?, String) { await proxyObj("account/status") }
    static func accountBalance() async -> (JObj?, String) { await proxyObj("account/balance") }

    // MARK: - 只读列表

    static func transactions(limit: Int = 30, offset: Int = 0) async -> (JObj?, String) {
        await proxyObj("transactions?limit=\(limit)&offset=\(offset)")
    }

    static func referrals(limit: Int = 50, offset: Int = 0) async -> (JObj?, String) {
        await proxyObj("referrals?limit=\(limit)&offset=\(offset)")
    }

    static func referralLink() async -> (JObj?, String) { await proxyObj("referrals/link") }

    /// 提现商品列表。
    static func products() async -> (JObj?, String) { await proxyObj("products") }

    /// 主要问卷。Worker 会自动补 client_ip。
    static func surveys() async -> (JObj?, String) { await proxyObj("surveys") }

    // MARK: - 写操作

    struct WriteResult {
        var body: String
        var http: Int
        var okHttp: Bool

        var json: JObj? {
            guard !body.isEmpty, let data = body.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? JObj
        }

        var errorMsg: String {
            let fallback = okHttp ? "" : "HTTP \(http)"
            guard let j = json, let rawError = j["error"] else { return fallback }
            if let m = J.dict(rawError)?["message"] as? String, !m.isEmpty { return m }
            return fallback
        }
    }

    /// POST /proxy/withdrawals（需要幂等键）。
    static func submitWithdrawal(productId: Int64,
                                 amount: String?,
                                 deliveryDetails: String,
                                 note: String?) async -> WriteResult {
        var b: JObj = [:]
        b["product_id"] = productId
        if let amount = amount, !amount.trimmingCharacters(in: .whitespaces).isEmpty {
            b["amount"] = amount.trimmingCharacters(in: .whitespaces)
        }
        b["delivery_details"] = deliveryDetails
        if let note = note, !note.trimmingCharacters(in: .whitespaces).isEmpty { b["note"] = note }
        return await write("withdrawals", b)
    }

    /// POST /proxy/codes/redeem（需要幂等键）；通常返回 202 与 `confirmation_url`。
    static func redeemCode(_ code: String) async -> WriteResult {
        let b: JObj = ["code": code.trimmingCharacters(in: .whitespacesAndNewlines)]
        return await write("codes/redeem", b)
    }

    /// POST /proxy/account/email-verification（不带幂等键）。
    static func requestEmailVerification() async -> WriteResult {
        await write("account/email-verification", [:], needIdem: false)
    }

    /// DELETE /user/tokens：吊销 Worker session。
    static func logout() async -> WriteResult {
        let r = await api.del("/user/tokens")
        return WriteResult(body: r.body, http: r.httpStatus, okHttp: r.ok)
    }

    // MARK: - 内部

    private static func proxyObj(_ path: String) async -> (JObj?, String) {
        let r = await api.proxyGet(path)
        guard r.ok else { return (nil, r.readable.isEmpty ? "HTTP \(r.httpStatus)" : r.readable) }
        guard let j = r.json else { return (nil, "上游返回空或非 JSON") }
        return (j, "")
    }

    private static func write(_ path: String, _ body: JObj, needIdem: Bool = true) async -> WriteResult {
        let res: MoonWorkerApi.CallResult
        if needIdem {
            res = await api.proxyPost(path, body, idempotencyKey: genIdem(path))
        } else {
            res = await api.proxyPostNoIdem(path, body)
        }
        return WriteResult(body: res.body, http: res.httpStatus, okHttp: res.ok)
    }

    private static var seq: Int64 = 0
    static func genIdem(_ prefix: String = "op") -> String {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        seq = (seq + 1) % 100000
        let sessPrefix = Session.shared.tokenValue.map { String($0.prefix(8)) } ?? "anon"
        return "\(prefix)-\(ts)-\(seq)-\(sessPrefix)"
    }

    /// 把 GC（Gascoin）渲染为整数串：丢掉小数。
    static func gcInteger(_ value: Any?) -> String {
        guard let d = J.anyDouble(value) else { return "0" }
        if d < 0 || d.isNaN { return "0" }
        return String(Int64(d.rounded(.down)))
    }
}