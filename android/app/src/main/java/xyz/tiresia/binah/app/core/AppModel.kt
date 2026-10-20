package xyz.tiresia.binah.app.core

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The app's shared state: signed in or not, today, the counts beside the tabs, and a toast. */
class AppModel : ViewModel() {
    var signedIn by mutableStateOf(Token.get(Api.app) != null)
    var today by mutableStateOf<TodayInfo?>(null)
    var nav by mutableStateOf<Nav?>(null)
    var toast by mutableStateOf<String?>(null)
    /** Bumped whenever today may have moved, so screens that show it load again. */
    var version by mutableIntStateOf(0)
    private var toastJob: Job? = null

    init {
        Api.onSignedOut = { signOut(expired = true) }
    }

    fun refresh() {
        if (!signedIn) return
        viewModelScope.launch {
            val n = async { runCatching { Api.get<Nav>("/api/nav") }.getOrNull() }
            val t = async { runCatching { Api.get<TodayInfo>("/api/today") }.getOrNull() }
            n.await()?.let { nav = it }
            t.await()?.let { today = it }
            version++
        }
    }

    fun flash(text: String) {
        toast = text
        toastJob?.cancel()
        toastJob = viewModelScope.launch { delay(2800); if (toast == text) toast = null }
    }

    fun signedIn() {
        signedIn = true
        refresh()
    }

    fun signOut(expired: Boolean = false) {
        Token.set(Api.app, null)
        signedIn = false
        today = null
        nav = null
        if (expired) flash("Binah asked for a fresh sign-in.")
    }
}

/** Where a game was opened from: one of today's slots (it counts for today) or Practice. */
data class PlayContext(val game: String, val day: String?, val slot: Int?) {
    val fromToday get() = day != null
    val nextTitle get() = if (fromToday) "Back to Today" else "Another one"
    fun subtitle(today: TodayInfo?): String {
        val p = Games.pillarNames[Games.pillar[game]] ?: ""
        val n = today?.edition?.slots?.size ?: 3
        val where = if (fromToday) "game ${(slot ?: 0) + 1} of $n in today's edition" else "Practice"
        return if (p.isEmpty()) where else "$p · $where"
    }
}

/** POST /api/attempts, with the day and slot when the game is one of today's. */
suspend fun submitAnswer(item: Item, answer: Map<String, Any?>, selfRating: Int?, startedMs: Long, ctx: PlayContext): Attempt =
    Api.post("/api/attempts", mapOf("item_id" to item.id, "answer" to answer, "self_rating" to selfRating,
                                    "ms" to (System.currentTimeMillis() - startedMs), "day" to ctx.day, "slot" to ctx.slot))

fun Context.appModelPrefs() = Server.prefs(this)
