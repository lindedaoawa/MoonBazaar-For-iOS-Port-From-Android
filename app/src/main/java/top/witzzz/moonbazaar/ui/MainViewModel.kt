package top.witzzz.moonbazaar.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import top.witzzz.moonbazaar.data.Account
import top.witzzz.moonbazaar.data.MoonRepository
import top.witzzz.moonbazaar.data.Session

// 登录/会话
sealed class AuthUi {
    data object Unknown : AuthUi()
    data object LoggedOut : AuthUi()
    data object LoggedIn : AuthUi()
}

// 账号信息 (GET /proxy/account/status)
data class AccountInfo(
    val uid: String = "",
    val username: String = "",
    val emailMasked: String = "",
    val emailVerified: Boolean = true,
    val status: String = "",
    val registeredAt: String = "",
    val isBanned: Boolean = false,
    val banReason: String = ""
)

// 首页 hero
data class HomeUi(
    val loading: Boolean = false,
    val gc: String = "—",
    val account: AccountInfo = AccountInfo()
)

data class BanState(val banned: Boolean = false, val reason: String = "")

// 交易流水一条（金额保留原始小数，不做取整）
data class TransactionRecord(
    val createdAt: String = "",
    val typeName: String = "",
    val description: String = "",
    val amountText: String = "0",
    val isGain: Boolean = true
) {
    /** 展示用：正数补 "+"，负数原样（本身带 "-"）。 */
    val displayAmount: String
        get() = if (isGain && !amountText.startsWith("+")) "+$amountText" else amountText
}

// Withdraw 商品卡
data class WithdrawProduct(
    val id: Long,
    val methodZh: String,
    val labelZh: String,
    val categoryZh: String,
    val descZh: String,
    val unitZh: String,
    val deliveryFieldZh: String,
    val pricingType: String,          // fixed | rate
    val fixedCostGc: String,          // 空串则按 rate
    val gcPerUnit: String,
    val minimumAmount: String,
    val maximumAmount: String,
    val apiOk: Boolean,
    val rawText: String
) {
    val bodyText: String get() = rawText
}

// 问卷一条
data class SurveyItem(
    val provider: String = "",
    val surveyId: String = "",
    val reward: String = "0",   // 单位 GC
    val loi: String = "",       // 问卷时长
    val url: String = ""
)

// 主要问卷页面状态
data class SurveysUiState(
    val loading: Boolean = false,
    val message: String = "",
    val countryCode: String = "",
    val qualityScore: Int = 0,
    val surveys: List<SurveyItem> = emptyList()
)

class MainViewModel : ViewModel() {

    private val _auth = MutableStateFlow<AuthUi>(AuthUi.Unknown)
    val auth: StateFlow<AuthUi> = _auth.asStateFlow()
    private val _authNote = MutableStateFlow("")
    val authNote: StateFlow<String> = _authNote.asStateFlow()

    private val _home = MutableStateFlow(HomeUi())
    val home: StateFlow<HomeUi> = _home.asStateFlow()

    private val _ban = MutableStateFlow<BanState>(BanState())
    val ban: StateFlow<BanState> = _ban.asStateFlow()

    // ---- 多账号 ----
    val accounts: StateFlow<List<Account>> = Session.accounts
    val currentKey: StateFlow<String?> = Session.currentKey

    // ---- transactions (paginated) ----
    data class TxUi(
        val loading: Boolean = false,
        val records: List<TransactionRecord> = emptyList(),
        val total: Int = 0,
        val limit: Int = 25,
        val hasMore: Boolean = false,
        val message: String = ""
    )

    private val _tx = MutableStateFlow(TxUi())
    val tx: StateFlow<TxUi> = _tx.asStateFlow()

    // ---- redeem ----
    private val _redeem = MutableStateFlow(RedemptionUiState())
    val redeem: StateFlow<RedemptionUiState> = _redeem.asStateFlow()

    // ---- referral ----
    private val _referral = MutableStateFlow(ReferralUiState())
    val referral: StateFlow<ReferralUiState> = _referral.asStateFlow()

