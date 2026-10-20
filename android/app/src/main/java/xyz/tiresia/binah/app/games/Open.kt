package xyz.tiresia.binah.app.games

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import xyz.tiresia.binah.app.core.Item
import xyz.tiresia.binah.app.core.PlayContext
import xyz.tiresia.binah.app.core.get
import xyz.tiresia.binah.app.core.int
import xyz.tiresia.binah.app.core.list
import xyz.tiresia.binah.app.core.str
import xyz.tiresia.binah.app.core.strings
import xyz.tiresia.binah.app.core.wordCount
import xyz.tiresia.binah.app.ui.AnswerBox
import xyz.tiresia.binah.app.ui.Ask
import xyz.tiresia.binah.app.ui.BCard
import xyz.tiresia.binah.app.ui.LocalBinah
import xyz.tiresia.binah.app.ui.Nav
import xyz.tiresia.binah.app.ui.Passage
import xyz.tiresia.binah.app.ui.SelfRating
import xyz.tiresia.binah.app.ui.SourceLine
import xyz.tiresia.binah.app.ui.readingStyle

// The games Claude grades against a hidden key: Gist & Infer, Subtext and Cut the Bloat. Each runs
// the same fixed order (OpenFlow): answer with a self-rating → verdict → one revision → reference.

/** "**Label** rest", for the reference cards. */
fun lead(label: String, rest: String): AnnotatedString = buildAnnotatedString {
    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(label) }
    append(" "); append(rest)
}

