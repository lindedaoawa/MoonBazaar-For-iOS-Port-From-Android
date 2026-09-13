package top.witzzz.moonbazaar.data

import org.json.JSONObject

// Lightweight typed/call wrappers around the Worker API.
// Every call talks to the Worker so the app never holds the MoonBazaar API key
// or the user token; Session is sent as X-Client-Session by MoonWorkerApi.
object MoonRepository {

    private val api = MoonWorkerApi()

    data class SessionStatus(
        val okResponse: Boolean,
        val sessionValid: Boolean,
        val hasTokens: Boolean,
        val uid: String?,
        val apiKeyConfigured: Boolean,
        val rawText: String
    )

    // /status
    fun status(): Pair<SessionStatus?, String> {
        val r = api.get("/status")
        if (!r.ok) return null to (r.readable.ifEmpty { "HTTP ${r.httpStatus}" })
        val j = r.json ?: return null to "无法解析返回 JSON"
        return SessionStatus(
            okResponse = j.optBoolean("ok", false),
            sessionValid = j.optBoolean("session_valid", false),
            hasTokens = j.optBoolean("has_tokens", false),
            uid = j.optString("uid").ifBlank { null },
            apiKeyConfigured = j.optBoolean("api_key_configured", false),
            rawText = r.body
        ) to ""
    }

    // /proxy/account/*
    fun accountStatus(): Pair<JSONObject?, String> = proxyObj("account/status")
    fun accountBalance(): Pair<JSONObject?, String> = proxyObj("account/balance")

    // /proxy/transactions
    fun transactions(limit: Int = 30, offset: Int = 0): Pair<JSONObject?, String> =
        proxyObj("transactions?limit=$limit&offset=$offset")

    // /proxy/referrals and /proxy/referrals/link
    fun referrals(limit: Int = 50, offset: Int = 0): Pair<JSONObject?, String> =
        proxyObj("referrals?limit=$limit&offset=$offset")
    fun referralLink(): Pair<JSONObject?, String> = proxyObj("referrals/link")

    // /proxy/products (withdraw products)
    fun products(): Pair<JSONObject?, String> = proxyObj("products")

    // /proxy/surveys (main surveys). Worker auto-fills client_ip.
    fun surveys(): Pair<JSONObject?, String> = proxyObj("surveys")

    data class WriteResult(val body: String, val http: Int, val okHttp: Boolean) {
        val json: JSONObject?
            get() = try {
                if (body.isBlank()) null else JSONObject(body)
            } catch (_: Exception) {
                null
            }
        val errorMsg: String
            get() = json?.optJSONObject("error")?.optString("message")
                ?.takeIf { it.isNotBlank() }
                ?: (if (okHttp) "" else "HTTP $http")
    }

    // POST /proxy/withdrawals (idempotency-required)
    fun submitWithdrawal(
        productId: Long,
        amount: String?,
        deliveryDetails: String,
        note: String?
    ): WriteResult {
        val b = JSONObject().apply {
            put("product_id", productId)
            if (!amount.isNullOrBlank()) put("amount", amount.trim())
            put("delivery_details", deliveryDetails)
            if (!note.isNullOrBlank()) put("note", note)
        }
        return write("withdrawals", b)
    }

    // POST /proxy/codes/redeem (idempotency-required); usually HTTP 202,
    // returns a confirmation_url the user must open to finalise.
    fun redeemCode(code: String): WriteResult {
        val b = JSONObject().put("code", code.trim())
        return write("codes/redeem", b)
    }

    // POST /proxy/account/email-verification (no idempotency header).
    fun requestEmailVerification(): WriteResult {
        val b = JSONObject()
        return write("account/email-verification", b, needIdem = false)
    }

    // DELETE /user/tokens: revoke WORKER session server-side.
    fun logout(): WriteResult {
        val r = api.del("/user/tokens")
        return WriteResult(body = r.body, http = r.httpStatus, okHttp = r.ok)
    }

    private fun proxyObj(path: String): Pair<JSONObject?, String> {
        val r = api.proxyGet(path)
        if (!r.ok) return null to (r.readable.ifEmpty { "HTTP ${r.httpStatus}" })
        val j = r.json ?: return null to "上游返回空或非 JSON"
        return j to ""
    }

    private fun write(path: String, body: JSONObject, needIdem: Boolean = true): WriteResult {
        val res = if (needIdem) api.proxyPost(path, body, genIdem(path))
        else api.proxyPostNoIdem(path, body)
        return WriteResult(body = res.body, http = res.httpStatus, okHttp = res.ok)
    }

    private var seq = 0L
    fun genIdem(prefix: String = "op"): String {
        val ts = System.currentTimeMillis()
        seq = (seq + 1) % 100000
        return "$prefix-$ts-$seq-${Session.tokenValue?.take(8) ?: "anon"}"
    }

    // Render a GC (Gascoin) value as an integer string: drop the decimals.
    fun gcInteger(value: Any?): String {
        if (value == null) return "0"
        val d: Double = when (value) {
            is Number -> value.toDouble()
            is String -> value.trim().toDoubleOrNull()
            else -> null
        } ?: return "0"
        if (d < 0) return "0"
        return kotlin.math.floor(d).toLong().toString()
    }
}
