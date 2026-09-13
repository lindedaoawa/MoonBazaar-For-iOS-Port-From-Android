package top.witzzz.moonbazaar

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import top.witzzz.moonbazaar.data.AppConfig
import top.witzzz.moonbazaar.data.Session
import top.witzzz.moonbazaar.ui.MainViewModel
import top.witzzz.moonbazaar.ui.MoonApp
import top.witzzz.moonbazaar.ui.WebLoginScreen
import top.witzzz.moonbazaar.ui.theme.MyApplicationTheme

class MainActivity : ComponentActivity() {

    private val viewModel: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Still accept a deep link that carries a token (defensive).
        captureSessionFromIntent(intent)

        setContent {
            Root()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureSessionFromIntent(intent)
    }

    @Composable
    private fun Root() {
        var showLogin by remember { mutableStateOf(false) }

        MyApplicationTheme {
            Box(Modifier.fillMaxSize()) {
                MoonApp(
                    vm = viewModel,
                    openUrl = ::openExternal,
                    onStartLogin = { showLogin = true }
                )

                if (showLogin) {
                    WebLoginScreen(
                        startUrl = AppConfig.BASE_URL.trimEnd('/') + "/auth/login",
                        onToken = { token ->
                            // 新登录：加入账号列表并设为当前，再拉取数据
                            Session.addAndSelect(token)
                            viewModel.refreshAuthState()
                            viewModel.reloadAll()
                            showLogin = false
                        },
                        onClose = { showLogin = false }
                    )
                }
            }
        }
    }

    private fun captureSessionFromIntent(i: Intent?) {
        val data = i?.data ?: return
        if (data.scheme?.equals(AppConfig.CALLBACK_SCHEME, ignoreCase = true) != true) return
        val token = data.getQueryParameter("session_token")
        if (!token.isNullOrBlank()) {
            Session.addAndSelect(token)
            viewModel.refreshAuthState()
            viewModel.reloadAll()
        }
    }

    private fun openExternal(url: String) {
        try {
            CustomTabsIntent.Builder().setShowTitle(true).build()
                .launchUrl(this, Uri.parse(url))
        } catch (_: Exception) {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }
    }
}