@Composable
fun Counter(left: String, right: String, bad: Boolean) {
    Row(Modifier.fillMaxWidth()) {
        Text(left, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
        Text(right, style = MaterialTheme.typography.bodySmall, color = if (bad) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

// MARK: Gist & Infer

/** Read the passage at your own pace, hide it, then write its point from memory in 20 words or
 *  fewer, and answer one inference question. */
@Composable
fun GistGame(item: Item, ctx: PlayContext, nav: Nav) {
    var hidden by rememberSaveable { mutableStateOf(false) }
    var gist by rememberSaveable { mutableStateOf("") }
    var inference by rememberSaveable { mutableStateOf("") }
    var selfRating by rememberSaveable { mutableStateOf<Int?>(null) }
    val started = remember { System.currentTimeMillis() }
    val flow = rememberOpenFlow()
    val focus = remember { FocusRequester() }
    fun answer() = mapOf("gist" to gist.trim(), "inference" to inference.trim())
    GameColumn(follow = flow.phase.takeIf { it != OpenFlow.Phase.Answering && it != OpenFlow.Phase.Revising }) {
        AnimatedContent(hidden, label = "gist") { h ->
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                if (!h) {
                    SourceLine(item.source)
                    Passage(item.passage ?: "")
                    Button(onClick = { hidden = true }, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("I've got it, hide the passage") }
                    Text("Read at your own pace. Rereading is fine.", style = MaterialTheme.typography.bodySmall,
                         color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.align(Alignment.CenterHorizontally))
                } else {
                    val n = wordCount(gist)
                    Ask("What's the main point? 20 words or fewer, from memory.")
                    Column(Modifier.focusRequester(focus)) { AnswerBox(gist, { gist = it }, "Your gist", minLines = 2, enabled = !flow.locked) }
                    Counter("the point, not the topic", "$n / 20", n > 20)
                    Ask(item.inference_q ?: "")
                    AnswerBox(inference, { inference = it }, "Your answer", minLines = 2, enabled = !flow.locked)
                    if (flow.phase == OpenFlow.Phase.Answering) SelfRating(selfRating) { selfRating = it }
                    OpenSend(flow, ready = n in 1..20, rated = selfRating != null,
                             onSend = { flow.send(item, answer(), selfRating, started, ctx) }, onRevise = { flow.reviseAgain(answer()) })
                    OpenFlowPanel(flow, ctx, nav) { a ->
                        val k = a.key
                        val covered = (a.grade2 ?: a.grade)["covered"].list.mapNotNull { it.int }.toSet()
                        BCard(title = "The reference") {
                            Text(k["gist"].str ?: "", style = readingStyle(17).copy(fontStyle = FontStyle.Italic))
                            k["key_points"].strings.forEachIndexed { i, p ->
                                val hit = (i + 1) in covered
                                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Icon(if (hit) Icons.Filled.CheckCircle else Icons.Outlined.Circle, null, Modifier.size(20.dp),
                                         tint = if (hit) LocalBinah.current.good else MaterialTheme.colorScheme.outline)
                                    Text(p, color = if (hit) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                            k["inference_a"].str?.let { Text(lead("The inference:", it)) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: Subtext

/** What's really going on in a scene: the passage, then the question and your answer. */
@Composable
fun SubtextGame(item: Item, ctx: PlayContext, nav: Nav) {
    var text by rememberSaveable { mutableStateOf("") }
    var selfRating by rememberSaveable { mutableStateOf<Int?>(null) }
    val started = remember { System.currentTimeMillis() }
    val flow = rememberOpenFlow()
    GameColumn(follow = flow.phase.takeIf { it != OpenFlow.Phase.Answering && it != OpenFlow.Phase.Revising }) {
        SourceLine(item.source)
        Passage(item.passage ?: "")
        Ask(item.question ?: "")
        AnswerBox(text, { text = it }, "Your answer", minLines = 4, enabled = !flow.locked)
        if (flow.phase == OpenFlow.Phase.Answering) SelfRating(selfRating) { selfRating = it }
        OpenSend(flow, ready = text.isNotBlank(), rated = selfRating != null,
                 onSend = { flow.send(item, mapOf("text" to text.trim()), selfRating, started, ctx) },
                 onRevise = { flow.reviseAgain(mapOf("text" to text.trim())) })
        OpenFlowPanel(flow, ctx, nav) { a ->
            BCard(title = "What's going on") {
                Text(a.key["answer"].str ?: "")
                a.key["evidence_quote"].str?.takeIf { it.isNotBlank() }?.let {
                    Text("It shows in: “$it”", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

// MARK: Cut the Bloat

fun golf(d: Int) = when {
    d <= -2 -> "Eagle"; d == -1 -> "Birdie"; d == 0 -> "Par"; d == 1 -> "Bogey"; d == 2 -> "Double bogey"; else -> "+$d"
}

/** Someone padded a good writer's sentence; cut it back without changing what it says. Par is the
 *  author's own word count, and the score is golf. */
@Composable
fun BloatGame(item: Item, ctx: PlayContext, nav: Nav) {
    var text by rememberSaveable { mutableStateOf(item.padded ?: "") }
    var selfRating by rememberSaveable { mutableStateOf<Int?>(null) }
    val started = remember { System.currentTimeMillis() }
    val flow = rememberOpenFlow()
    val n = wordCount(text)
    val par = item.par ?: 0
    val d = n - par
    val b = LocalBinah.current
    GameColumn(follow = flow.phase.takeIf { it != OpenFlow.Phase.Answering && it != OpenFlow.Phase.Revising }) {
        SourceLine(item.source)
        Ask("Someone padded a good writer's sentence. Cut it back without changing what it says. Par is the author's own word count.")
        AnswerBox(text, { text = it }, "Your cut", minLines = 5, enabled = !flow.locked, reading = true)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("$n words · par $par", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
            Text(golf(d), fontWeight = FontWeight.SemiBold, color = when { d <= 0 -> b.good; d > 2 -> MaterialTheme.colorScheme.error; else -> MaterialTheme.colorScheme.onSurfaceVariant })
        }
        if (flow.phase == OpenFlow.Phase.Answering) SelfRating(selfRating) { selfRating = it }
        OpenSend(flow, ready = n > 0, rated = selfRating != null, title = "Putt", again = "Putt again",
                 onSend = { flow.send(item, mapOf("text" to text.trim()), selfRating, started, ctx) },
                 onRevise = { flow.reviseAgain(mapOf("text" to text.trim())) })
        OpenFlowPanel(flow, ctx, nav) { a ->
            BCard(title = "The author's line · $par words") {
                Text(a.key["original"].str ?: "", style = readingStyle(17).copy(fontStyle = FontStyle.Italic))
                a.instant["golf"].str?.let {
                    Text("You: ${a.instant["words"].int ?: n} words, $it", style = MaterialTheme.typography.bodySmall,
                         color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        Spacer(Modifier.height(1.dp))
    }
}
