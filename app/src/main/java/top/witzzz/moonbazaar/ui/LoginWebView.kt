package top.witzzz.moonbazaar.ui

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.net.Uri
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebViewDatabase
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.viewinterop.AndroidView
import top.witzzz.moonbazaar.data.AppConfig

// ---- In-app WebView OAuth ----
// The Worker finishes auth on an HTML page: /auth/done?auth=ok&uid=..&session_token=..
// A system browser cannot jump back, so we keep the flow inside a WebView and the
// moment the page lands on /auth/done we capture the token and close.
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun WebLoginScreen(
    startUrl: String,
    onToken: (String) -> Unit,
    onClose: () -> Unit
) {
    var loading by remember { mutableStateOf(true) }
    var captured by remember { mutableStateOf(false) }  // block after we got the token

    Box(Modifier.fillMaxSize()) {
        if (loading) {
            CircularProgressIndicator(Modifier.align(Alignment.Center),
                color = Color(0xFF6650a4))
        }
        AndroidView(
            factory = { ctx ->
                // 每次打开登录页（含「添加账号」）先清空 WebView 的 Cookie 与浏览器数据，
                // 避免复用上一个账号的登录态、直接跳过授权。
                runCatching {
                    CookieManager.getInstance().apply {
                        removeAllCookies(null)
                        flush()
                    }
                    WebStorage.getInstance().deleteAllData()
                    WebViewDatabase.getInstance(ctx).apply {
                        clearFormData()
                        clearHttpAuthUsernamePassword()
                    }
                }

                WebView(ctx).apply {
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                    // 清掉该 WebView 实例的缓存与历史
                    clearCache(true)
                    clearHistory()
                    clearFormData()
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.useWideViewPort = true
                    settings.loadWithOverviewMode = true
                    settings.cacheMode = android.webkit.WebSettings.LOAD_NO_CACHE
                    webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            view: WebView?, request: WebResourceRequest?
                        ): Boolean {
                            val u = request?.url?.toString() ?: return false
                            return tryFinish(u, view)
                        }

                        @Deprecated("Deprecated in Java")
                        override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                            return tryFinish(url ?: return false, view)
                        }

                        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                            if (url != null) tryFinish(url, view)
                            loading = true
                        }

                        override fun onPageFinished(view: WebView?, url: String?) {
                            loading = false
                        }

                        // returns true means we handled (stop) the load
                        private fun tryFinish(url: String, view: WebView?): Boolean {
                            val u = Uri.parse(url)
                            if (u.scheme?.equals("https", true) == true &&
                                u.host?.equals(AppConfig.BASE_HOST, true) == true &&
                                u.path.orEmpty().startsWith("/auth/done")
                            ) {
                                if (!captured) {
                                    captured = true
                                    val token = u.getQueryParameter("session_token")
                                    if (!token.isNullOrBlank()) {
                                        onToken(token)
                                    } else {
                                        onClose()   // reached done but no token
                                    }
                                    if (view != null) {
                                        view.stopLoading()
                                        (view.parent as? ViewGroup)?.removeView(view)
                                    }
                                }
                                return true
                            }
                            return false
                        }
                    }
                    loadUrl(startUrl)
                }
            },
            update = { }
        )
    }
}
