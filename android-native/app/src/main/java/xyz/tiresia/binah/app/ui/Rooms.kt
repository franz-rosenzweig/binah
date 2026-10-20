package xyz.tiresia.binah.app.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle as JTextStyle
import java.util.Locale
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import xyz.tiresia.binah.app.core.Api
import xyz.tiresia.binah.app.core.AppModel
import xyz.tiresia.binah.app.core.Criteria
import xyz.tiresia.binah.app.core.Games
import xyz.tiresia.binah.app.core.GoldenInfo
import xyz.tiresia.binah.app.core.PracticeGame
import xyz.tiresia.binah.app.core.Recall
import xyz.tiresia.binah.app.core.Server
import xyz.tiresia.binah.app.core.ServerSettings
import xyz.tiresia.binah.app.core.SkillsInfo
import xyz.tiresia.binah.app.core.Slot
import xyz.tiresia.binah.app.core.TodayInfo
import xyz.tiresia.binah.app.core.Token
import xyz.tiresia.binah.app.core.WeekDay

val Weekdays = listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")

fun dateLine(day: String): String = runCatching { LocalDate.parse(day).format(DateTimeFormatter.ofPattern("EEEE, MMMM d", Locale.getDefault())) }.getOrDefault(day)

// MARK: Today

@Composable
fun TodayScreen(model: AppModel, nav: Nav) {
    val t = model.today
    LaunchedEffect(Unit) { model.refresh() }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            LargeTitle("Today", t?.edition?.day?.let(::dateLine)) {
                IconButton(onClick = { nav.c.navigate("settings") }) { Icon(Icons.Outlined.Settings, "Settings") }
            }
        }
        if (t == null) { item { Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { Waiting("Loading today…") } }; return@LazyColumn }
        item { Hero(t, nav) }
        t.edition.recall?.takeIf { it.mark == null && it.reference != null }?.let { r -> item(key = "recall-${t.edition.day}") { RecallCard(r, model) } }
        item { SectionHead("Games") }
        item { GamesList(t, nav) }
        item { WeekCard(t, model) }
        item { SectionHead("So far") }
        item { CountsCard(t) }
    }
}

@Composable fun SectionHead(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
         modifier = Modifier.padding(start = 24.dp, end = 24.dp, top = 22.dp, bottom = 8.dp))
}

@Composable
fun Hero(t: TodayInfo, nav: Nav) {
    val ed = t.edition
    val next = ed.next
    Surface(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), shape = RoundedCornerShape(28.dp),
            color = MaterialTheme.colorScheme.primaryContainer, contentColor = MaterialTheme.colorScheme.onPrimaryContainer) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Today's edition", style = MaterialTheme.typography.titleSmall)
            if (ed.finished || next == null) {
                Text("Today's edition is done.", style = readingStyle(24, FontWeight.SemiBold))
                Text("Tomorrow opens with a recall card on today's passage. Anything else today is extra, in Practice.")
                FilledTonalButton(onClick = { nav.tab("practice") }, modifier = Modifier.height(48.dp)) { Text("Practice") }
            } else {
                Text("Next: ${next.name ?: Games.name(next.game)}", style = readingStyle(24, FontWeight.SemiBold))
                Text("${ed.done} of ${ed.slots.size} games · about ${maxOf(1, ed.minutesLeft)} min left")
                WavyProgress(if (ed.slots.isEmpty()) 0f else ed.done.toFloat() / ed.slots.size, Modifier.fillMaxWidth().height(14.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { nav.play(next.game, next.items, ed.day, next.slot) }, modifier = Modifier.weight(1f).height(52.dp)) {
                        Icon(Icons.Filled.PlayArrow, null); Spacer(Modifier.width(8.dp)); Text("Continue")
                    }
                    FilledTonalButton(onClick = { nav.tab("practice") }, modifier = Modifier.height(52.dp)) { Text("Practice") }
                }
            }
        }
    }
}

