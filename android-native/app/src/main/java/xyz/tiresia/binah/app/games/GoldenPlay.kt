package xyz.tiresia.binah.app.games

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import xyz.tiresia.binah.app.core.Api
import xyz.tiresia.binah.app.core.AppModel
import xyz.tiresia.binah.app.core.Criteria
import xyz.tiresia.binah.app.core.Games
import xyz.tiresia.binah.app.core.GoldenInfo
import xyz.tiresia.binah.app.core.GoldenKey
import xyz.tiresia.binah.app.core.Item
import xyz.tiresia.binah.app.core.Rubric
import xyz.tiresia.binah.app.core.get
import xyz.tiresia.binah.app.core.str
import xyz.tiresia.binah.app.core.strings
import xyz.tiresia.binah.app.ui.AnswerBox
import xyz.tiresia.binah.app.ui.Ask
import xyz.tiresia.binah.app.ui.BCard
import xyz.tiresia.binah.app.ui.GameBar
import xyz.tiresia.binah.app.ui.Nav
import xyz.tiresia.binah.app.ui.Passage
import xyz.tiresia.binah.app.ui.SourceLine
import xyz.tiresia.binah.app.ui.Waiting
import xyz.tiresia.binah.app.ui.readingStyle

/** The golden set: answer an item yourself, see the key, then score your own answer with the same
 *  anchors Claude uses. Claude grades the same answer blind in the background (docs/API.md). */
@Composable
fun GoldenPlay(itemId: String, model: AppModel, nav: Nav) {
    var item by remember { mutableStateOf<Item?>(null) }
    var rubric by remember { mutableStateOf<Rubric?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    var hidden by remember { mutableStateOf(false) }
    var a1 by remember { mutableStateOf("") }
    var a2 by remember { mutableStateOf("") }
    var key by remember { mutableStateOf<JsonElement?>(null) }
    val mine = remember { mutableStateMapOf<String, Int>() }
    var saved by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var passageAgain by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val cs = MaterialTheme.colorScheme

    LaunchedEffect(itemId) {
        try {
            coroutineScope {
                val i = async { Api.get<Item>("/api/item/${Api.escape(itemId)}") }
                val g = async { Api.get<GoldenInfo>("/api/golden") }
                val it = i.await()
                item = it
                rubric = g.await().rubrics[it.game]
                if (it.game == "bloat") a1 = it.padded ?: ""
            }
        } catch (e: Exception) { problem = e.message }
    }

    Column(Modifier.fillMaxSize()) {
        GameBar("Golden set · " + Games.name(item?.game ?: itemId.substringBefore(':')), "Score your own answer", { nav.back() })
        val it = item
        val r = rubric
        if (it == null || r == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { problem?.let { p -> Text(p, color = cs.error) } ?: Waiting("Opening…") }
            return@Column
        }
        GameColumn {
            problem?.let { p -> Text(p, color = cs.error) }
            val locked = key != null
            val scoreButton: @Composable () -> Unit = {
                Button(onClick = {
                    if (a1.isBlank() && a2.isBlank()) { model.flash("Write an answer first"); return@Button }
                    scope.launch { runCatching { Api.get<GoldenKey>("/api/golden/key/${Api.escape(itemId)}") }.onSuccess { k -> key = k.key }.onFailure { e -> problem = e.message } }
                }, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("Now score it yourself") }
            }
            when (it.game) {
                "gist" -> if (!hidden) {
                    SourceLine(it.source)
                    Passage(it.passage ?: "")
                    Button(onClick = { hidden = true }, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("Hide it and write") }
                } else {
                    Ask("The main point, 20 words or fewer.")
                    AnswerBox(a1, { v -> a1 = v }, "Your gist", minLines = 2, enabled = !locked)
                    Ask(it.inference_q ?: "")
                    AnswerBox(a2, { v -> a2 = v }, "Your answer", minLines = 2, enabled = !locked)
                    if (!locked) scoreButton()
                }
                "subtext" -> {
                    SourceLine(it.source)
                    Passage(it.passage ?: "")
                    Ask(it.question ?: "")
                    AnswerBox(a1, { v -> a1 = v }, "Your answer", minLines = 4, enabled = !locked)
                    if (!locked) scoreButton()
                }
                else -> {
                    Ask("Cut it back to the author's line (par ${it.par ?: 0}).")
                    AnswerBox(a1, { v -> a1 = v }, "Your cut", minLines = 5, enabled = !locked, reading = true)
                    if (!locked) scoreButton()
                }
            }
            val k = key ?: return@GameColumn
            if (it.game == "gist") {
                TextButton(onClick = { passageAgain = !passageAgain }) { Text(if (passageAgain) "Hide the passage" else "The passage again") }
                if (passageAgain) Passage(it.passage ?: "", size = 15)
            }
            BCard(title = "The key") {
                Text(k["gist"].str ?: k["answer"].str ?: k["original"].str ?: "", style = readingStyle(17).copy(fontStyle = FontStyle.Italic))
                k["key_points"].strings.forEach { p -> Text("• $p") }
                k["inference_a"].str?.let { inf -> Text(lead("Inference:", inf)) }
            }
            if (saved) {
                BCard {
                    Text("Saved to the golden set", style = MaterialTheme.typography.titleLarge)
                    Text("Claude grades your answer blind in the background, and the agreement report updates.", color = cs.onSurfaceVariant)
                }
                Button(onClick = { nav.back() }, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("Back to the golden set") }
            } else {
                Text("Score your own answer the way a strict, fair editor would. These are the same anchors Claude uses.", color = cs.onSurfaceVariant)
                r.ordered.forEach { c ->
                    val levels = r.criteria[c] ?: emptyList()
                    BCard {
                        Text(Criteria.label(c).capitalizedFirst(), fontWeight = FontWeight.SemiBold)
                        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                            levels.indices.forEach { n ->
                                SegmentedButton(mine[c] == n, { mine[c] = n }, SegmentedButtonDefaults.itemShape(n, levels.size)) { Text("$n") }
                            }
                        }
                        Text(mine[c]?.let { n -> "$n: ${levels.getOrElse(n) { "" }}" } ?: "Pick a score to see what it means.",
                             style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
                    }
                }
                Button(onClick = {
                    busy = true
                    val answer = if (it.game == "gist") mapOf("gist" to a1.trim(), "inference" to a2.trim()) else mapOf("text" to a1.trim())
                    scope.launch {
                        runCatching { Api.post<JsonElement>("/api/golden", mapOf("item_id" to it.id, "answer" to answer, "mine" to mine.toMap())) }
                            .onSuccess { saved = true; model.refresh() }.onFailure { e -> problem = e.message }
                        busy = false
                    }
                }, enabled = !busy && mine.size >= r.criteria.size, modifier = Modifier.fillMaxWidth().height(52.dp)) {
                    Text(if (busy) "Saving…" else "Save to the golden set")
                }
            }
        }
    }
}