    // ---- withdraw products ----
    private val _products = MutableStateFlow<List<WithdrawProduct>>(emptyList())
    val products: StateFlow<List<WithdrawProduct>> = _products.asStateFlow()

    private val _withdrawMsg = MutableStateFlow<String>("")
    val withdrawMsg: StateFlow<String> = _withdrawMsg.asStateFlow()

    // ---- surveys ----
    private val _surveys = MutableStateFlow(SurveysUiState())
    val surveys: StateFlow<SurveysUiState> = _surveys.asStateFlow()

    init {
        refreshAuthState()
        loadHome()
        loadSurveys()
        loadTransactions(0)
        loadReferral()
        loadProducts()
    }

    // ===== 会话 =====
    fun refreshAuthState() {
        _authNote.value = "检查会话…"
        viewModelScope.launch(Dispatchers.IO) {
            val (s, err) = MoonRepository.status()
            when {
                s == null -> { _auth.value = AuthUi.LoggedOut; _authNote.value = err.ifEmpty { "无法获取会话" } }
                !s.sessionValid || !s.hasTokens -> {
                    _auth.value = AuthUi.LoggedOut
                    _authNote.value = if (s.sessionValid) "已有会话，尚无用户令牌" else "会话无效，请登录"
                }
                else -> { _auth.value = AuthUi.LoggedIn; _authNote.value = "已登录" }
            }
        }
    }

    /** 清空所有与账号相关的界面数据（切换账号 / 登出时必须调用，否则会残留上一个账号的信息）。 */
    private fun clearAccountUiState(note: String) {
        _home.value = HomeUi()
        _ban.value = BanState()
        _tx.value = TxUi()
        _redeem.value = RedemptionUiState()
        _referral.value = ReferralUiState()
        _products.value = emptyList()
        _withdrawMsg.value = ""
        _surveys.value = SurveysUiState()
        _authNote.value = note
    }

    /** 重新拉取当前账号的全部数据。 */
    fun reloadAll() {
        loadHome()
        loadSurveys()
        loadTransactions(0)
        loadReferral()
        loadProducts()
    }

    /** 退出当前账号：吊销服务端 session 并移除本地该账号；若还有其它账号则自动切过去。 */
    fun logout() {
        val key = Session.currentKey.value
        viewModelScope.launch(Dispatchers.IO) {
            MoonRepository.logout()          // 尽力吊销当前账号的 Worker session
            if (key != null) Session.removeByKey(key) else Session.clear()

            clearAccountUiState("未登录")
            if (Session.currentKey.value != null) {
                refreshAuthState()
                reloadAll()
            } else {
                _auth.value = AuthUi.LoggedOut
            }
        }
    }

    /** 切换到指定账号（uid key）。 */
    fun switchAccount(key: String) {
        if (key == Session.currentKey.value) return
        Session.selectByKey(key)
        clearAccountUiState("正在切换账号…")
        _auth.value = AuthUi.Unknown
        refreshAuthState()
        reloadAll()
    }

    /** 移除指定账号；若移除的是当前账号会自动切换到其它账号。 */
    fun removeAccount(key: String) {
        val wasCurrent = key == Session.currentKey.value
        Session.removeByKey(key)
        if (!wasCurrent) return
        clearAccountUiState("已移除该账号")
        if (Session.currentKey.value != null) {
            _auth.value = AuthUi.Unknown
            refreshAuthState()
            reloadAll()
        } else {
            _auth.value = AuthUi.LoggedOut
        }
    }