/** Yesterday's passage: what you remember, then the reference, then how much you got. */
@Composable
fun RecallCard(r: Recall, model: AppModel) {
    var text by rememberSaveable { mutableStateOf("") }
    var shown by rememberSaveable { mutableStateOf(false) }
    var gone by rememberSaveable { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    if (gone) return
    BCard(title = "Before you start", modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        Text("Yesterday you read a passage" + (r.book?.let { " from $it" } ?: "") + ". What was its point?")
        AnswerBox(text, { text = it }, "What you remember", minLines = 2, enabled = !shown)
        if (!shown) OutlinedButton(onClick = { shown = true }) { Text("Check against yesterday's reference") }
        else {
            Text(r.reference ?: "", style = readingStyle(16))
            r.key_points.forEach { Text("• $it", style = MaterialTheme.typography.bodyMedium) }
            Text("How much did you remember?", color = MaterialTheme.colorScheme.onSurfaceVariant)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("yes" to "Got it", "partly" to "Partly", "no" to "Not really").forEach { (m, title) ->
                    FilledTonalButton(onClick = {
                        scope.launch {
                            runCatching { Api.post<JsonElement>("/api/today/recall", mapOf("answer" to text, "mark" to m)) }
                                .onSuccess { gone = true; model.flash("Noted. On to today.") }.onFailure { model.flash(it.message ?: "") }
                        }
                    }) { Text(title) }
                }
            }
        }
    }
}

/** The edition's games as a segmented list: the pillar, the game, where it's from, and how it went. */
@Composable
fun GamesList(t: TodayInfo, nav: Nav) {
    val ed = t.edition
    Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        if (ed.slots.isEmpty()) Text("No items yet.", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(16.dp))
        ed.slots.forEachIndexed { i, s ->
            val shape = segmentShape(i, ed.slots.size)
            GameRow(s, t, next = s.slot == ed.next?.slot, shape = shape) { nav.play(s.game, s.items, ed.day, s.slot) }
        }
    }
}

fun segmentShape(i: Int, n: Int) = RoundedCornerShape(
    topStart = if (i == 0) 20.dp else 6.dp, topEnd = if (i == 0) 20.dp else 6.dp,
    bottomStart = if (i == n - 1) 20.dp else 6.dp, bottomEnd = if (i == n - 1) 20.dp else 6.dp)

@Composable
fun GameRow(s: Slot, t: TodayInfo, next: Boolean, shape: RoundedCornerShape, onClick: () -> Unit) {
    val p = s.pillar ?: Games.pillar[s.game] ?: "u"
    val b = LocalBinah.current
    ListItem(
        modifier = Modifier.clip(shape).clickable(onClick = onClick),
        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        leadingContent = { PillarIcon(p) },
        headlineContent = { Text(t.games[s.game]?.name ?: Games.name(s.game), fontWeight = FontWeight.Medium) },
        supportingContent = { Text(Pillar.name(p) + (s.source?.let { " · $it" } ?: " · ${s.minutes} min"), maxLines = 1, overflow = TextOverflow.Ellipsis) },
        trailingContent = {
            when {
                s.done -> Row(Modifier.clip(RoundedCornerShape(8.dp)).background(b.goodContainer).padding(horizontal = 10.dp, vertical = 5.dp),
                              verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Check, null, tint = b.onGoodContainer, modifier = Modifier.size(16.dp))
                    Text(s.average?.let { " ${Math.round(it * 100)}%" } ?: " Done", color = b.onGoodContainer, style = MaterialTheme.typography.labelLarge)
                }
                next -> Text("Next", color = MaterialTheme.colorScheme.onPrimary, style = MaterialTheme.typography.labelLarge,
                             modifier = Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.primary).padding(horizontal = 12.dp, vertical = 4.dp))
                (s.answered ?: 0) > 0 -> Text("${s.answered}/${s.items.size}", color = b.amber)
                else -> Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null)
            }
        },
    )
}

