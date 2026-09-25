import Foundation

/// 对 MoonBazaar Worker 的轻量 HTTP 客户端（session 鉴权版）。
///
/// - App 一律请求 `AppConfig.BASE_URL`（自己部署的 Cloudflare Worker），由 Worker 转发到
///   MoonBazaar 上游并自动注入 `X-API-Key` / `Authorization(Bearer)`。
/// - 客户端身份使用 Worker 发放的 session token（见 `Session`），每次请求自动带
///   `X-Client-Session: <session_token>`。
/// - 写操作统一走 `proxyPost`，并强制携带 `idempotencyKey`（MoonBazaar 要求 8–128 字符）。
///
/// 说明：`await session.data(for:)` 是挂起而不是阻塞，因此标 `@MainActor` 不会卡住 UI，
/// 同时保证 `Session` 的 `@Published` 更新始终在主线程。
@MainActor
final class MoonWorkerApi {

    private let session: URLSession

    /// 与 Android OkHttp 的 connect/read/write 超时保持一致。
    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 45
        cfg.timeoutIntervalForResource = 45
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["Accept": "application/json"]
        session = URLSession(configuration: cfg)
    }

    /// 一次调用的结果。
    struct CallResult {
        var ok: Bool                  // HTTP 是否 2xx
        var httpStatus: Int = -1
        var body: String = ""         // Worker / 上游原始响应文本
        var replayed: Bool = false    // Idempotent-Replayed == true
        var thrown: String?           // 本地网络 / IO 错误

        var json: JObj? {
            guard !body.isEmpty, let data = body.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? JObj
        }

        var upError: JObj? {
            guard let j = json, let e = j["error"] else { return nil }
            return J.dict(e)
        }

        /// 对 UI 友好：优先取上游 error.message，其次本地 thrown / HTTP。
        var readable: String {
            if let e = upError, let m = e["message"] as? String, !m.isEmpty { return m }
            if let t = thrown, !t.isEmpty { return t }
            if !ok { return "HTTP \(httpStatus)" }
            return ""
        }
    }

    // MARK: - 便捷入口

    /// Worker 自带的只读接口（如 `/status`）。
    func get(_ path: String) async -> CallResult { await exec("GET", path, nil, nil) }

    /// Worker 自带写接口（如 `DELETE /user/tokens` 登出）。
    func del(_ path: String) async -> CallResult { await exec("DELETE", path, nil, nil) }

    /// 经 Worker 代理的只读 GET：path 不带 `/proxy` 前缀，如 `account/status`。
    func proxyGet(_ path: String) async -> CallResult { await exec("GET", "/proxy/\(path)", nil, nil) }

    /// 经 Worker 代理的写操作，body 可为 nil，需幂等键。path 不带 `/proxy`。
    func proxyPost(_ path: String, _ body: JObj?, idempotencyKey: String) async -> CallResult {
        await exec("POST", "/proxy/\(path)", body, idempotencyKey)
    }

    /// 经 Worker 代理、**无需幂等键**的写操作（如 `account/email-verification`）。
    func proxyPostNoIdem(_ path: String, _ body: JObj?) async -> CallResult {
        await exec("POST", "/proxy/\(path)", body, nil)
    }

    // MARK: - 核心

    private func exec(_ method: String, _ urlPath: String, _ body: JObj?, _ idem: String?) async -> CallResult {
        let base = AppConfig.BASE_URL.hasSuffix("/")
            ? String(AppConfig.BASE_URL.dropLast())
            : AppConfig.BASE_URL
        guard let url = URL(string: base + urlPath) else {
            return CallResult(ok: false, thrown: "无效的请求地址：\(base + urlPath)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method.uppercased()
        req.setValue(AppConfig.SOURCE_APP, forHTTPHeaderField: "X-Source-App")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let sess = Session.shared.tokenValue, !sess.isEmpty {
            req.setValue(sess, forHTTPHeaderField: "X-Client-Session")
        }
        if let idem = idem {
            req.setValue(idem, forHTTPHeaderField: "Idempotency-Key")
        }

        if method.uppercased() == "POST" {
            let payload: Data
            if let body = body, let data = try? JSONSerialization.data(withJSONObject: body) {
                payload = data
            } else {
                payload = Data("{}".utf8)
            }
            req.httpBody = payload
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: req)
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? -1
            return CallResult(
                ok: (200...299).contains(code),
                httpStatus: code,
                body: String(data: data, encoding: .utf8) ?? "",
                replayed: http?.value(forHTTPHeaderField: "Idempotent-Replayed") == "true",
                thrown: nil
            )
        } catch {
            return CallResult(ok: false, httpStatus: -1, body: "",
                              thrown: "网络请求失败：\(error.localizedDescription)")
        }
    }
}