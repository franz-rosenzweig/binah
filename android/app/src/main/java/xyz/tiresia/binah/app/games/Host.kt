package xyz.tiresia.binah.app.games

import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import xyz.tiresia.binah.app.core.Api
import xyz.tiresia.binah.app.core.AppModel
import xyz.tiresia.binah.app.core.Attempt
import xyz.tiresia.binah.app.core.Games
import xyz.tiresia.binah.app.core.Item
import xyz.tiresia.binah.app.core.PlayContext
import xyz.tiresia.binah.app.core.submitAnswer
import xyz.tiresia.binah.app.ui.BCard
import xyz.tiresia.binah.app.ui.GameBar
import xyz.tiresia.binah.app.ui.Nav
import xyz.tiresia.binah.app.ui.RatingDelta
import xyz.tiresia.binah.app.ui.VerdictCard
import xyz.tiresia.binah.app.ui.Waiting

/** One game on screen: its bar, then the item loaded and the game's own view. */
@Composable
fun GameScreen(ctx: PlayContext, ids: List<String>, model: AppModel, nav: Nav) {
    var item by remember { mutableStateOf<Item?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(ids.firstOrNull()) {
        if (ctx.game == "tech") return@LaunchedEffect
        val id = ids.firstOrNull() ?: run { problem = "Nothing to play here yet."; return@LaunchedEffect }
        runCatching { Api.get<Item>("/api/item/${Api.escape(id)}") }.onSuccess { item = it }.onFailure { problem = it.message }
    }
    Column(Modifier.fillMaxSize()) {
        GameBar(Games.name(ctx.game), ctx.subtitle(model.today), { nav.back() })
        val it = item
        when {
            ctx.game == "tech" -> TechRound(ids, ctx, nav)
            it != null -> when (ctx.game) {
                "gist" -> GistGame(it, ctx, nav)
                "subtext" -> SubtextGame(it, ctx, nav)
                "bloat" -> BloatGame(it, ctx, nav)
                "weak" -> WeakGame(it, ctx, nav)
                "word" -> WordGame(it, ctx, nav)
                "jam" -> JamGame(it, ctx, nav)
                else -> Note("This app doesn't know that game yet.")
            }
            problem != null -> Note("Couldn't open it. $problem")
            else -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Waiting("Opening…") }
        }
    }
}