@Composable
fun WeekCard(t: TodayInfo, model: AppModel) {
    val w = t.week
    Surface(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 16.dp), shape = RoundedCornerShape(24.dp),
            color = MaterialTheme.colorScheme.surfaceContainer) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f), horizontalArrangement = Arrangement.SpaceBetween) { w.days.forEach { DayDot(it) } }
            Spacer(Modifier.width(12.dp))
            Column(horizontalAlignment = Alignment.End) {
                Text("${w.active}/${w.goal}", style = MaterialTheme.typography.titleLarge)
                Text("days", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    model.nav?.rest_weekday?.let {
        Text("${Weekdays.getOrElse(it) { "" }} counts as on track.", style = MaterialTheme.typography.bodySmall,
             color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 24.dp, top = 6.dp))
    }
}

@Composable
fun DayDot(d: WeekDay) {
    val letter = runCatching { LocalDate.parse(d.day).dayOfWeek.getDisplayName(JTextStyle.NARROW, Locale.getDefault()) }.getOrDefault("")
    val cs = MaterialTheme.colorScheme
    val (bg, fg) = when {
        d.answers > 0 -> cs.primary to cs.onPrimary
        d.today -> cs.primaryContainer to cs.onPrimaryContainer
        else -> cs.surfaceContainerHighest to cs.onSurfaceVariant
    }
    Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) {
        if (d.rest && d.answers == 0) Canvas(Modifier.fillMaxSize()) {
            drawCircle(cs.outline, style = Stroke(1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f))))
        } else Box(Modifier.fillMaxSize().clip(CircleShape).background(bg)
                   .then(if (d.today) Modifier.border(2.dp, cs.primary, CircleShape) else Modifier))
        Text(letter, color = if (d.rest && d.answers == 0) cs.onSurfaceVariant else fg, style = MaterialTheme.typography.labelMedium)
    }
}

