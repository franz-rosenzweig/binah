package xyz.tiresia.binah.app

import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.mutableStateOf
import xyz.tiresia.binah.app.core.Api
import xyz.tiresia.binah.app.core.AppModel
import xyz.tiresia.binah.app.core.Server
import xyz.tiresia.binah.app.core.Token
import xyz.tiresia.binah.app.platform.Shortcuts
import xyz.tiresia.binah.app.platform.TodayWidget
import xyz.tiresia.binah.app.ui.BinahTheme
import xyz.tiresia.binah.app.ui.Root

/** The process: the API client's context. */
/** The process: the API client's context, and the widget asking again when the phone is unlocked,
 *  at most every 15 minutes (Android tells only a running process). */
class BinahApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Api.app = this
        val unlocked = object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) = TodayWidget.refreshIfOlder(c, 15 * 60_000L)
        }
        registerReceiver(unlocked, IntentFilter(Intent.ACTION_USER_PRESENT), RECEIVER_NOT_EXPORTED)
    }
}

/**
 * Binah for Android, native: Kotlin and Jetpack Compose over Binah's JSON API (docs/API.md). The
 * widget, the shortcuts and the share card open it on a room ("today", "practice", …) with the
 * extra [EXTRA_ROUTE].
 */
class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()
    /** A room asked for from outside (the widget, a shortcut), for Root to go to. */
    val pending = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Api.app = applicationContext
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (debuggable) debugExtras(intent)
        enableEdgeToEdge()
        pending.value = route(intent)
        val selfTest = debuggable && intent.getBooleanExtra("binah.selftest", false)
        if (selfTest) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)     // the pictures need the screen
        setContent { BinahTheme { Root(model, pending, selfTest) } }
        Shortcuts.publish(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pending.value = route(intent)
    }

    override fun onResume() {
        super.onResume()
        model.refresh()
    }

    /** Leaving the app: the widget catches up with what was just played. */
    override fun onStop() {
        super.onStop()
        TodayWidget.refreshIfOlder(this, 0)
    }

    /** The test build is pointed at a sandbox by check.sh, never the real Binah. */
    private fun debugExtras(i: Intent) {
        i.getStringExtra("binah.base")?.let { Server.setBase(this, it) }
        i.getStringExtra("binah.token")?.let { Token.set(this, it.takeIf { t -> t != "-" }) }
        model.signedIn = Token.get(this) != null
    }

    companion object {
        const val EXTRA_ROUTE = "binah.route"

        fun open(c: Context, route: String): Intent =
            Intent(c, MainActivity::class.java).setAction(Intent.ACTION_VIEW)
                .setData(Uri.parse("binah://go/$route"))     // distinct data, so PendingIntents for rooms stay apart
                .putExtra(EXTRA_ROUTE, route)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)

        /** "today", from the extra or binah://go/today; the WebView app's "#today" too, which a
         *  shortcut pinned before the update may still send. */
        fun route(i: Intent?): String? = (i?.getStringExtra(EXTRA_ROUTE)
            ?: i?.data?.takeIf { it.host == "go" }?.pathSegments?.firstOrNull())?.removePrefix("#")?.takeIf { it.isNotEmpty() }
    }
}
