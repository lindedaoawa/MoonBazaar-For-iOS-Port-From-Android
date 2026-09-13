package top.witzzz.moonbazaar.data

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject

// App-level constants.
object AppConfig {
    const val BASE_URL: String = "https://mnb.witzzz.top"

    // Host without scheme, used to detect /auth/done page inside the login WebView.
    const val BASE_HOST: String = "mnb.witzzz.top"

    // Custom-scheme callback resuming the app after OAuth.
    const val CALLBACK_URI: String = "mnb://auth/callback"

    // Recognised scheme of our deep link.
    const val CALLBACK_SCHEME: String = "mnb"

    // Logging tag when calling the Worker.
    const val SOURCE_APP: String = "android"
}

/** 一个已登录的账号（保存它的 Worker session token）。 */
data class Account(
    val uid: String = "",
    val username: String = "",
    val token: String = ""
) {
    /** 稳定主键：优先 UID；登录早期还没拿到 UID 时用 token 前缀。 */
    val key: String
        get() = if (uid.isNotBlank()) "uid:$uid" else "tok:${token.take(12)}"

    val displayName: String
        get() = when {
            username.isNotBlank() -> username
            uid.isNotBlank() -> "UID $uid"
            else -> "未命名账号"
        }
}

/**
 * 多账号 session 存储。
 * 每个账号保存各自的 X-Client-Session token，可随时切换当前账号。
 */
object Session {
    private const val PREFS = "moonbazaar_session"
    private const val KEY_ACCOUNTS = "accounts_json"
    private const val KEY_CURRENT = "current_key"
    private const val LEGACY_TOKEN = "session_token"

    @Volatile
    private var prefs: SharedPreferences? = null

    private val _accounts = MutableStateFlow<List<Account>>(emptyList())
    val accounts: StateFlow<List<Account>> = _accounts.asStateFlow()

    private val _currentKey = MutableStateFlow<String?>(null)
    val currentKey: StateFlow<String?> = _currentKey.asStateFlow()

    private val _token = MutableStateFlow<String?>(null)
    val token: StateFlow<String?> = _token.asStateFlow()
    val tokenValue: String? get() = _token.value

    val currentAccount: Account?
        get() = _accounts.value.firstOrNull { it.key == _currentKey.value }

    val isValid: Boolean get() = !tokenValue.isNullOrBlank()

    // Initialise once at Application.onCreate.
    fun init(context: Context) {
        val p = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs = p
        val list = readAccounts(p).toMutableList()

        // 迁移旧版本的单账号 token
        val legacy = p.getString(LEGACY_TOKEN, null)
        if (!legacy.isNullOrBlank() && list.none { it.token == legacy }) {
            list.add(Account(token = legacy))
        }

        var current = p.getString(KEY_CURRENT, null)
        if (current == null || list.none { it.key == current }) {
            current = list.firstOrNull()?.key
        }
        persist(p, list, current)
        p.edit().remove(LEGACY_TOKEN).apply()

        _accounts.value = list
        _currentKey.value = current
        _token.value = list.firstOrNull { it.key == current }?.token
    }

    /** 新登录成功：加入账号并设为当前。 */
    fun addAndSelect(token: String) {
        val t = token.trim()
        if (t.isBlank()) return
        val p = prefs ?: return
        val list = _accounts.value.toMutableList()
        val idx = list.indexOfFirst { it.token == t }
        val acct = if (idx >= 0) list[idx] else Account(token = t)
        if (idx < 0) list.add(acct)
        persist(p, list, acct.key)
        _accounts.value = list
        _currentKey.value = acct.key
        _token.value = acct.token
    }

    /** 登录后拿到真实 uid/username，回填当前账号（并按 uid 去重）。 */
    fun identify(uid: String, username: String) {
        val u = uid.trim()
        if (u.isBlank()) return
        val p = prefs ?: return
        val cur = _currentKey.value ?: return
        val list = _accounts.value.toMutableList()
        val idx = list.indexOfFirst { it.key == cur }
        if (idx < 0) return

        val dupIdx = list.indexOfFirst { it.uid == u && it != list[idx] }
        val newKey: String
        if (dupIdx >= 0) {
            // 同一账号重复登录：合并到已有条目，使用最新的 token
            val merged = list[dupIdx].copy(
                token = list[idx].token,
                username = username.ifBlank { list[dupIdx].username }
            )
            list[dupIdx] = merged
            list.removeAt(idx)
            newKey = merged.key
        } else {
            list[idx] = list[idx].copy(
                uid = u,
                username = username.ifBlank { list[idx].username }
            )
            newKey = list[idx].key
        }
        persist(p, list, newKey)
        _accounts.value = list
        _currentKey.value = newKey
        _token.value = list.firstOrNull { it.key == newKey }?.token
    }

    /** 切换当前账号。 */
    fun selectByKey(key: String) {
        if (key == _currentKey.value) return
        val acct = _accounts.value.firstOrNull { it.key == key } ?: return
        prefs?.let { persist(it, _accounts.value, acct.key) }
        _currentKey.value = acct.key
        _token.value = acct.token
    }

    /** 移除某个账号；若移除的是当前账号，则自动切到剩余的第一个。 */
    fun removeByKey(key: String) {
        val p = prefs ?: return
        val list = _accounts.value.toMutableList()
        list.removeAll { it.key == key }
        var cur = _currentKey.value
        if (cur == key || list.none { it.key == cur }) {
            cur = list.firstOrNull()?.key
        }
        persist(p, list, cur)
        _accounts.value = list
        _currentKey.value = cur
        _token.value = list.firstOrNull { it.key == cur }?.token
    }

    /** 清空所有账号（完全登出）。 */
    fun clear() {
        val p = prefs ?: return
        persist(p, emptyList(), null)
        _accounts.value = emptyList()
        _currentKey.value = null
        _token.value = null
    }

    private fun readAccounts(p: SharedPreferences): List<Account> {
        val raw = p.getString(KEY_ACCOUNTS, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                val token = o.optString("token")
                if (token.isBlank()) null
                else Account(
                    uid = o.optString("uid"),
                    username = o.optString("username"),
                    token = token
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun persist(p: SharedPreferences, list: List<Account>, current: String?) {
        val arr = JSONArray()
        list.forEach { a ->
            arr.put(
                JSONObject().apply {
                    put("uid", a.uid)
                    put("username", a.username)
                    put("token", a.token)
                }
            )
        }
        p.edit()
            .putString(KEY_ACCOUNTS, arr.toString())
            .putString(KEY_CURRENT, current)
            .apply()
    }
}