@Composable
fun CountsCard(t: TodayInfo) {
    val c = t.counts
    BCard(modifier = Modifier.padding(horizontal = 16.dp)) {
        listOf(listOf(c.editions to "editions finished", c.passages to "passages read", c.arguments to "arguments weighed"),
               listOf(c.answers to "answers", Math.round(c.minutes_spoken).toInt() to "minutes spoken", c.active_weeks to "active weeks"))
            .forEach { row ->
                Row(Modifier.fillMaxWidth()) {
                    row.forEach { (n, label) ->
                        Column(Modifier.weight(1f).padding(vertical = 4.dp)) {
                            Text("$n", style = MaterialTheme.typography.titleLarge)
                            Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
    }
}

// MARK: Practice

@Composable
fun PracticeScreen(model: AppModel, nav: Nav) {
    var games by remember { mutableStateOf<List<PracticeGame>>(emptyList()) }
    var problem by remember { mutableStateOf<String?>(null) }
    var filter by rememberSaveable { mutableStateOf("all") }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { runCatching { Api.get<List<PracticeGame>>("/api/practice") }.onSuccess { games = it }.onFailure { problem = it.message } }
    LazyVerticalGrid(GridCells.Adaptive(170.dp), Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp),
                     horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Column {
                LargeTitle("Practice")
                Text("Anything beyond today's edition. The daily edition is the one that counts for the week.",
                     color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 4.dp, end = 4.dp, bottom = 12.dp))
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    (listOf("all" to "All") + listOf("u", "r", "e", "s").map { it to Pillar.name(it) }).forEach { (k, n) ->
                        FilterChip(selected = filter == k, onClick = { filter = k }, label = { Text(n) })
                    }
                }
                problem?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        }
        items(games.filter { filter == "all" || Games.pillar[it.game] == filter }, key = { it.game }) { g ->
            val p = Games.pillar[g.game] ?: "u"
            Surface(onClick = { scope.launch { runCatching { Api.get<xyz.tiresia.binah.app.core.PracticePick>("/api/practice/${g.game}") }
                                    .onSuccess { nav.play(g.game, it.items) }.onFailure { model.flash(it.message ?: "") } } },
                    enabled = g.live > 0, shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
                Column(Modifier.padding(16.dp).height(168.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.Top) {
                        PillarIcon(p, 40.dp); Spacer(Modifier.weight(1f))
                        Text("${g.minutes} min", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text(g.name, style = MaterialTheme.typography.titleMedium)
                    Text(g.blurb, style = MaterialTheme.typography.bodySmall, maxLines = 3, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Text("${Pillar.name(p)} · " + if (g.live > 0) "${g.live} ready" else "none yet",
                         style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

// MARK: Skills

@Composable
fun SkillsScreen(nav: Nav) {
    var s by remember { mutableStateOf<SkillsInfo?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { runCatching { Api.get<SkillsInfo>("/api/skills") }.onSuccess { s = it }.onFailure { problem = it.message } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        LargeTitle("Skills")
        Text("Ratings measure your first try, unaided. They say “calibrating” until there's enough to go on.",
             color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp))
        problem?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(20.dp)) }
        val info = s ?: return@Column
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Games.skillOrder.forEachIndexed { i, k ->
                val meta = info.skills[k]
                val r = info.ratings[k]
                Surface(shape = segmentShape(i, Games.skillOrder.size), color = MaterialTheme.colorScheme.surfaceContainer) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        PillarIcon(meta?.pillar ?: "u", 40.dp)
                        Column(Modifier.width(110.dp)) {
                            Text(meta?.name ?: Games.skillNames[k] ?: k, fontWeight = FontWeight.Medium)
                            Text(r?.let { "${it.rating}" + if (it.calibrating) " · calibrating" else "" } ?: "—",
                                 style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Spark(info.recent[k] ?: emptyList(), Modifier.weight(1f).height(28.dp))
                    }
                }
            }
        }
        SectionHead("Fair or trick, honestly measured")
        BCard(modifier = Modifier.padding(horizontal = 16.dp)) {
            val d = info.discern
            if (d.dprime != null && d.bias != null) {
                Text("Discernment d′ ${"%.2f".format(d.dprime)} · bias " + when { d.bias > 0.15 -> "toward calling things fair"; d.bias < -0.15 -> "toward calling things tricks"; else -> "balanced" })
                Text("Caught ${Math.round((d.hit_rate ?: 0.0) * 100)}% of the tricks, flagged ${Math.round((d.false_alarms ?: 0.0) * 100)}% of the fair moves as tricks." +
                     (d.brier?.let { " Confidence Brier score $it (0 is perfect, 0.25 is a coin flip)." } ?: ""),
                     style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else Text("After a few rounds of Technique or Fair Move, this shows whether you're getting sharper or just more suspicious.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        SectionHead("How well you judge yourself")
        BCard(modifier = Modifier.padding(horizontal = 16.dp)) {
            Text(info.self_gap?.let { "Your self-rating is off from the grade by ${"%.2f".format(it)} points on average (on 0–4). Watch it shrink." }
                 ?: "Rate yourself before each verdict, and this tracks the gap.")
        }
        SectionHead("Away from practice")
        Surface(onClick = { nav.c.navigate("bench") }, modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth(),
                shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(LocalBinah.current.pillarContainer["r"]!!), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.Flag, null, tint = LocalBinah.current.onPillarContainer["r"]!!)
                }
                Column(Modifier.weight(1f)) {
                    Text("The monthly benchmark", fontWeight = FontWeight.Medium)
                    Text("A sealed test, about 35 minutes. The honest measure of whether practice transfers.",
                         style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (info.bench_due) Text("Due", color = MaterialTheme.colorScheme.onError, style = MaterialTheme.typography.labelMedium,
                                         modifier = Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.error).padding(horizontal = 10.dp, vertical = 3.dp))
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null)
            }
        }
    }
}

/** A sparkline of recent scores, 0–1. */
@Composable
fun Spark(values: List<Double>, modifier: Modifier) {
    if (values.size < 2) { Text("A few more answers and a trend shows here.", style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = modifier); return }
    val color = MaterialTheme.colorScheme.primary
    Canvas(modifier) {
        val n = values.size
        val pts = values.mapIndexed { i, v -> Offset(size.width * i / (n - 1), size.height - 3f - v.toFloat() * (size.height - 6f)) }
        for (i in 1 until n) drawLine(color, pts[i - 1], pts[i], strokeWidth = 2.dp.toPx(), cap = StrokeCap.Round)
    }
}

// MARK: Golden set

@Composable
fun GoldenScreen(nav: Nav) {
    var g by remember { mutableStateOf<GoldenInfo?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { runCatching { Api.get<GoldenInfo>("/api/golden") }.onSuccess { g = it }.onFailure { problem = it.message } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        LargeTitle("Golden set")
        Text("Answer an item, then score your own answer with the same rubric Claude uses. Fifty of these tell you whether its grades deserve your trust.",
             color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp))
        problem?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(20.dp)) }
        val info = g ?: return@Column
        BCard(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text("${info.report.total} of ${info.report.target}", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
                Text("scored by you", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            androidx.compose.material3.LinearProgressIndicator(progress = { info.report.total.toFloat() / maxOf(1, info.report.target) },
                                                                modifier = Modifier.fillMaxWidth())
        }
        SectionHead("Score one now")
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            if (info.next.isEmpty()) Text("No items left to score in these games.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            info.next.forEachIndexed { i, id ->
                val game = id.substringBefore(':')
                ListItem(modifier = Modifier.clip(segmentShape(i, info.next.size)).clickable { nav.golden(id) },
                         colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
                         leadingContent = { PillarIcon(Games.pillar[game] ?: "u") },
                         headlineContent = { Text(Games.name(game), fontWeight = FontWeight.Medium) },
                         supportingContent = { Text("Answer it, then grade yourself") },
                         trailingContent = { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null) })
            }
        }
        SectionHead("How Claude agrees with you")
        BCard(modifier = Modifier.padding(horizontal = 16.dp)) {
            Row { listOf("Criterion" to 2f, "n" to 0.6f, "Exact" to 1f, "±1" to 1f, "QWK" to 1f).forEach { (h, w) ->
                Text(h, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(w)) } }
            HorizontalDivider()
            listOf("gist", "subtext", "bloat").forEach { game ->
                val gg = info.report.games[game] ?: return@forEach
                Criteria.sorted(gg.criteria.keys).forEach { c ->
                    val a = gg.criteria[c]!!
                    Row {
                        Text("${Games.name(game).substringBefore(' ')} · ${Criteria.label(c)}", style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(2f))
                        Text("${a.n}", style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(0.6f))
                        Text(if (a.n > 0) a.exact?.let { "${Math.round(it * 100)}%" } ?: "—" else "—", style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                        Text(if (a.n > 0) a.within1?.let { "${Math.round(it * 100)}%" } ?: "—" else "—", style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                        Text(a.qwk?.let { "%.2f".format(it) } ?: "—", style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                    }
                }
            }
            Text("Claude grades golden answers blind. QWK of 0.6–0.7 is typical for open judgments; above 0.8 is very good.",
                 style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (info.disputed.isNotEmpty()) {
            SectionHead("Grades you disputed")
            info.disputed.forEach { a ->
                BCard(modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                    Text("${Games.name(a.game)} · ${a.score?.let { "${Math.round(it * 100)}%" } ?: "—"}", fontWeight = FontWeight.Medium)
                    Text(a.disputed ?: "", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

// MARK: Settings

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(model: AppModel, nav: Nav) {
    val c = LocalContext.current
    val scope = rememberCoroutineScope()
    var s by remember { mutableStateOf<ServerSettings?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    var current by remember { mutableStateOf("") }
    var new by remember { mutableStateOf("") }
    var said by remember { mutableStateOf<String?>(null) }
    var address by remember { mutableStateOf(Server.base(c)) }
    var micOn by remember { mutableStateOf(c.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) }
    val askMic = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { micOn = it }
    LaunchedEffect(Unit) { runCatching { Api.get<ServerSettings>("/api/settings") }.onSuccess { s = it }.onFailure { problem = it.message } }
    fun save(v: ServerSettings) {
        s = v
        scope.launch {
            runCatching { Api.post<ServerSettings>("/api/settings", mapOf("weekly_goal_days" to v.weekly_goal_days, "rest_weekday" to v.rest_weekday, "grading_tone" to v.grading_tone)) }
                .onSuccess { s = it; model.refresh(); model.flash("Saved") }.onFailure { problem = it.message }
        }
    }
    Column(Modifier.fillMaxSize()) {
        GameBar("Settings", "", { nav.back() })
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp),
               verticalArrangement = Arrangement.spacedBy(12.dp)) {
            problem?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            s?.let { cur ->
                BCard(title = "Rhythm") {
                    Text("Days a week I aim for")
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        (1..7).forEach { n -> SegmentedButton(cur.weekly_goal_days == n, { save(cur.copy(weekly_goal_days = n)) }, SegmentedButtonDefaults.itemShape(n - 1, 7)) { Text("$n") } }
                    }
                    Text("Rest day (counts as on track)")
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        FilterChip(cur.rest_weekday == null, { save(cur.copy(rest_weekday = null)) }, { Text("None") })
                        Weekdays.forEachIndexed { i, d -> FilterChip(cur.rest_weekday == i, { save(cur.copy(rest_weekday = i)) }, { Text(d.take(3)) }) }
                    }
                }
                BCard(title = "How Claude talks to me") {
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        listOf("soft", "balanced", "strict").forEachIndexed { i, t ->
                            SegmentedButton(cur.grading_tone == t, { save(cur.copy(grading_tone = t)) }, SegmentedButtonDefaults.itemShape(i, 3)) { Text(t.replaceFirstChar { it.uppercase() }) }
                        }
                    }
                }
            }
            BCard(title = "Microphone") {
                Text(if (micOn) "On. Binah can record your spoken answers." else "Off. Binah asks the first time a game needs your voice.")
                if (!micOn) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilledTonalButton(onClick = { askMic.launch(Manifest.permission.RECORD_AUDIO) }) { Text("Allow") }
                    TextButton(onClick = { c.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + c.packageName))) }) { Text("App info") }
                }
            }
            BCard(title = "Password") {
                OutlinedTextField(current, { current = it }, Modifier.fillMaxWidth(), label = { Text("Current password") }, singleLine = true, visualTransformation = PasswordVisualTransformation())
                OutlinedTextField(new, { new = it }, Modifier.fillMaxWidth(), label = { Text("New password (10+ characters)") }, singleLine = true, visualTransformation = PasswordVisualTransformation())
                said?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                OutlinedButton(enabled = current.isNotEmpty() && new.length >= 10, onClick = {
                    scope.launch {
                        runCatching { Api.post<JsonElement>("/api/account", mapOf("current" to current, "password" to new)) }
                            .onSuccess { said = "Changed. Other browsers are signed out."; current = ""; new = "" }.onFailure { said = it.message }
                    }
                }) { Text("Change password") }
            }
            BCard(title = "This phone") {
                Text("Signed in as “${Token.deviceName}”. Binah's address:")
                OutlinedTextField(address, { address = it }, Modifier.fillMaxWidth(), singleLine = true)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilledTonalButton(enabled = Server.normal(address) != Server.base(c), onClick = {
                        if (Server.setBase(c, address)) { model.signOut(); model.flash("Binah opens from ${Server.base(c)}. Sign in there once.") }
                        else model.flash("That isn't an address Binah can use.")
                    }) { Text("Use") }
                    OutlinedButton(onClick = { model.signOut() }) { Text("Sign out") }
                }
            }
        }
    }
}
