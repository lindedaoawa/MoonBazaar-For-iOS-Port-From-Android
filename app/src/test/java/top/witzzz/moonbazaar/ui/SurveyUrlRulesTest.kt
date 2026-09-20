package top.witzzz.moonbazaar.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 问卷 WebView 的 URL 重写 / 拦截规则单测。
 */
class SurveyUrlRulesTest {

    // ---------------- 重写（必须保留全部参数） ----------------

    @Test
    fun recaptcha_isRewritten_andQueryKept() {
        val src = "https://www.google.com/recaptcha/api.js?render=explicit&hl=zh-CN&onload=cb"
        val dst = "https://www.recaptcha.net/recaptcha/api.js?render=explicit&hl=zh-CN&onload=cb"
        assertEquals(dst, rewriteSurveyUrl(src))
    }

    @Test
    fun ajaxGoogleapis_isRewritten() {
        val src = "https://ajax.googleapis.com/ajax/libs/jquery/3.6.0/jquery.min.js"
        val dst = "https://ajax.loli.net/ajax/libs/jquery/3.6.0/jquery.min.js"
        assertEquals(dst, rewriteSurveyUrl(src))
    }

    @Test
    fun ipify_isRewritten_toApi64_andQueryKept() {
        assertEquals(
            "https://api64.ipify.org?format=json&callback=x",
            rewriteSurveyUrl("https://api.ipify.org?format=json&callback=x")
        )
    }

    @Test
    fun unrelatedUrl_isUntouched() {
        val src = "https://click.cpx-research.com/?k=abc&api=true&time_stamp=1789301109&subid_1=&is_p=2"
        assertEquals(src, rewriteSurveyUrl(src))
    }

    @Test
    fun alreadyRewritten_isIdempotent() {
        val once = rewriteSurveyUrl("https://api.ipify.org?format=json")
        assertEquals(once, rewriteSurveyUrl(once))
    }

    // ---------------- 拦截 ----------------

    @Test
    fun blockedTargets_areBlocked() {
        assertTrue(isBlockedHostPath("firebase.googleapis.com", "/v1/projects/x"))
        assertTrue(isBlockedHostPath("analytics.tiktok.com", "/i18n/pixel/events.js"))
        assertTrue(isBlockedHostPath("connect.facebook.net", "/en_US/sdk.js"))
        assertTrue(isBlockedHostPath("www.google.com", "/jsapi"))
        assertTrue(isBlockedHostPath("accounts.google.com", "/gsi/client"))
    }

    @Test
    fun blockedTargets_areCaseInsensitive() {
        assertTrue(isBlockedHostPath("WWW.Google.COM", "/jsapi"))
        assertTrue(isBlockedHostPath("Firebase.Googleapis.com", "/v1/x"))
    }

    @Test
    fun rewrittenTargets_areNotBlocked() {
        // 这些应被重写而不是拦截
        assertFalse(isBlockedHostPath("www.google.com", "/recaptcha/api.js"))
        assertFalse(isBlockedHostPath("ajax.googleapis.com", "/ajax/libs/x.js"))
        assertFalse(isBlockedHostPath("api.ipify.org", "/"))
    }

    @Test
    fun similarHosts_areNotBlocked() {
        // 不能误伤：仅精确匹配主机名
        assertFalse(isBlockedHostPath("google.com", "/jsapi"))
        assertFalse(isBlockedHostPath("example.com", "/jsapi"))
        assertFalse(isBlockedHostPath("notfirebase.googleapis.com", "/v1/x"))
        assertFalse(isBlockedHostPath("www.google.com", "/jsapi2-other"))
    }
}
