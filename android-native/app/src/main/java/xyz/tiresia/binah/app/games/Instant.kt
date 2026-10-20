package xyz.tiresia.binah.app.games

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import xyz.tiresia.binah.app.core.Api
import xyz.tiresia.binah.app.core.Attempt
import xyz.tiresia.binah.app.core.Discern
import xyz.tiresia.binah.app.core.Item
import xyz.tiresia.binah.app.core.PlayContext
import xyz.tiresia.binah.app.core.SkillsInfo
import xyz.tiresia.binah.app.core.bool
import xyz.tiresia.binah.app.core.dbl
import xyz.tiresia.binah.app.core.get
import xyz.tiresia.binah.app.core.int
import xyz.tiresia.binah.app.core.str
import xyz.tiresia.binah.app.core.submitAnswer
import xyz.tiresia.binah.app.ui.Ask
import xyz.tiresia.binah.app.ui.BCard
import xyz.tiresia.binah.app.ui.LocalBinah
import xyz.tiresia.binah.app.ui.Nav
import xyz.tiresia.binah.app.ui.RatingDelta
import xyz.tiresia.binah.app.ui.SourceLine
import xyz.tiresia.binah.app.ui.Waiting
import xyz.tiresia.binah.app.ui.readingStyle

// The games code scores at once: Find the Weak Step, The Author's Word and Technique or Fair Move?
// The answer comes back done, with the score, the rating's move and the key (docs/API.md).

fun String.capitalizedFirst() = replaceFirstChar { it.uppercase() }

// MARK: Find the Weak Step

/** An argument, a sentence at a time: pick where the reasoning is weakest (or call it sound), name
 *  the flaw, and optionally say why in one line, which Claude reads afterwards. */