    // ===== 首页 =====
    fun loadHome() {
        if (!Session.isValid) return
        _home.value = _home.value.copy(loading = true)
        viewModelScope.launch(Dispatchers.IO) {
            val (acct, acctErr) = MoonRepository.accountStatus()
            val (bal, balErr) = MoonRepository.accountBalance()
            val avail = findVal(bal, "available", "available_gascoin", "balance", "gascoin")
            val acctData = acct?.optJSONObject("data") ?: acct
            val banned = acctData?.optBoolean("is_banned", false) == true
            val acctInfo = AccountInfo(
                uid = acctData?.opt("uid")?.toString() ?: "",
                username = acctData?.optString("username") ?: "",
                emailMasked = acctData?.optString("email_masked") ?: "",
                emailVerified = acctData?.optBoolean("email_verified", true) ?: true,
                status = acctData?.optString("status") ?: "",
                registeredAt = acctData?.optString("registered_at") ?: "",
                isBanned = banned,
                banReason = acctData?.optString("ban_reason")?.ifEmpty { "" }
                    ?: (if (banned) "账号已被封禁" else "")
            )
            _ban.value = BanState(banned = banned, reason = acctInfo.banReason)
            _home.value = HomeUi(loading = false, gc = MoonRepository.gcInteger(avail), account = acctInfo)
            // 回填账号信息（uid / username），用于账号列表显示
            if (acctInfo.uid.isNotBlank()) {
                Session.identify(acctInfo.uid, acctInfo.username)
            }
        }
    }

    // ===== 交易流水（动态 limit：先探测 total，再按总数拉取） =====
    // 单次请求条数安全上限：total 超过它时回退为多页加载，避免被上游拒绝或卡顿。
    private val txCap = 500
    private val refCap = 500

    /**
     * @param offset 偏移。传 0 表示「刷新」：先用 limit=1 探测请求拿到 total，
     *               再用 limit=min(total, txCap) 拉取记录。
     */
    fun loadTransactions(offset: Int = 0) {
        if (!Session.isValid) return
        if (_ban.value.banned) {
            _tx.value = TxUi(message = _ban.value.reason.ifEmpty { "账号已封禁，无法查看" })
            return
        }
        val cur = _tx.value
        if (offset > 0 && (cur.loading || !cur.hasMore)) return
        _tx.value = cur.copy(
            loading = true,
            message = if (offset == 0) "正在获取记录总数…" else cur.message
        )
        viewModelScope.launch(Dispatchers.IO) {
            // ① 探测请求：拿总数
            var total = cur.total
            if (offset == 0) {
                val (probe, probeErr) = MoonRepository.transactions(limit = 1, offset = 0)
                val pd = probe?.optJSONObject("data") ?: probe
                if (pd == null) {
                    _tx.value = TxUi(
                        loading = false,
                        message = probeErr.ifEmpty { "无法获取交易记录" }
                    )
                    return@launch
                }
                total = pd.optInt("total", 0)
                if (total <= 0) {
                    _tx.value = TxUi(loading = false, total = 0, hasMore = false,
                        message = "暂无交易记录")
                    return@launch
                }
            }

            // ② 正式请求：limit = min(total, 上限)；翻页时沿用同一页大小
            val pageSize = if (offset == 0) minOf(total, txCap) else cur.limit
            val (data, err) = MoonRepository.transactions(limit = pageSize, offset = offset)
            val d = data?.optJSONObject("data") ?: data
            val records = d?.optJSONArray("records")
            if (records == null) {
                _tx.value = cur.copy(loading = false,
                    message = err.ifEmpty { "暂无交易数据" })
                return@launch
            }
            val list = (0 until records.length()).map { i ->
                val j = records.optJSONObject(i) ?: JSONObject()
                val amountRaw = j.opt("amount_gc")
                val amountText = numberText(amountRaw).ifEmpty { "0" }
                val gain = (amountRaw as? Number)?.toDouble()?.let { it >= 0 } ?: true
                TransactionRecord(
                    createdAt = j.optString("created_at"),
                    typeName = j.optString("type_name"),
                    description = j.optString("description"),
                    amountText = amountText,
                    isGain = gain
                )
            }
            val combined = if (offset == 0) list else cur.records + list
            _tx.value = TxUi(
                loading = false,
                records = combined,
                total = total,
                limit = pageSize,
                hasMore = combined.size < total,
                message = "共 $total 条记录"
            )
        }
    }

