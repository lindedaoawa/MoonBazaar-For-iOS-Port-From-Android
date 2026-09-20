package top.witzzz.moonbazaar.ui

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.net.Uri
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.ByteArrayInputStream
import java.util.concurrent.TimeUnit

// ============================ 问卷 WebView ============================
// 问卷在 App 内打开，并在 WebView 内对请求做重写 / 拦截，避免依赖被墙的域名。
//
// 重写（仅替换域名/路径前缀，其余原样保留，包含全部 query 参数）：
//   google.com/recaptcha   -> recaptcha.net/recaptcha
//   ajax.googleapis.com    -> ajax.loli.net
//   api.ipify.org          -> api64.ipify.org
//
// 拦截（直接阻止加载，不做任何响应改写）：
//   www.google.com/jsapi
//   firebase.googleapis.com/*
//   accounts.google.com/gsi/client
//   analytics.tiktok.com/*
//   connect.facebook.net/*

private const val RECAPTCHA_FROM = "google.com/recaptcha"
private const val RECAPTCHA_TO = "recaptcha.net/recaptcha"
private const val AJAX_FROM = "ajax.googleapis.com"
private const val AJAX_TO = "ajax.loli.net"
private const val IPIFY_FROM = "api.ipify.org"
private const val IPIFY_TO = "api64.ipify.org"

/** 命中则直接拦截（纯函数，便于单测）。 */
internal fun isBlockedHostPath(host: String, path: String): Boolean {
    val h = host.lowercase()
    val p = path.ifEmpty { "/" }
    return when {
        // 整个域名下所有路径
        h == "firebase.googleapis.com" -> true
        h == "analytics.tiktok.com" -> true
        h == "connect.facebook.net" -> true
        // 精确路径（允许其子路径），避免误伤同前缀的其它路径
        h == "www.google.com" && (p == "/jsapi" || p.startsWith("/jsapi/")) -> true
        h == "accounts.google.com" &&
            (p == "/gsi/client" || p.startsWith("/gsi/client/")) -> true
        else -> false
    }
}

/** 命中则直接拦截。 */
internal fun isBlockedSurveyUrl(url: String): Boolean {
    val u = Uri.parse(url)
    val host = u.host ?: return false
    return isBlockedHostPath(host, u.path.orEmpty())
}

/** 按规则重写 URL；参数与其余部分保持不变。 */
internal fun rewriteSurveyUrl(url: String): String {
    var out = url
    if (out.contains(RECAPTCHA_FROM)) out = out.replace(RECAPTCHA_FROM, RECAPTCHA_TO)
    if (out.contains(AJAX_FROM)) out = out.replace(AJAX_FROM, AJAX_TO)
    if (out.contains(IPIFY_FROM)) out = out.replace(IPIFY_FROM, IPIFY_TO)
    return out
}

// 用于代替 WebView 去实际拉取重写后的子资源
private val surveyProxyClient: OkHttpClient = OkHttpClient.Builder()
    .connectTimeout(20, TimeUnit.SECONDS)
    .readTimeout(30, TimeUnit.SECONDS)
    .writeTimeout(30, TimeUnit.SECONDS)
    .followRedirects(true)
    .build()

/** 拦截时返回的空响应（403，空 body）。 */
private fun blockedResponse(): WebResourceResponse =
    WebResourceResponse(
        "text/plain",
        "utf-8",
        403,
        "Blocked",
        emptyMap<String, String>(),
        ByteArrayInputStream(ByteArray(0))
    )

/** 用重写后的 URL 代取资源并回填给 WebView。 */
private fun proxyFetch(newUrl: String, request: WebResourceRequest): WebResourceResponse? {
    return try {
        val b = Request.Builder().url(newUrl)
        request.requestHeaders.forEach { (k, v) ->
            // Host 会由 OkHttp 按新地址重算；Accept-Encoding 固定 identity 以拿到原始字节
            if (!k.equals("Host", true) && !k.equals("Accept-Encoding", true)) {
                runCatching { b.header(k, v) }
            }
        }
        b.header("Accept-Encoding", "identity")

        val resp = surveyProxyClient.newCall(b.build()).execute()
        val body = resp.body ?: return null
        val ct = body.contentType()
        val mime = if (ct != null) "${ct.type}/${ct.subtype}" else "text/plain"
        val charset = ct?.charset()?.name() ?: "utf-8"
        val headers = HashMap<String, String>()
        resp.headers.forEach { (k, v) -> headers[k] = v }
        WebResourceResponse(
            mime,
            charset,
            resp.code,
            resp.message.ifEmpty { "OK" },
            headers,
            body.byteStream()
        )
    } catch (_: Exception) {
        null
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun SurveyWebScreen(
    startUrl: String,
    onClose: () -> Unit
) {
    var loading by remember { mutableStateOf(true) }
    var shownUrl by remember { mutableStateOf(startUrl) }
    var webRef by remember { mutableStateOf<WebView?>(null) }

    Column(Modifier.fillMaxSize()) {
        // 顶部：返回 / 刷新 / 当前域名 / 加载指示
        WebViewTopBar(
            title = Uri.parse(shownUrl).host ?: shownUrl,
            loading = loading,
            onRefresh = { webRef?.reload() },
            onClose = onClose
        )

        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                WebView(ctx).apply {
                    webRef = this
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.useWideViewPort = true
                    settings.loadWithOverviewMode = true
                    settings.javaScriptCanOpenWindowsAutomatically = true
                    settings.setSupportMultipleWindows(false)
                    settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
                    settings.userAgentString = settings.userAgentString + " MoonBazaarAndroid"

                    webViewClient = object : WebViewClient() {

                        // 主框架导航：拦截 & 重写
                        override fun shouldOverrideUrlLoading(
                            view: WebView?,
                            request: WebResourceRequest?
                        ): Boolean {
                            val u = request?.url?.toString() ?: return false
                            if (isBlockedSurveyUrl(u)) return true          // 直接拦截，不加载
                            val rw = rewriteSurveyUrl(u)
                            if (rw != u) {
                                view?.loadUrl(rw)
                                return true
                            }
                            return false
                        }

                        @Deprecated("Deprecated in Java")
                        override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                            val u = url ?: return false
                            if (isBlockedSurveyUrl(u)) return true
                            val rw = rewriteSurveyUrl(u)
                            if (rw != u) {
                                view?.loadUrl(rw)
                                return true
                            }
                            return false
                        }

                        // 子资源（JS / XHR / 图片等）：拦截 & 重写
                        override fun shouldInterceptRequest(
                            view: WebView?,
                            request: WebResourceRequest?
                        ): WebResourceResponse? {
                            val u = request?.url?.toString() ?: return null
                            if (isBlockedSurveyUrl(u)) return blockedResponse()
                            val rw = rewriteSurveyUrl(u)
                            if (rw != u) return proxyFetch(rw, request)
                            return null
                        }

                        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                            loading = true
                            if (url != null) shownUrl = url
                        }

                        override fun onPageFinished(view: WebView?, url: String?) {
                            loading = false
                            if (url != null) shownUrl = url
                        }
                    }

                    loadUrl(startUrl)
                }
            }
        )
    }
}