@Composable
fun WeakGame(item: Item, ctx: PlayContext, nav: Nav) {
    val sound = "none (sound)"
    var pick by remember { mutableStateOf<Int?>(null) }
    var flaw by remember { mutableStateOf<String?>(null) }
    var why by remember { mutableStateOf("") }
    var attempt by remember { mutableStateOf<Attempt?>(null) }
    var sending by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    val started = remember { System.currentTimeMillis() }
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val b = LocalBinah.current
    val cs = MaterialTheme.colorScheme
    GameColumn(follow = attempt?.let { it.id to (it.grade != null) }) {
        SourceLine(item.source)
        Text("Tap the sentence where the reasoning is weakest, or call it sound.", color = cs.onSurfaceVariant)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            (item.sentences ?: emptyList()).forEachIndexed { i, s ->
                if (s == "¶") { Spacer(Modifier.height(8.dp)); return@forEachIndexed }
                val ins = attempt?.instant
                val isKey = ins["key_index"].int == i
                val isMiss = attempt != null && pick == i && ins["spot_ok"].bool == false
                val picked = pick == i
                val tint = when { isKey -> b.good; isMiss -> cs.error; else -> cs.primary }
                val on = picked || isKey || isMiss
                Text(s, style = readingStyle(18), modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                    .background(if (on) tint.copy(alpha = 0.12f) else Color.Transparent)
                    .border(1.dp, if (on) tint.copy(alpha = 0.5f) else Color.Transparent, RoundedCornerShape(12.dp))
                    .selectable(selected = picked, enabled = attempt == null, role = Role.RadioButton) { pick = i; Haptic.tick(view) }
                    .padding(horizontal = 12.dp, vertical = 8.dp))
            }
        }
        Ask("What's wrong with it?")
        Column(Modifier.selectableGroup()) {
            (item.flaws ?: emptyList()).forEach { f ->
                Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(12.dp))
                        .selectable(flaw == f, enabled = attempt == null, role = Role.RadioButton) { flaw = f; Haptic.tick(view) },
                    verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = flaw == f, onClick = null, enabled = attempt == null, modifier = Modifier.padding(horizontal = 8.dp))
                    Text(f.capitalizedFirst())
                }
            }
        }
        Ask("Why, in one line?")
        OutlinedTextField(why, { why = it }, Modifier.fillMaxWidth(), placeholder = { Text("Optional; Claude reads it") },
                          minLines = 1, maxLines = 4, enabled = attempt == null, shape = RoundedCornerShape(16.dp))
        problem?.let { Text(it, color = cs.error) }
        val a = attempt
        if (a == null) {
            Button(onClick = {
                sending = true; problem = null
                scope.launch {
                    try {
                        var r = submitAnswer(item, mapOf("index" to pick, "flaw" to (flaw ?: ""), "why" to why.trim()), null, started, ctx)
                        attempt = r
                        Haptic.verdict(view, (r.score ?: 0.0) >= 1)
                        if (why.isNotBlank() && r.grade == null && !r.waitsForTomorrow) {
                            r = Api.waitFor(r.id) { it.grade != null || it.waitsForTomorrow }
                            attempt = r
                        }
                    } catch (e: Exception) { problem = e.message }
                    sending = false
                }
            }, enabled = !sending && flaw != null && (pick != null || flaw == sound), modifier = Modifier.fillMaxWidth().height(52.dp)) {
                Text(if (sending) "Checking…" else "Check answer")
            }
        } else {
            val k = a.key
            val ins = a.instant
            val score = a.score ?: 0.0
            ResultCard(if (score >= 1) "Clean" else if (score > 0) "Half right" else "Missed",
                       if (score >= 1) b.good else if (score > 0) b.amber else cs.error) {
                Text("spot ${if (ins["spot_ok"].bool == true) "✓" else "✗"} · flaw ${if (ins["flaw_ok"].bool == true) "✓" else "✗"}",
                     style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
                Text(lead((k["flaw"].str ?: "").capitalizedFirst() + ".", k["explain"].str ?: ""))
                k["assumption"].str?.takeIf { it.isNotBlank() }?.let { Text(lead("It quietly assumes:", it)) }
                if (why.isNotBlank()) {
                    val w = a.grade["work_on"].str
                    when {
                        w != null -> Text(lead("Your reason:", "${a.grade["reason"].int?.let { "$it/4" } ?: "?"}. $w"), style = MaterialTheme.typography.bodyMedium)
                        a.waitsForTomorrow -> Text("Claude reads your reason tomorrow: today's grading is used up.",
                                                   style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
                        else -> Waiting("Claude is reading your reason…")
                    }
                }
            }
            RatingDelta(a)
            EndButtons(ctx, nav, attempt = a)
        }
    }
}

// MARK: The Author's Word

/** A sentence with one word gone; pick the one the author actually chose. */
@Composable
fun WordGame(item: Item, ctx: PlayContext, nav: Nav) {
    var chosen by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableStateOf<Attempt?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    val started = remember { System.currentTimeMillis() }
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val b = LocalBinah.current
    val cs = MaterialTheme.colorScheme
    val fill = attempt?.key["target"].str
    GameColumn(follow = attempt?.id) {
        SourceLine(item.source)
        val parts = (item.sentence ?: "").split("_____")
        Text(buildAnnotatedString {
            append(parts.first())
            parts.drop(1).forEach { p ->
                if (fill != null) withStyle(SpanStyle(color = cs.primary, fontWeight = FontWeight.SemiBold)) { append(fill) }
                else withStyle(SpanStyle(textDecoration = TextDecoration.Underline, color = cs.outline)) { append("    ") }
                append(p)
            }
        }, style = readingStyle(22))
        Ask("Which word did the author choose?")
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            (item.options ?: emptyList()).forEach { w ->
                val target = attempt?.key["target"].str?.lowercase()
                val mark = when {
                    attempt == null -> null
                    w.lowercase() == target -> Icons.Filled.CheckCircle to b.good
                    w == chosen -> Icons.Filled.Cancel to cs.error
                    else -> null
                }
                OutlinedButton(onClick = {
                    chosen = w
                    scope.launch {
                        runCatching { submitAnswer(item, mapOf("choice" to w), null, started, ctx) }
                            .onSuccess { attempt = it; Haptic.verdict(view, (it.score ?: 0.0) > 0) }
                            .onFailure { problem = it.message; chosen = null }
                    }
                }, enabled = chosen == null, modifier = Modifier.fillMaxWidth().height(56.dp), shape = RoundedCornerShape(16.dp)) {
                    Text(w, style = readingStyle(17), modifier = Modifier.weight(1f), color = cs.onSurface)
                    mark?.let { (icon, tint) -> Icon(icon, null, tint = tint) }
                }
            }
        }
        problem?.let { Text(it, color = cs.error) }
        attempt?.let { a ->
            val right = (a.score ?: 0.0) > 0
            ResultCard(if (right) "The author's word" else "The author wrote “${a.key["target"].str ?: ""}”", if (right) b.good else cs.error) {
                Text(a.key["why"].str ?: "")
            }
            RatingDelta(a)
            EndButtons(ctx, nav, attempt = a)
        }
    }
}