    // ===== redeem =====
    fun redeem(code: String) {
        val b = _ban.value
        if (b.banned) {
            _redeem.value = RedemptionUiState(done = true, okHttp = false,
                error = b.reason.ifEmpty { "账号已封禁，无法兑换" })
            return
        }
        if (code.isBlank()) return
        _redeem.value = RedemptionUiState(submitting = true)
        viewModelScope.launch(Dispatchers.IO) {
            val r = MoonRepository.redeemCode(code)
            val confirmation = r.json?.optJSONObject("data")?.optString("confirmation_url")
                ?: r.json?.optString("confirmation_url") ?: ""
            _redeem.value = if (r.okHttp) {
                RedemptionUiState(done = true, okHttp = true, confirmationUrl = confirmation,
                    body = r.body,
                    note = if (confirmation.isBlank()) "受理成功" else "已受理，请打开官方确认页完成兑换")
            } else {
                RedemptionUiState(done = true, okHttp = false,
                    error = r.errorMsg.ifEmpty { "HTTP ${r.http}" }, body = r.body)
            }
        }
    }

    fun resetRedeem() {
        _redeem.value = RedemptionUiState()
    }

    // ===== referral =====
    fun loadReferral() {
        if (!Session.isValid) return
        if (_ban.value.banned) {
            _referral.value = ReferralUiState(
                message = _ban.value.reason.ifEmpty { "账号已封禁，无法查看" })
            return
        }
        _referral.value = _referral.value.copy(loading = true)
        viewModelScope.launch(Dispatchers.IO) {
            // 邀请链接（uid_link 必有；custom_link 可能未设置）
            val (linkData, linkErr) = MoonRepository.referralLink()
            val ld = linkData?.optJSONObject("data") ?: linkData
            val uidLink = ld?.optString("uid_link").orEmpty()
            val customCode = ld?.optString("custom_code").orEmpty()
            val customLink = ld?.optString("custom_link").orEmpty()

            // 邀请统计 + 明细（先探测总数再按总数拉取）
            val invites = mutableListOf<InviteeRow>()
            var totalInvites = 0
            var commission = ""
            var listErrMsg = ""

            val (probe, probeErr) = MoonRepository.referrals(limit = 1, offset = 0)
            val pd = probe?.optJSONObject("data") ?: probe
            if (pd == null) {
                listErrMsg = probeErr.ifEmpty { "无法获取邀请数据" }
            } else {
                totalInvites = pd.optInt("total_invites", 0)
                commission = numberText(pd.opt("commission_earned_gc"))
                if (totalInvites > 0) {
                    val pageSize = minOf(totalInvites, refCap)
                    val (listData, listErr) = MoonRepository.referrals(limit = pageSize, offset = 0)
                    val d = listData?.optJSONObject("data") ?: listData
                    val arr = d?.optJSONArray("invites")
                    if (arr == null) {
                        listErrMsg = listErr.ifEmpty { "邀请明细为空" }
                    } else {
                        for (i in 0 until arr.length()) {
                            val j = arr.optJSONObject(i) ?: continue
                            invites.add(
                                InviteeRow(
                                    id = j.optLong("id"),
                                    username = j.optString("username"),
                                    createdAt = j.optString("created_at"),
                                    isBanned = j.optBoolean("is_banned", false),
                                    totalEarnedGc = numberText(j.opt("total_earned_gc")),
                                    milestoneAwarded = j.optBoolean("milestone_awarded", false)
                                )
                            )
                        }
                    }
                }
            }
            if (listErrMsg.isBlank() && linkErr.isNotBlank()) listErrMsg = linkErr

            _referral.value = ReferralUiState(
                loading = false,
                message = listErrMsg,
                totalInvites = totalInvites,
                commissionEarnedGc = commission.ifEmpty { "0" },
                invites = invites,
                uidLink = uidLink,
                customCode = customCode,
                customLink = customLink
            )
        }
    }

