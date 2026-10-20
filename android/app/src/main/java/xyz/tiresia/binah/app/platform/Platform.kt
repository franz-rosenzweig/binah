package xyz.tiresia.binah.app.platform

import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Bundle
import android.util.SizeF
import android.widget.RemoteViews
import android.widget.TextView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import xyz.tiresia.binah.app.MainActivity
import xyz.tiresia.binah.app.R
import xyz.tiresia.binah.app.core.Api
import xyz.tiresia.binah.app.core.ApiError
import xyz.tiresia.binah.app.core.Saved
import xyz.tiresia.binah.app.core.Server
import xyz.tiresia.binah.app.core.Token
import xyz.tiresia.binah.app.core.Widget
import java.time.LocalDate
import kotlin.math.roundToInt

/**
 * Today's edition on the home screen: a ring of the games done with the count in it, and on the 4×2
 * the next game, the minutes left and the week. Tap: Today.
 *
 * It asks /api/widget with the phone's token, gently: when it's placed, every half hour (Android's
 * own update), on unlock at most every 15 minutes, and when the app goes to the background. If
 * Binah can't be reached it keeps the last numbers, dimmed.
 */
open class TodayWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, widgets: AppWidgetManager, ids: IntArray) {
        render(context)
        val done = goAsync()
        CoroutineScope(Dispatchers.IO).launch { try { fetch(context.applicationContext) } finally { done.finish() } }
    }

    override fun onAppWidgetOptionsChanged(context: Context, widgets: AppWidgetManager, id: Int, options: Bundle) = render(context)

    companion object {
        private const val KEPT = "widget.json"
        private const val AT = "widget.at"
        private const val FAILED = "widget.failed"
        @Volatile private var asking = false

        /** Asks again if the last answer is older than this, in the background. */
        fun refreshIfOlder(c: Context, ms: Long) {
            val app = c.applicationContext
            if (System.currentTimeMillis() - Server.prefs(app).getLong(AT, 0) < ms || asking) return
            if (!placed(app)) return
            CoroutineScope(Dispatchers.IO).launch { fetch(app) }
        }

        private fun placed(c: Context) = AppWidgetManager.getInstance(c).getAppWidgetIds(ComponentName(c, xyz.tiresia.binah.Widget::class.java)).isNotEmpty()

        /** /api/widget, kept, then every placed widget drawn again. */
        suspend fun fetch(c: Context) {
            if (asking || Token.get(c) == null) { render(c); return }
            asking = true
            val p = Server.prefs(c)
            try {
                val text = Api.send("/api/widget", "GET", null, null)
                Api.json.decodeFromString<Widget>(text)     // only an answer the app can read is kept
                p.edit().putString(KEPT, text).putLong(AT, System.currentTimeMillis()).putBoolean(FAILED, false).apply()
            } catch (e: Exception) {
                p.edit().putBoolean(FAILED, true).apply()
            } finally {
                asking = false
                render(c)
            }
        }

        private fun kept(c: Context): Widget? =
            Server.prefs(c).getString(KEPT, null)?.let { runCatching { Api.json.decodeFromString<Widget>(it) }.getOrNull() }

        /** Every placed copy, in both sizes: the launcher shows whichever fits. */
        fun render(c: Context) {
            val widgets = AppWidgetManager.getInstance(c)
            val ids = widgets.getAppWidgetIds(ComponentName(c, xyz.tiresia.binah.Widget::class.java))
            if (ids.isEmpty()) return
            val w = kept(c).takeIf { Token.get(c) != null }
            val dim = w == null || Server.prefs(c).getBoolean(FAILED, false) || w.day != LocalDate.now().toString()
            val sizes = mapOf(SizeF(100f, 100f) to views(c, R.layout.widget_small, w, dim),
                              SizeF(240f, 100f) to views(c, R.layout.widget_wide, w, dim))
            for (id in ids) widgets.updateAppWidget(id, RemoteViews(sizes))
        }

        private fun views(c: Context, layout: Int, w: Widget?, dim: Boolean): RemoteViews {
            val v = RemoteViews(c.packageName, layout)
            val done = w?.done ?: 0
            val total = w?.total ?: 0
            val finished = w?.finished == true
            v.setProgressBar(R.id.ring, 100, if (total > 0) minOf(100, 100 * done / total) else 0, false)
            v.setTextViewText(R.id.count, if (w == null) "ב" else if (finished) "✓" else "$done/$total")
            v.setTextViewText(R.id.label, if (w == null) "Sign in to Binah" else if (finished) "Done today" else "Today")
            if (layout == R.layout.widget_wide) {
                val left = (w?.minutes_left ?: 0.0).roundToInt()
                when {
                    w == null -> {
                        v.setTextViewText(R.id.title, "Today's edition")
                        v.setTextViewText(R.id.detail, "Open Binah and sign in to connect this phone.")
                    }
                    finished -> {
                        v.setTextViewText(R.id.title, "Today's edition is done.")
                        v.setTextViewText(R.id.detail, "Anything else today is extra, in Practice.")
                    }
                    else -> {
                        v.setTextViewText(R.id.title, w.next?.name ?: "Today's edition")
                        v.setTextViewText(R.id.detail, "$done of $total games" + if (left > 0) " · about $left min left" else "")
                    }
                }
                v.setTextViewText(R.id.week, w?.week?.let { "This week: ${it.active} of ${it.goal} days" } ?: "")
                if (dim) v.setColorStateList(R.id.title, "setTextColor", R.color.widgetText2)
            }
            if (dim) {
                v.setColorStateList(R.id.count, "setTextColor", R.color.widgetText2)
                v.setColorStateList(R.id.ring, "setProgressTintList", R.color.widgetText2)
            }
            v.setOnClickPendingIntent(R.id.root, PendingIntent.getActivity(c, 1, MainActivity.open(c, "today"),
                                                                           PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            return v
        }
    }
}

/** Long-press Binah's icon: Today, Practice, Skills and Settings. */
object Shortcuts {
    fun publish(c: Context) {
        val sm = c.getSystemService(ShortcutManager::class.java) ?: return
        fun one(id: String, label: String, long: String?, icon: Int) = ShortcutInfo.Builder(c, id).setShortLabel(label)
            .apply { if (long != null) setLongLabel(long) }
            .setIcon(Icon.createWithResource(c, icon)).setIntent(MainActivity.open(c, id)).build()
        runCatching {
            sm.dynamicShortcuts = listOf(
                one("today", "Today", "Today's edition", R.drawable.ic_shortcut_today),
                one("practice", "Practice", null, R.drawable.ic_shortcut_practice),
                one("skills", "Skills", null, R.drawable.ic_shortcut_skills),
                one("settings", "Settings", "Binah settings", R.drawable.ic_shortcut_settings),
            )
        }   // a launcher's limit on shortcuts: nothing lost but them
    }
}

/**
 * Train on this, from any app's share sheet, with a card at the bottom saying what happened. A link,
 * or a passage of 20 words or more, goes to /api/save with this phone's token; Binah keeps it for
 * later practice, and the card shows what it said. Tap the card for Today.
 */
class ShareActivity : Activity() {
    private val scope = MainScope()
    private lateinit var title: TextView
    private lateinit var detail: TextView
    private var saved = false

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        Api.app = applicationContext
        setContentView(R.layout.share)
        title = findViewById(R.id.shareTitle)
        detail = findViewById(R.id.shareDetail)
        findViewById<android.view.View>(R.id.shareRoot).setOnClickListener { finish() }
        findViewById<android.view.View>(R.id.card).setOnClickListener {
            if (saved) startActivity(MainActivity.open(this, "today"))
            finish()
        }
        val (url, passage, name) = what(intent.getStringExtra(Intent.EXTRA_TEXT), intent.getStringExtra(Intent.EXTRA_SUBJECT))
        detail.text = name?.takeIf { it.isNotEmpty() } ?: url?.let { Uri.parse(it).host } ?: passage?.let { if (it.length > 80) it.take(80) + "…" else it } ?: ""
        scope.launch {
            try {
                if (url == null && passage == null) throw ApiError(0, "Nothing to send: share a link or some text.")
                if (Token.get(applicationContext) == null) throw ApiError(401, "Open Binah and sign in first; then share again.")
                val said = Api.post<Saved>("/api/save", buildMap {
                    url?.let { put("url", it) }; passage?.let { put("text", it) }; name?.let { put("title", it) }
                })
                saved = true
                say("Sent to Binah", said.message ?: "Saved.")
                delay(4000)
            } catch (e: Exception) {
                say("Not sent", e.message ?: "")
                delay(4500)
            }
            finish()
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun say(t: String, d: String) { title.text = t; detail.text = d }

    companion object {
        private val LINK = Regex("https?://\\S+")

        /** What was shared, as (url, passage, title): a link with a few words is the link (the words
         *  its title); 20 words or more are a passage, with the link if there was one. */
        fun what(text: String?, subject: String?): Triple<String?, String?, String?> {
            val t = text?.trim() ?: ""
            val link = LINK.find(t)?.value
            val rest = if (link == null) t else t.replace(link, "").trim()
            val passage = rest.split(Regex("\\s+")).size >= 20
            val title = subject?.trim()?.takeIf { it.isNotEmpty() } ?: if (link != null && !passage && rest.isNotEmpty()) rest else null
            return when {
                passage -> Triple(link, rest, title)
                link != null -> Triple(link, null, title)
                else -> Triple(null, t.ifEmpty { null }, title)
            }
        }
    }
}