@Composable
fun Note(text: String) {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** A game's column: scrolls, keeps clear of the keyboard, at a reading measure on wide screens.
 *  When [follow] changes to something (a result, a verdict), it scrolls down to show it. */
@Composable
fun GameColumn(follow: Any? = null, content: @Composable ColumnScope.() -> Unit) {
    val scroll = rememberScrollState()
    LaunchedEffect(follow) {
        if (follow == null) return@LaunchedEffect
        delay(120)      // the result's own height, laid out first
        scroll.animateScrollTo(scroll.maxValue)
    }
    Box(Modifier.fillMaxSize().imePadding(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 680.dp).fillMaxWidth().verticalScroll(scroll)
                   .padding(horizontal = 20.dp).padding(top = 4.dp, bottom = 32.dp).navigationBarsPadding(),
               verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
    }
}

object Haptic {
    fun confirm(v: View) = v.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
    fun reject(v: View) = v.performHapticFeedback(HapticFeedbackConstants.REJECT)
    fun tick(v: View) = v.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    fun verdict(v: View, good: Boolean) { if (good) confirm(v) else reject(v) }
}

/**
 * The fixed order of an open answer (gist, subtext, bloat): answer with a self-rating → Claude's
 * verdict → one revision → the reference. "Later" (the daily cap, or an error) is final for now:
 * no invented score, and the reference on request (docs/API.md, Answering).
 */
class OpenFlow(private val scope: CoroutineScope, private val view: View) {
    enum class Phase { Answering, Grading, Verdict, Revising, Regrading, Reference, Later }
    var phase by mutableStateOf(Phase.Answering)
    var attempt by mutableStateOf<Attempt?>(null)
    var problem by mutableStateOf<String?>(null)
    var disputed by mutableStateOf(false)
    val locked get() = phase != Phase.Answering && phase != Phase.Revising

    fun send(item: Item, answer: Map<String, Any?>, selfRating: Int?, started: Long, ctx: PlayContext) {
        phase = Phase.Grading
        problem = null
        scope.launch {
            try {
                val a0 = submitAnswer(item, answer, selfRating, started, ctx)
                attempt = a0
                val a = if (a0.grading) Api.waitFor(a0.id) { !it.grading || it.waitsForTomorrow } else a0
                attempt = a
                if (a.later || (a.grade == null && a.waitsForTomorrow)) phase = Phase.Later
                else { phase = Phase.Verdict; Haptic.verdict(view, (a.score ?: 0.0) >= 0.65) }
            } catch (e: Exception) {
                problem = e.message
                phase = if (attempt == null) Phase.Answering else Phase.Later
            }
        }
    }

    fun reveal() {
        val a = attempt ?: return
        scope.launch {
            runCatching { Api.post<Attempt>("/api/attempts/${a.id}/reveal") }
                .onSuccess { attempt = it; phase = Phase.Reference }.onFailure { problem = it.message }
        }
    }

    fun reviseAgain(answer: Map<String, Any?>) {
        val a = attempt ?: return
        phase = Phase.Regrading
        problem = null
        scope.launch {
            try {
                Api.post<Attempt>("/api/attempts/${a.id}/revise", mapOf("answer" to answer))
                var r = Api.waitFor(a.id) { it.grade2 != null || it.waitsForTomorrow }
                if (r.key == null) r = Api.post("/api/attempts/${a.id}/reveal")
                attempt = r
                phase = Phase.Reference
                if (r.grade2 == null) problem = "Claude reads the revision tomorrow: today's grading is used up."
            } catch (e: Exception) {
                problem = e.message
                phase = Phase.Revising
            }
        }
    }

    fun dispute() {
        val a = attempt ?: return
        scope.launch { runCatching { Api.post<JsonElement>("/api/attempts/${a.id}/dispute", mapOf("note" to "disputed from the result screen")) }; disputed = true }
    }
}

@Composable
fun rememberOpenFlow(): OpenFlow {
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    return remember { OpenFlow(scope, view) }
}

/** The send button of an open answer, or the revision's, by the flow's phase. */
@Composable
fun OpenSend(flow: OpenFlow, ready: Boolean, rated: Boolean, title: String = "Send to the grader", again: String = "Send the revision",
             onSend: () -> Unit, onRevise: () -> Unit) {
    when (flow.phase) {
        OpenFlow.Phase.Answering -> Button(onClick = onSend, enabled = ready && rated, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text(title) }
        OpenFlow.Phase.Revising -> Button(onClick = onRevise, enabled = ready, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text(again) }
        else -> {}
    }
}

/** Everything under an open answer once it's sent: waiting, the verdict, the choice to revise, and at
 *  the end the reference, the next step and the dispute. */
@Composable
fun OpenFlowPanel(flow: OpenFlow, ctx: PlayContext, nav: Nav, reference: @Composable (Attempt) -> Unit) {
    flow.problem?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    when (flow.phase) {
        OpenFlow.Phase.Answering -> {}
        OpenFlow.Phase.Grading -> Waiting("Claude is reading it against the hidden key…")
        OpenFlow.Phase.Verdict -> flow.attempt?.let { a ->
            VerdictCard(a)
            RatingDelta(a)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { flow.phase = OpenFlow.Phase.Revising }, modifier = Modifier.height(48.dp)) { Text("Revise once") }
                FilledTonalButton(onClick = { flow.reveal() }, modifier = Modifier.height(48.dp)) { Text("Keep it, show the reference") }
            }
        }
        OpenFlow.Phase.Revising -> Text("Change your answer above, then send it. The rating moves only on the first try.",
                                         style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        OpenFlow.Phase.Regrading -> Waiting("Claude is reading the revision…")
        OpenFlow.Phase.Later -> {
            BCard {
                Text("Grading later", style = MaterialTheme.typography.titleLarge)
                Text("Claude couldn't grade this right now. It will, and the score lands in your history.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            FilledTonalButton(onClick = { flow.reveal() }) { Text("Show the reference") }
        }
        OpenFlow.Phase.Reference -> flow.attempt?.let { a ->
            if (a.grade2 != null) VerdictCard(a, second = true)
            reference(a)
            EndButtons(ctx, nav, disputed = flow.disputed, onDispute = { flow.dispute() })
        }
    }
}

/** After a game: on to the next (today, or another round) and "I think this grade is wrong". */
@Composable
fun EndButtons(ctx: PlayContext, nav: Nav, attempt: Attempt? = null, disputed: Boolean = false, onDispute: (() -> Unit)? = null) {
    val scope = rememberCoroutineScope()
    var mine by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Button(onClick = { scope.launch { nav.finished(ctx) } }, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text(ctx.nextTitle) }
        if (disputed || mine) Text("Noted. It goes to your golden set.", style = MaterialTheme.typography.bodySmall,
                                   color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(8.dp))
        else if (onDispute != null || attempt != null) TextButton(onClick = {
            if (onDispute != null) onDispute() else attempt?.let { a ->
                scope.launch { runCatching { Api.post<JsonElement>("/api/attempts/${a.id}/dispute", mapOf("note" to "disputed from the result screen")) }; mine = true }
            }
        }) { Text("I think this grade is wrong") }
    }
}

/** A result in a quiet card: a headline in its colour, then what to know. */
@Composable
fun ResultCard(headline: String, color: androidx.compose.ui.graphics.Color, content: @Composable ColumnScope.() -> Unit) {
    BCard {
        Text(headline, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, color = color)
        content()
    }
}
