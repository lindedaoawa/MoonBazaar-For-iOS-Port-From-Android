import Foundation
import Combine

/// 一个已登录的账号（保存它的 Worker session token）。
/// 对应 Android 版 `data/AppConfig.kt` 中的 `Account`。
struct Account: Codable, Equatable, Identifiable {
    var uid: String = ""
    var username: String = ""
    var token: String = ""

    /// 稳定主键：优先 UID；登录早期还没拿到 UID 时用 token 前缀。
    var key: String {
        uid.isEmpty ? "tok:\(String(token.prefix(12)))" : "uid:\(uid)"
    }

    var displayName: String {
        if !username.isEmpty { return username }
        if !uid.isEmpty { return "UID \(uid)" }
        return "未命名账号"
    }

    var id: String { key }
}

/// 多账号 session 存储（等价于 Android 的 `SharedPreferences` 版本）。
///
/// - 账号列表与当前选中项持久化在 `UserDefaults`：
///   `accounts_json` / `current_key`，并自动迁移旧版本的单账号 token（`session_token`）。
/// - SwiftUI 通过 `@ObservedObject Session.shared` 观察 `accounts` / `currentKey`。
@MainActor
final class Session: ObservableObject {

    static let shared = Session()

    private let KEY_ACCOUNTS = "accounts_json"
    private let KEY_CURRENT = "current_key"
    private let LEGACY_TOKEN = "session_token"

    @Published private(set) var accounts: [Account] = []
    @Published private(set) var currentKey: String?
    /// 当前账号的 session token（供网络层读取）。
    @Published private(set) var token: String?

    /// 网络层可直接读取的值。
    var tokenValue: String? { token }

    var currentAccount: Account? {
        accounts.first { $0.key == currentKey }
    }

    var isValid: Bool { !(token ?? "").isEmpty }

    private init() {
        load()
    }

    // MARK: - 初始化 / 迁移

    func load() {
        let ud = UserDefaults.standard
        var list = readAccounts(ud)

        // 迁移旧版本的单账号 token
        if let legacy = ud.string(forKey: LEGACY_TOKEN), !legacy.isEmpty,
           !list.contains(where: { $0.token == legacy }) {
            list.append(Account(token: legacy))
        }

        var current = ud.string(forKey: KEY_CURRENT)
        if current == nil || !list.contains(where: { $0.key == current }) {
            current = list.first?.key
        }
        persist(list, current)
        ud.removeObject(forKey: LEGACY_TOKEN)

        accounts = list
        currentKey = current
        token = list.first { $0.key == current }?.token
    }

    // MARK: - 变更

    /// 新登录成功：加入账号并设为当前。
    func addAndSelect(token raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var list = accounts
        let idx = list.firstIndex { $0.token == t }
        let acct: Account
        if let idx = idx {
            acct = list[idx]
        } else {
            acct = Account(token: t)
            list.append(acct)
        }
        persist(list, acct.key)
        accounts = list
        currentKey = acct.key
        token = acct.token
    }

    /// 登录后拿到真实 uid/username，回填当前账号（并按 uid 去重）。
    func identify(uid rawUID: String, username: String) {
        let u = rawUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, let cur = currentKey else { return }
        var list = accounts
        guard let idx = list.firstIndex(where: { $0.key == cur }) else { return }

        let newKey: String
        if let dupIdx = list.firstIndex(where: { $0.uid == u && $0 != list[idx] }) {
            // 同一账号重复登录：合并到已有条目，使用最新的 token
            var merged = list[dupIdx]
            merged.token = list[idx].token
            if !username.isEmpty { merged.username = username }
            list[dupIdx] = merged
            list.remove(at: idx)
            newKey = merged.key
        } else {
            var updated = list[idx]
            updated.uid = u
            if !username.isEmpty { updated.username = username }
            list[idx] = updated
            newKey = updated.key
        }
        persist(list, newKey)
        accounts = list
        currentKey = newKey
        token = list.first { $0.key == newKey }?.token
    }

    /// 切换当前账号。
    func selectByKey(_ key: String) {
        guard key != currentKey, let acct = accounts.first(where: { $0.key == key }) else { return }
        persist(accounts, acct.key)
        currentKey = acct.key
        token = acct.token
    }

    /// 移除某个账号；若移除的是当前账号，则自动切到剩余的第一个。
    func removeByKey(_ key: String) {
        var list = accounts
        list.removeAll { $0.key == key }
        var cur = currentKey
        if cur == key || !list.contains(where: { $0.key == cur }) {
            cur = list.first?.key
        }
        persist(list, cur)
        accounts = list
        currentKey = cur
        token = list.first { $0.key == cur }?.token
    }

    /// 清空所有账号（完全登出）。
    func clear() {
        persist([], nil)
        accounts = []
        currentKey = nil
        token = nil
    }

    // MARK: - 持久化

    private func readAccounts(_ ud: UserDefaults) -> [Account] {
        guard let raw = ud.string(forKey: KEY_ACCOUNTS),
              let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([Account].self, from: data) else { return [] }
        return list.filter { !$0.token.isEmpty }
    }

    private func persist(_ list: [Account], _ current: String?) {
        let ud = UserDefaults.standard
        if let data = try? JSONEncoder().encode(list),
           let raw = String(data: data, encoding: .utf8) {
            ud.set(raw, forKey: KEY_ACCOUNTS)
        }
        if let current = current {
            ud.set(current, forKey: KEY_CURRENT)
        } else {
            ud.removeObject(forKey: KEY_CURRENT)
        }
    }
}