    // ===== 主要问卷 =====
    fun loadSurveys() {
        if (!Session.isValid) return
        if (_ban.value.banned) {
            _surveys.value = SurveysUiState(
                message = _ban.value.reason.ifEmpty { "账号已封禁，无法查看问卷" })
            return
        }
        _surveys.value = _surveys.value.copy(loading = true, message = "")
        viewModelScope.launch(Dispatchers.IO) {
            val (data, err) = MoonRepository.surveys()
            val d = data?.optJSONObject("data") ?: data
            if (d == null) {
                _surveys.value = SurveysUiState(loading = false,
                    message = err.ifEmpty { "无法获取问卷" })
                return@launch
            }
            val country = d.optString("country_code")
            val quality = d.optInt("quality_score", 0)

            // provider_status: { "cpx": true, ... } —— 为 false 的提供商问卷不显示
            val statusObj = d.optJSONObject("provider_status")
            fun providerEnabled(p: String): Boolean {
                if (statusObj == null) return true
                val keys = statusObj.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    if (k.equals(p, ignoreCase = true)) return statusObj.optBoolean(k, true)
                }
                return true   // 未列出的提供商不隐藏
            }

            val arr = d.optJSONArray("surveys")
            val list = mutableListOf<SurveyItem>()
            if (arr != null) {
                for (i in 0 until arr.length()) {
                    val j = arr.optJSONObject(i) ?: continue
                    val provider = j.optString("provider")
                    if (!providerEnabled(provider)) continue
                    // 真实字段：id / payout / link；同时对示例里的旧键名做兜底
                    val payout = if (j.has("payout")) j.opt("payout") else j.opt("reward")
                    list.add(
                        SurveyItem(
                            provider = provider,
                            surveyId = if (j.has("id")) j.opt("id")?.toString().orEmpty()
                            else j.opt("survey_id")?.toString().orEmpty(),
                            reward = numberText(payout).ifEmpty { "0" },
                            loi = numberText(j.opt("loi")),
                            url = j.optString("link").ifBlank { j.optString("url") }
                        )
                    )
                }
            }
            _surveys.value = SurveysUiState(
                loading = false,
                message = if (list.isEmpty()) "当前没有可做的问卷" else "共 ${list.size} 份可做问卷",
                countryCode = country,
                qualityScore = quality,
                surveys = list
            )
        }
    }

    // ===== withdraw products =====
    fun loadProducts() {
        if (!Session.isValid) return
        if (_ban.value.banned) {
            _products.value = emptyList()
            _withdrawMsg.value = _ban.value.reason.ifEmpty { "账号已封禁，无法提现" }
            return
        }
        viewModelScope.launch(Dispatchers.IO) {
            _withdrawMsg.value = "加载中…"
            val (data, err) = MoonRepository.products()
            val d = data?.optJSONObject("data") ?: data
            val methods = d?.optJSONArray("methods")
            if (methods == null) {
                _products.value = emptyList()
                _withdrawMsg.value = err.ifEmpty { (d?.toString(2)) ?: "无提现产品" }
                return@launch
            }
            val out = mutableListOf<WithdrawProduct>()
            for (m in 0 until methods.length()) {
                val method = methods.optJSONObject(m) ?: continue
                val methodZh = text(method, "name") // {en,zh}
                val apiOk = method.optBoolean("api_withdraw_supported", true)
                val productsArr = method.optJSONArray("products") ?: continue
                for (p in 0 until productsArr.length()) {
                    val j = productsArr.optJSONObject(p) ?: continue
                    val pricing = j.optString("pricing_type", "fixed")
                    out.add(WithdrawProduct(
                        id = j.optLong("id"),
                        methodZh = methodZh,
                        labelZh = text(j, "label"),
                        categoryZh = text(j, "category"),
                        descZh = text(j, "description"),
                        unitZh = text(j, "unit"),
                        deliveryFieldZh = text(j, "delivery_field"),
                        pricingType = pricing,
                        fixedCostGc = numStr(j, "fixed_cost_gc"),
                        gcPerUnit = numStr(j, "gc_per_unit"),
                        minimumAmount = numStr(j, "minimum_amount"),
                        maximumAmount = numStr(j, "maximum_amount"),
                        apiOk = apiOk,
                        rawText = j.toString(2)
                    ))
                }
            }
            _products.value = out
            _withdrawMsg.value = if (out.isEmpty()) "（暂无可用提现产品）" else "共 ${out.size} 个可提现产品"
        }
    }

    fun submitWithdrawal(product: WithdrawProduct?, amount: String, delivery: String, note: String) {
        val b = _ban.value
        if (product == null || product.id <= 0) {
            _withdrawMsg.value = "请选择一个提现产品。"
            return
        }
        if (b.banned) {
            _withdrawMsg.value = "❌ ${b.reason.ifEmpty { "账号已封禁，无法提现" }}"
            return
        }
        if (delivery.isBlank()) {
            _withdrawMsg.value = "需填写${product.deliveryFieldZh.ifEmpty { "接收信息" }}。"
            return
        }
        if (product.pricingType == "rate" && amount.isBlank()) {
            _withdrawMsg.value = "该产品按数量/金额计，请填写金额。"
            return
        }
        // 发送时固定价可不传 amount，rate 必传
        viewModelScope.launch(Dispatchers.IO) {
            _withdrawMsg.value = "提交中…"
            val r = MoonRepository.submitWithdrawal(
                product.id,
                if (product.pricingType == "rate") amount else null,
                delivery, note.ifBlank { null })
            val st = findStr(r.json, "status") ?: "已提交"
            _withdrawMsg.value = if (r.okHttp) "✅ 已提交，状态 $st\n${r.body}"
            else "❌ ${r.errorMsg}\n${r.body}"
        }
    }

    fun clearWithdrawMsg() { _withdrawMsg.value = "" }

    // 文本双语对象取中文
    private fun text(o: JSONObject?, key: String): String {
        o ?: return ""
        val v = o.opt(key)
        return when (v) {
            is String -> v
            is JSONObject -> v.optString("zh").ifEmpty { v.optString("en") }
            else -> o.optString(key)
        }
    }

    private fun numStr(o: JSONObject?, key: String): String {
        o ?: return ""
        return numberText(o.opt(key))
    }

    /** 数值转字符串：保留原始小数（整数不补 .0），不用取整。 */
    private fun numberText(v: Any?): String = when (v) {
        null -> ""
        is Double -> if (v.isNaN() || v.isInfinite()) v.toString()
        else java.math.BigDecimal.valueOf(v).stripTrailingZeros().toPlainString()
        else -> v.toString()
    }

    // ===== small JSON helpers (root or data aware) =====
    private fun findVal(o: JSONObject?, vararg keys: String): Any? {
        o ?: return null
        for (k in keys) if (o.has(k)) { val v = o.opt(k); if (v != null && v !== JSONObject.NULL) return v }
        o.optJSONObject("data")?.let { d ->
            for (k in keys) if (d.has(k)) { val v = d.opt(k); if (v != null && v !== JSONObject.NULL) return v }
        }
        return null
    }

    private fun findStr(o: JSONObject?, vararg keys: String): String? =
        findVal(o, *keys)?.toString()

    fun pickString(o: JSONObject, vararg keys: String): String = findStr(o, *keys) ?: ""
}

data class RedemptionUiState(
    val submitting: Boolean = false,
    val done: Boolean = false,
    val okHttp: Boolean = false,
    val confirmationUrl: String = "",
    val error: String = "",
    val note: String = "",
    val body: String = ""
)

// 邀请明细一行
data class InviteeRow(
    val id: Long = 0,
    val username: String = "",
    val createdAt: String = "",
    val isBanned: Boolean = false,
    val totalEarnedGc: String = "0",
    val milestoneAwarded: Boolean = false
)

data class ReferralUiState(
    val loading: Boolean = false,
    val message: String = "",
    val totalInvites: Int = 0,
    val commissionEarnedGc: String = "0",
    val invites: List<InviteeRow> = emptyList(),
    val uidLink: String = "",       // 数值邀请链接（必有）
    val customCode: String = "",    // 自定义邀请码（可能未设置）
    val customLink: String = ""     // 自定义链接（可能未设置）
)
