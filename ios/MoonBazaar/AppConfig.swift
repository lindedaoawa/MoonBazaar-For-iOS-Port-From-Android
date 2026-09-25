import Foundation

/// App 级常量（与 Android 版 `data/AppConfig.kt` 一一对应）。
enum AppConfig {
    /// 自己部署的 Cloudflare Worker 域名。**必须改成你自己的域名**。
    static let BASE_URL = "https://mnb.witzzz.top"

    /// 不带 scheme 的 host，用于在登录 WebView 中识别 `/auth/done` 落地页。
    static let BASE_HOST = "mnb.witzzz.top"

    /// OAuth 结束后回到 App 的自定义 scheme 回调。
    static let CALLBACK_URI = "mnb://auth/callback"

    /// 深链 scheme。
    static let CALLBACK_SCHEME = "mnb"

    /// 请求头 `X-Source-App`，便于 Worker 端日志追踪。
    static let SOURCE_APP = "ios"

    /// 归一化后的 base（去掉结尾斜杠）。
    static var baseTrimmed: String {
        BASE_URL.hasSuffix("/") ? String(BASE_URL.dropLast()) : BASE_URL
    }

    /// 登录入口。
    static var loginUrl: String { baseTrimmed + "/auth/login" }

    /// 组装带登录回跳的授权 URL（供自定义动作 / 调试用）。
    static func moonLoginUrl() -> String {
        let cb = CALLBACK_URI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? CALLBACK_URI
        return baseTrimmed + "/auth/login?client_back_uri=" + cb
    }
}