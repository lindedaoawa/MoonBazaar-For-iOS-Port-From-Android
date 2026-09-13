package top.witzzz.moonbazaar

import android.app.Application
import android.content.Context
import top.witzzz.moonbazaar.data.Session

/** Application 入口：在进程启动时初始化 Session 持久化依赖。 */
class MoonBazaarApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Session.init(applicationContext)
    }
}