// MARK: Technique or Fair Move?

/** Six quick calls: is this manipulation, or a fair version of the same move? With a confidence, so
 *  the round can say how well calibrated you are, and Skills whether you're getting sharper or just
 *  more suspicious. */
@Composable
fun TechRound(ids: List<String>, ctx: PlayContext, nav: Nav) {
    var index by remember { mutableIntStateOf(0) }
    var item by remember { mutableStateOf<Item?>(null) }
    val results = remember { mutableStateListOf<Attempt>() }
    var kind by remember { mutableStateOf<String?>(null) }
    var technique by remember { mutableStateOf<String?>(null) }
    var confidence by remember { mutableFloatStateOf(70f) }
    var attempt by remember { mutableStateOf<Attempt?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    var started by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var discern by remember { mutableStateOf<Discern?>(null) }
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val b = LocalBinah.current
    val cs = MaterialTheme.colorScheme

    LaunchedEffect(index) {
        if (index >= ids.size) { discern = runCatching { Api.get<SkillsInfo>("/api/skills") }.getOrNull()?.discern; return@LaunchedEffect }
        item = null; kind = null; technique = null; confidence = 70f; attempt = null; problem = null
        started = System.currentTimeMillis()
        runCatching { Api.get<Item>("/api/item/${Api.escape(ids[index])}") }.onSuccess { item = it }.onFailure { problem = it.message }
    }

    Column(Modifier.fillMaxSize()) {
        // Where you are in the round: a dash per call, coloured once it's made.
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            ids.indices.forEach { j ->
                val c = when {
                    j < results.size -> if (results[j].instant["kind_ok"].bool == true) b.good else cs.error
                    j == index -> cs.primary
                    else -> cs.surfaceContainerHighest
                }
                Box(Modifier.weight(1f).height(5.dp).clip(CircleShape).background(c))
            }
        }
        if (index >= ids.size) {
            val right = results.count { it.instant["kind_ok"].bool == true }
            val briers = results.mapNotNull { it.instant["brier"].dbl }
            GameColumn {
                BCard {
                    Text("$right of ${results.size} called right", style = MaterialTheme.typography.headlineSmall)
                    if (briers.isNotEmpty()) Text(lead("Confidence Brier score this round:", "%.3f (0 is perfect, 0.25 is a coin flip).".format(briers.average())))
                    val d = discern
                    if (d?.dprime != null && d.bias != null)
                        Text("Over all your rounds: discernment d′ ${"%.2f".format(d.dprime)}, " +
                             when { d.bias > 0.15 -> "leaning toward calling things fair."; d.bias < -0.15 -> "leaning toward calling things tricks."; else -> "no lean either way." })
                    else Text("After a few rounds, Skills shows whether you are getting sharper or just more suspicious.",
                              style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
                }
                Button(onClick = { scope.launch { nav.finished(ctx) } }, modifier = Modifier.fillMaxWidth().height(52.dp)) {
                    Text(if (ctx.fromToday) "Back to Today" else "Another round")
                }
            }
            return@Column
        }
        val it = item
        if (it == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { if (problem != null) Text(problem!!, color = cs.error) else Waiting("Opening…") }
            return@Column
        }
        GameColumn(follow = attempt?.id) {
            Text(it.context ?: "", style = MaterialTheme.typography.bodyMedium, color = cs.onSurfaceVariant)
            val text = it.text ?: ""
            val tell = attempt?.key["tell"].str?.takeIf { t -> t.isNotBlank() }
            val at = tell?.let { t -> text.indexOf(t) } ?: -1
            Text(buildAnnotatedString {
                if (tell == null || at < 0) append(text) else {
                    append(text.substring(0, at))
                    withStyle(SpanStyle(background = b.amber.copy(alpha = 0.28f))) { append(tell) }
                    append(text.substring(at + tell.length))
                }
            }, style = readingStyle(20))
            Ask("Manipulative as written, or a fair move?")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("technique" to "Manipulation", "fair" to "Fair move").forEach { (k, title) ->
                    val key = attempt?.key["kind"].str
                    val tint = if (attempt == null) (if (kind == k) cs.primary else null) else if (key == k) b.good else if (kind == k) cs.error else null
                    OutlinedButton(onClick = { kind = k; if (k != "technique") technique = null; Haptic.tick(view) }, enabled = attempt == null,
                                   modifier = Modifier.weight(1f).height(56.dp), shape = RoundedCornerShape(16.dp),
                                   border = androidx.compose.foundation.BorderStroke(if (tint != null) 2.dp else 1.dp, tint ?: cs.outline),
                                   colors = androidx.compose.material3.ButtonDefaults.outlinedButtonColors(
                                       containerColor = tint?.copy(alpha = 0.12f) ?: Color.Transparent,
                                       disabledContainerColor = tint?.copy(alpha = 0.12f) ?: Color.Transparent,
                                       contentColor = tint ?: cs.onSurface, disabledContentColor = tint ?: cs.onSurfaceVariant)) {
                        Text(title, style = MaterialTheme.typography.titleSmall)
                    }
                }
            }
            if (kind == "technique") {
                Text("Which technique? (optional, a bonus if right)", style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
                Column {
                    (it.techniques ?: emptyList()).forEach { t ->
                        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(12.dp))
                                .clickable(enabled = attempt == null) { technique = if (technique == t) null else t },
                            verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(checked = technique == t, onCheckedChange = null, enabled = attempt == null, modifier = Modifier.padding(horizontal = 10.dp))
                            Text(t.capitalizedFirst())
                        }
                    }
                }
            }
            Column {
                Row { Text("How sure are you?", modifier = Modifier.weight(1f)); Text("${confidence.toInt()}%", fontWeight = FontWeight.SemiBold) }
                Slider(confidence, { v -> confidence = v }, valueRange = 50f..100f, steps = 9, enabled = attempt == null)
            }
            problem?.let { p -> Text(p, color = cs.error) }
            val a = attempt
            if (a == null) {
                Button(onClick = {
                    scope.launch {
                        runCatching {
                            submitAnswer(it, mapOf("kind" to (kind ?: ""), "technique" to (if (kind == "technique") technique else null),
                                                   "confidence" to confidence.toInt()), null, started, ctx)
                        }.onSuccess { r -> attempt = r; Haptic.verdict(view, r.instant["kind_ok"].bool == true) }.onFailure { e -> problem = e.message }
                    }
                }, enabled = kind != null, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("Call it") }
            } else {
                val k = a.key
                val ok = a.instant["kind_ok"].bool == true
                ResultCard((if (ok) "Right" else "Not quite") + " · " + (if (k["kind"].str == "fair") "a fair move" else (k["technique"].str ?: "")),
                           if (ok) b.good else cs.error) {
                    if (k["kind"].str == "fair") k["technique"].str?.let { t ->
                        Text("It resembles $t, done fairly.", style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant) }
                    else if (a.instant["label_ok"].bool == true) Text("And you named the technique.", style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
                    Text(k["why"].str ?: "")
                }
                Button(onClick = { results.add(a); index += 1 }, modifier = Modifier.fillMaxWidth().height(52.dp)) {
                    Text(if (index + 1 < ids.size) "Next" else "See the round")
                }
            }
        }
    }
}
