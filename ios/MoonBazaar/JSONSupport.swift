import Foundation

/// JSON 便捷类型别名。Swift 侧用 `[String: Any]` / `[Any]` 承载 `JSONSerialization` 的结果，
/// 对应 Android 版里的 `org.json.JSONObject` / `JSONArray`。
typealias JObj = [String: Any]
typealias JArr = [Any]

/// 与 Android `JSONObject.optXxx` 语义对齐的一组取值工具。
///
/// 关键点：
/// - 不存在的键、`NSNull` 都视为 nil；
/// - 数字保持原始文本（不因为走 `Double` 而出现 `52.8 -> 52.800000000000004`）；
/// - 布尔值通过 `CFBooleanGetTypeID` 与普通数字区分（否则 `1` 会被误判成 `true`）。
enum J {

    // MARK: - 容器

    static func dict(_ value: Any?) -> JObj? { value as? JObj }

    static func arr(_ value: Any?) -> JArr? { value as? JArr }

    /// 读取字典的某个键；不存在或为 NSNull 时返回 nil。
    static func raw(_ obj: Any?, _ key: String) -> Any? {
        guard let d = obj as? JObj, let v = d[key], !(v is NSNull) else { return nil }
        return v
    }

    // MARK: - 标量取值

    /// 带键取值并转字符串（不存在时空串）。
    static func str(_ obj: Any?, _ key: String) -> String { anyStr(raw(obj, key)) }

    static func bool(_ obj: Any?, _ key: String, _ def: Bool = false) -> Bool {
        anyBool(raw(obj, key)) ?? def
    }

    static func int(_ obj: Any?, _ key: String, _ def: Int = 0) -> Int {
        anyInt(raw(obj, key)) ?? def
    }

    static func int64(_ obj: Any?, _ key: String, _ def: Int64 = 0) -> Int64 {
        anyInt64(raw(obj, key)) ?? def
    }

    /// 直接对任意值做转换（适用于数组元素与 `opt("...")` 的结果）。
    static func anyStr(_ value: Any?) -> String {
        switch value {
        case nil:
            return ""
        case let s as String:
            return s
        case let n as NSNumber:
            if isBoolNumber(n) { return n.boolValue ? "true" : "false" }
            return n.stringValue
        case let b as Bool:
            return b ? "true" : "false"
        case let i as Int:
            return String(i)
        case let i as Int64:
            return String(i)
        case let d as Double:
            return numText(d)
        default:
            return String(describing: value!)
        }
    }

    static func anyBool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber {
            if isBoolNumber(n) { return n.boolValue }
            return n.doubleValue != 0
        }
        if let s = value as? String {
            switch s.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    static func anyInt(_ value: Any?) -> Int? { anyInt64(value).map { Int($0) } }

    static func anyInt64(_ value: Any?) -> Int64? {
        if let i = value as? Int64 { return i }
        if let i = value as? Int { return Int64(i) }
        if let n = value as? NSNumber {
            if isBoolNumber(n) { return n.boolValue ? 1 : 0 }
            return n.int64Value
        }
        if let s = value as? String { return Int64(s) }
        return nil
    }

    static func anyDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func isBoolNumber(_ n: NSNumber) -> Bool {
        CFGetTypeID(n) == CFBooleanGetTypeID()
    }
}

/// 数值转文本：保留原始小数（整数不补 `.0`），与 Android 端 `BigDecimal.stripTrailingZeros` 意图一致。
func numText(_ value: Any?) -> String {
    switch value {
    case nil:
        return ""
    case let n as NSNumber:
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
        return n.stringValue
    case let d as Double:
        return numText(d)
    case let i as Int:
        return String(i)
    case let i as Int64:
        return String(i)
    case let s as String:
        return s
    default:
        return J.anyStr(value)
    }
}

func numText(_ d: Double) -> String {
    if d.isNaN || d.isInfinite { return String(d) }
    if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
    return String(d)
}

/// 把任意可序列化对象编码为 JSON 字符串（用于调试展示）。
func prettyJSON(_ obj: Any?) -> String {
    guard let obj = obj, JSONSerialization.isValidJSONObject(obj),
          let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
          let s = String(data: data, encoding: .utf8) else { return "" }
    return s
}