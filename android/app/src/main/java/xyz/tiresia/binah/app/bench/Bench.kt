package xyz.tiresia.binah.app.bench

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import xyz.tiresia.binah.app.core.Api
import xyz.tiresia.binah.app.core.BenchForm
import xyz.tiresia.binah.app.core.BenchItem
import xyz.tiresia.binah.app.core.BenchPassage
import xyz.tiresia.binah.app.core.BenchReview
import xyz.tiresia.binah.app.core.BenchRun
import xyz.tiresia.binah.app.core.BenchSection
import xyz.tiresia.binah.app.core.BenchStart
import xyz.tiresia.binah.app.core.BenchStatus
import xyz.tiresia.binah.app.core.bool
import xyz.tiresia.binah.app.core.dbl
import xyz.tiresia.binah.app.core.get
import xyz.tiresia.binah.app.core.int
import xyz.tiresia.binah.app.core.isNullish
import xyz.tiresia.binah.app.core.str
import xyz.tiresia.binah.app.core.wordCount
import xyz.tiresia.binah.app.games.GameColumn
import xyz.tiresia.binah.app.games.Haptic
import xyz.tiresia.binah.app.games.Levels
import xyz.tiresia.binah.app.games.lead
import xyz.tiresia.binah.app.platform.Recorder
import xyz.tiresia.binah.app.ui.AnswerBox
import xyz.tiresia.binah.app.ui.Ask
import xyz.tiresia.binah.app.ui.BCard
import xyz.tiresia.binah.app.ui.GameBar
import xyz.tiresia.binah.app.ui.IconLine
import xyz.tiresia.binah.app.ui.LocalBinah
import xyz.tiresia.binah.app.ui.Nav
import xyz.tiresia.binah.app.ui.Passage
import xyz.tiresia.binah.app.ui.Ring
import xyz.tiresia.binah.app.ui.Waiting
import xyz.tiresia.binah.app.ui.readingStyle

// The monthly benchmark: one sitting on a sealed form, about thirty-five minutes. No feedback until
// the end; every answer is saved as it's given, so a sitting can stop and pick up later; the results
// live on their own track, apart from practice ratings (docs/API.md, The monthly benchmark).

private val sectionNames = mapOf("argument" to "Arguments", "discern" to "Fair or trick", "inference" to "Reading",
                                 "essay" to "The essay", "talk" to "The talk", "vocab" to "Words")
private const val letters = "ABCDE"

private fun pct(r: JsonElement?): String {
    val of = r["of"].dbl ?: return "—"
    if (of <= 0) return "—"
    return "${Math.round((r["right"].dbl ?: 0.0) / of * 100)}%"
}
private fun essayAvg(g: JsonElement?): String? {
    if (g.isNullish || g["failed"].bool == true) return null
    val s = g["structure"].dbl ?: return null
    return "%.1f".format((s + (g["accuracy"].dbl ?: 0.0) + (g["understanding"].dbl ?: 0.0)) / 3)
}
private fun talkAvg(g: JsonElement?): String? {
    if (g.isNullish || g["failed"].bool == true) return null
    val d = g["deviation"].dbl ?: return null
    return "%.1f".format(((g["hesitation"].dbl ?: 0.0) + (g["repetition"].dbl ?: 0.0) + d + (g["structure"].dbl ?: 0.0)) / 4)
}
private fun day(stamp: String?): LocalDate? = stamp?.takeIf { it.length >= 10 }?.let { runCatching { LocalDate.parse(it.substring(0, 10)) }.getOrNull() }
private fun short(d: LocalDate?) = d?.format(DateTimeFormatter.ofPattern("d MMM yyyy", Locale.getDefault())) ?: ""

// MARK: the overview

@Composable
fun BenchOverview(nav: Nav) {
    var status by remember { mutableStateOf<BenchStatus?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    val cs = MaterialTheme.colorScheme
    LaunchedEffect(Unit) { runCatching { Api.get<BenchStatus>("/api/benchmark") }.onSuccess { status = it }.onFailure { problem = it.message } }
    Column(Modifier.fillMaxSize()) {
        GameBar("Benchmark", "A sealed test, once a month", { nav.back() })
        GameColumn {
            Text("Once a month, a sealed test you never practise on: eight arguments, eight fair-or-trick calls, two passages with three questions each, " +
                 "a 15-minute essay, a 2-minute talk and six words. About 35 minutes. Answers save as you go, so you can stop and come back. " +
                 "You see what you missed at the end.", color = cs.onSurfaceVariant)
            problem?.let { Text(it, color = cs.error) }
            val s = status ?: return@GameColumn
            val open = s.runs.firstOrNull { it.finished == null }
            val done = s.runs.filter { it.finished != null }
            val used = s.runs.map { it.form }.toSet()
            val unused = s.forms.count { it.id !in used }
            val due = day(done.lastOrNull()?.finished)?.plusDays(28)
            val early = due?.isAfter(LocalDate.now()) ?: false
            BCard {
                when {
                    open != null -> {
                        Text("You have a sitting in progress.", fontWeight = FontWeight.SemiBold)
                        Button(onClick = { nav.benchRun() }) { Text("Continue it") }
                    }
                    unused > 0 -> {
                        if (due != null && done.isNotEmpty()) Text(if (early) lead("Next one is due around ${due.format(DateTimeFormatter.ofPattern("d MMMM", Locale.getDefault()))}.",
                                                                                     "A month between sittings keeps the comparison fair.")
                                                                   else lead("A sitting is due.", ""))
                        else Text("Take the first one to set your baseline.", fontWeight = FontWeight.SemiBold)
                        Text("$unused sealed form${if (unused == 1) "" else "s"} ready.", style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
                        if (early) FilledTonalButton(onClick = { nav.benchRun() }) { Text("Start one anyway") }
                        else Button(onClick = { nav.benchRun() }) { Text("Start a sitting") }
                    }
                    else -> {
                        Text(if (s.forms.isEmpty()) "No sealed forms yet." else "Every sealed form has been used.")
                        Text("New ones are written on the server with python -m binah.benchgen.", style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
                    }
                }
            }
            if (done.isNotEmpty()) {
                Text("Sittings", style = MaterialTheme.typography.titleSmall, color = cs.onSurfaceVariant)
                done.reversed().forEach { r -> SittingRow(r) { nav.benchReview(r.id) } }
                Text("Essay and talk are out of 4. Brier: 0 is perfect calibration, 0.25 a coin flip. With eight items a section, one sitting is noisy; " +
                     "trust a change only once it holds for two sittings.", style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun SittingRow(r: BenchRun, onClick: () -> Unit) {
    val x = r.results
    BCard(modifier = Modifier.clickable(onClick = onClick)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(short(day(r.finished)), fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null)
        }
        Row(Modifier.fillMaxWidth()) {
            listOf(pct(x["argument"]) to "arg.", pct(x["inference"]) to "read", pct(x["vocab"]) to "words",
                   (x["discern"]["dprime"].dbl?.let { "%.2f".format(it) } ?: "—") to "d′",
                   (essayAvg(x["essay"]["grade"]) ?: "…") to "essay", (talkAvg(x["talk"]["grade"]) ?: "…") to "talk").forEach { (v, l) ->
                Column(Modifier.weight(1f)) {
                    Text(v, style = MaterialTheme.typography.titleSmall)
                    Text(l, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

// MARK: a sitting

data class BenchStep(val sec: String, val key: String, val item: BenchItem?, val section: BenchSection,
                     val passage: BenchPassage?, val passageIndex: Int?)

fun benchSteps(form: BenchForm): List<BenchStep> = buildList {
    for (s in form.sections) when (s.kind) {
        "argument", "vocab", "discern" -> (s.items ?: emptyList()).forEach { add(BenchStep(s.kind, "${s.kind}:${it.key}", it, s, null, null)) }
        "inference" -> (s.passages ?: emptyList()).forEachIndexed { pi, p ->
            p.questions.forEach { q -> add(BenchStep("inference", "inference:${q.key}", q, s, p, pi)) }
        }
        else -> add(BenchStep(s.kind, s.kind, null, s, null, null))
    }
}

@Composable
fun BenchSitting(nav: Nav) {
    var run by remember { mutableStateOf<Int?>(null) }
    var steps by remember { mutableStateOf<List<BenchStep>>(emptyList()) }
    val answers = remember { mutableStateMapOf<String, JsonElement>() }
    var passages by remember { mutableStateOf<List<BenchPassage>>(emptyList()) }
    var problem by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val cs = MaterialTheme.colorScheme

    LaunchedEffect(Unit) {
        runCatching { Api.post<BenchStart>("/api/benchmark/start") }.onSuccess { r ->
            answers.putAll(r.answers)
            passages = r.form.sections.firstOrNull { it.kind == "inference" }?.passages ?: emptyList()
            steps = benchSteps(r.form)
            run = r.run
        }.onFailure { problem = it.message }
    }

    fun answered(st: BenchStep) = when (st.sec) {
        "essay" -> answers["essay"]["done"].bool == true
        "talk" -> !answers["talk"].isNullish
        else -> !answers[st.key].isNullish
    }
    suspend fun save(r: Int, key: String, value: Map<String, Any?>) {
        Api.post<JsonElement>("/api/benchmark/$r/answer", mapOf("key" to key, "value" to value))
        answers[key] = Api.toJson(value)
    }

    val current = steps.indexOfFirst { !answered(it) }.takeIf { it >= 0 }
    Column(Modifier.fillMaxSize()) {
        GameBar(current?.let { sectionNames[steps[it].sec] ?: "Benchmark" } ?: if (run != null) "That's everything" else "Benchmark",
                "Monthly benchmark" + (current?.let { " · ${it + 1} of ${steps.size}" } ?: ""), { nav.back() })
        val r = run
        if (r == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { problem?.let { Text("Couldn't start a sitting. $it", color = cs.error) } ?: Waiting("Opening the sealed form…") }
            return@Column
        }
        if (current != null) {
            val st = steps[current]
            key(st.key) {
                when (st.sec) {
                    "essay" -> BenchEssay(st.section, if (passages.size > 1) passages[1] else passages.firstOrNull(), answers["essay"]) { v -> save(r, "essay", v) }
                    "talk" -> BenchTalk(st.section, r, done = { answers["talk"] = Api.toJson(mapOf("audio" to true)) }, skip = { save(r, "talk", mapOf("skipped" to true)) })
                    else -> BenchChoice(st, current + 1 == steps.size) { v -> save(r, st.key, v) }
                }
            }
        } else GameColumn {
            Text("Hand it in to see your scores and what you missed. The essay and the talk are graded on the server and arrive a minute or two later.")
            problem?.let { Text(it, color = cs.error) }
            Button(onClick = {
                scope.launch {
                    runCatching { Api.post<JsonElement>("/api/benchmark/$r/finish") }
                        .onSuccess { Haptic.confirm(view); nav.benchReview(r); nav.model.refresh() }.onFailure { problem = it.message }
                }
            }, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("Hand it in") }
        }
    }
}

/** A multiple-choice question (argument, reading, words) or a fair-or-trick call, with a confidence. */
@Composable
fun BenchChoice(step: BenchStep, last: Boolean, save: suspend (Map<String, Any?>) -> Unit) {
    val binary = step.sec == "discern"
    val floor = if (binary) 50f else if (step.sec == "argument") 20f else 25f
    var pick by remember { mutableStateOf<String?>(null) }
    var confidence by remember { mutableFloatStateOf(maxOf(floor, 70f)) }
    var busy by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    var passageOpen by remember { mutableStateOf(true) }
    val scope = rememberCoroutineScope()
    val view = LocalView.current
    val cs = MaterialTheme.colorScheme
    val b = LocalBinah.current
    val it = step.item

    @Composable
    fun option(value: String, title: String, letter: Char?, modifier: Modifier = Modifier.fillMaxWidth()) {
        val on = pick == value
        OutlinedButton(onClick = { pick = value; Haptic.tick(view) }, modifier = modifier.heightIn(min = 56.dp), shape = RoundedCornerShape(16.dp),
                       border = BorderStroke(if (on) 2.dp else 1.dp, if (on) cs.primary else cs.outlineVariant),
                       colors = ButtonDefaults.outlinedButtonColors(containerColor = if (on) cs.primary.copy(alpha = 0.10f) else Color.Transparent,
                                                                    contentColor = cs.onSurface),
                       contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 12.dp)) {
            if (letter != null) { Text("$letter", fontWeight = FontWeight.Bold, color = if (on) cs.primary else cs.onSurfaceVariant); Spacer(Modifier.width(12.dp)) }
            Text(title, modifier = Modifier.weight(1f), textAlign = if (binary) TextAlign.Center else TextAlign.Start)
        }
    }

    GameColumn {
        when (step.sec) {
            "argument" -> { Passage(it?.stimulus ?: "", size = 17); Ask(it?.stem ?: "") }
            "vocab" -> {
                val s = it?.sentence ?: ""
                val w = it?.word ?: ""
                val at = if (w.isEmpty()) -1 else s.indexOf(w, ignoreCase = true)
                Text(buildAnnotatedString {
                    if (at < 0) append(s) else {
                        append(s.substring(0, at))
                        withStyle(SpanStyle(background = b.amber.copy(alpha = 0.28f))) { append(s.substring(at, at + w.length)) }
                        append(s.substring(at + w.length))
                    }
                }, style = readingStyle(19))
                Ask("What does “$w” mean here?")
            }
            "inference" -> {
                TextButton(onClick = { passageOpen = !passageOpen }) {
                    Text((if (passageOpen) "Hide passage " else "Passage ") + "${(step.passageIndex ?: 0) + 1}" + (step.passage?.source?.let { s -> " · $s" } ?: ""))
                }
                if (passageOpen) Passage(step.passage?.text ?: "", size = 16)
                Ask(it?.stem ?: "")
            }
            else -> {
                Text(it?.context ?: "", style = MaterialTheme.typography.bodyMedium, color = cs.onSurfaceVariant)
                Text(it?.text ?: "", style = readingStyle(20))
                Ask("Manipulative as written, or a fair move?")
            }
        }
        if (binary) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            option("technique", "Manipulation", null, Modifier.weight(1f))
            option("fair", "Fair move", null, Modifier.weight(1f))
        } else Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            (it?.options ?: emptyList()).forEachIndexed { k, o -> option("$k", o, letters.getOrNull(k)) }
        }
        Column {
            Row { Text("How sure are you?", modifier = Modifier.weight(1f)); Text("${confidence.toInt()}%", fontWeight = FontWeight.SemiBold) }
            Slider(confidence, { v -> confidence = v }, valueRange = floor..100f, steps = ((100f - floor) / 5f).toInt() - 1)
        }
        problem?.let { p -> Text(p, color = cs.error) }
        Button(onClick = {
            val p = pick ?: return@Button
            busy = true
            scope.launch {
                runCatching { save(if (binary) mapOf("kind" to p, "confidence" to confidence.toInt()) else mapOf("choice" to (p.toIntOrNull() ?: 0), "confidence" to confidence.toInt())) }
                    .onFailure { e -> problem = e.message }
                busy = false
            }
        }, enabled = pick != null && !busy, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text(if (last) "Done" else "Next") }
    }
}

/** The fifteen-minute essay: saved as you type (every fifteen seconds and when you leave), closed
 *  when you're done or the time is up. */
@Composable
fun BenchEssay(section: BenchSection, passage: BenchPassage?, draft: JsonElement?, save: suspend (Map<String, Any?>) -> Unit) {
    var text by remember { mutableStateOf(draft["text"].str ?: "") }
    var started by remember { mutableLongStateOf(draft["started"].dbl?.toLong() ?: System.currentTimeMillis()) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var lastSaved by remember { mutableStateOf(text) }
    var closed by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    var passageOpen by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val cs = MaterialTheme.colorScheme
    val total = (section.minutes ?: 15) * 60_000L
    val left = maxOf(0L, total - (now - started))

    fun persist(done: Boolean) {
        lastSaved = text
        val body = mapOf("text" to text, "started" to started, "done" to done)
        scope.launch { runCatching { save(body) } }
    }
    fun close(why: String?) {
        if (closed) return
        closed = true; problem = why; lastSaved = text
        scope.launch { runCatching { save(mapOf("text" to text, "started" to started, "done" to true)) }.onFailure { closed = false; problem = it.message } }
    }

    LaunchedEffect(Unit) {
        if (draft["started"].dbl == null) persist(false)
        var n = 0
        while (!closed) {
            delay(1000); n++
            now = System.currentTimeMillis()
            if (now - started >= total) close("Time's up. Your essay is saved.")
            else if (text != lastSaved && n % 15 == 0) persist(false)
        }
    }
    DisposableEffect(Unit) { onDispose { if (!closed && text != lastSaved) { val body = mapOf("text" to text, "started" to started, "done" to false); kotlinx.coroutines.MainScope().launch { runCatching { save(body) } } } } }

    GameColumn {
        Ask(section.prompt ?: "")
        if (passage != null) {
            TextButton(onClick = { passageOpen = !passageOpen }) { Text((if (passageOpen) "Hide the passage" else "The passage") + (passage.source?.let { " · $it" } ?: "")) }
            if (passageOpen) Passage(passage.text, size = 16)
        }
        Row {
            Text("${wordCount(text)} words", color = cs.onSurfaceVariant, modifier = Modifier.weight(1f))
            Text("${left / 60_000}:" + "%02d".format((left / 1000) % 60), fontWeight = FontWeight.SemiBold,
                 color = if (left < 60_000) cs.error else cs.onSurface)
        }
        AnswerBox(text, { text = it }, "Your essay", minLines = 12, enabled = !closed)
        problem?.let { Text(it, color = cs.error) }
        Button(onClick = { close(null) }, enabled = !closed, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("I'm done") }
        Text("It saves as you type. Fifteen minutes is the limit, and the reasoning counts more than the length.",
             style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
    }
}

/** The two-minute talk, spoken; or skipped this time. */
@Composable
fun BenchTalk(section: BenchSection, run: Int, done: () -> Unit, skip: suspend () -> Unit) {
    val c = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val recorder = remember { Recorder(c, (section.seconds ?: 120).toFloat()) }
    var status by remember { mutableStateOf("Tap to start. It stops by itself at two minutes.") }
    var uploading by remember { mutableStateOf(false) }
    val cs = MaterialTheme.colorScheme

    fun begin() {
        recorder.onFinish = { data, _ ->
            uploading = true
            status = "Uploading…"
            view.keepScreenOn = false
            scope.launch {
                runCatching { Api.upload<JsonElement>("/api/benchmark/$run/talk", emptyMap(), data, "talk.m4a", "audio/mp4") }
                    .onSuccess { done() }.onFailure { status = it.message ?: ""; recorder.state = Recorder.State.Idle }
                uploading = false
            }
        }
        runCatching { recorder.start(scope) }.onSuccess { status = "Tap to stop early."; view.keepScreenOn = true; Haptic.confirm(view) }
            .onFailure { status = it.message ?: "" }
    }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) begin() else status = "Binah can't use the microphone. Allow it in Settings → Apps → Binah → Permissions, or skip the talk."
    }
    DisposableEffect(Unit) { onDispose { if (recorder.state == Recorder.State.Recording) recorder.cancel(); view.keepScreenOn = false } }

    GameColumn {
        Text("Two minutes, spoken. Make one point and support it.", color = cs.onSurfaceVariant, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        Text(section.prompt ?: "", style = readingStyle(24, FontWeight.SemiBold), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        val rec = recorder.state == Recorder.State.Recording
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Ring(recorder.left / recorder.limit, Modifier.size(200.dp), stroke = 12.dp) {
                Text("${Math.ceil((if (rec) recorder.left else recorder.limit).toDouble()).toInt()}", fontSize = 48.sp, fontWeight = FontWeight.Medium)
            }
            Levels(recorder.levels, rec)
            FilledIconButton(onClick = {
                if (rec) recorder.stop()
                else if (c.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) begin()
                else ask.launch(Manifest.permission.RECORD_AUDIO)
            }, enabled = !uploading, modifier = Modifier.size(96.dp), shape = RoundedCornerShape(if (rec) 28.dp else 48.dp),
                colors = IconButtonDefaults.filledIconButtonColors(containerColor = if (rec) cs.error else cs.primary, contentColor = if (rec) cs.onError else cs.onPrimary)) {
                Icon(if (rec) Icons.Filled.Stop else Icons.Filled.Mic, if (rec) "Stop" else "Start recording", Modifier.size(40.dp))
            }
            Text(status, style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant, textAlign = TextAlign.Center)
            if (!rec && !uploading) TextButton(onClick = { scope.launch { runCatching { skip() } } }) { Text("Skip the talk this time") }
        }
    }
}

// MARK: the review

/** A finished sitting: the scores, the essay and the talk as their grades arrive, then every miss
 *  with its explanation. */
@Composable
fun BenchReviewScreen(run: Int, nav: Nav) {
    var review by remember { mutableStateOf<BenchReview?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    val cs = MaterialTheme.colorScheme

    fun wroteEssay(r: BenchReview) = !(r.answers["essay"]["text"].str ?: "").isBlank()
    fun talked(r: BenchReview) = r.answers["talk"] != null && r.answers["talk"]["skipped"].bool != true
    fun pending(r: BenchReview) = (wroteEssay(r) && r.results["essay"]["grade"].isNullish) || (talked(r) && r.results["talk"]["grade"].isNullish)

    // the essay and the talk are graded after the hand-in: ask again until both are in
    LaunchedEffect(run) {
        for (n in 0 until 80) {
            val r = runCatching { Api.get<BenchReview>("/api/benchmark/$run") }.getOrElse { problem = it.message; return@LaunchedEffect }
            review = r
            if (!pending(r)) return@LaunchedEffect
            delay(if (n < 10) 4000 else 8000)
        }
    }

    Column(Modifier.fillMaxSize()) {
        GameBar("Your sitting", "Monthly benchmark" + (review?.finished?.let { " · " + short(day(it)) } ?: ""), { nav.back() })
        GameColumn {
            problem?.let { Text(it, color = cs.error) }
            val r = review ?: run { if (problem == null) Waiting("Opening…"); return@GameColumn }
            val x = r.results
            val dd = x["discern"]
            val eg = x["essay"]["grade"]
            val tg = x["talk"]["grade"]
            fun rightOf(v: JsonElement?) = v["of"].int?.let { " · ${v["right"].int ?: 0}/$it" } ?: ""
            BCard {
                listOf(listOf(pct(x["argument"]) to "arguments" + rightOf(x["argument"]), pct(x["inference"]) to "reading" + rightOf(x["inference"]),
                              pct(x["vocab"]) to "words" + rightOf(x["vocab"])),
                       listOf((dd["dprime"].dbl?.let { "%.2f".format(it) } ?: "—") to "discernment d′", (x["brier"].dbl?.let { "%.2f".format(it) } ?: "—") to "calibration (Brier)",
                              (essayAvg(eg) ?: if (wroteEssay(r)) "…" else "—") to "essay, out of 4"))
                    .forEach { row ->
                        Row(Modifier.fillMaxWidth()) {
                            row.forEach { (v, l) ->
                                Column(Modifier.weight(1f).padding(vertical = 4.dp)) {
                                    Text(v, style = MaterialTheme.typography.titleLarge)
                                    Text(l, style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
                                }
                            }
                        }
                    }
            }
            dd["of_tricks"].int?.takeIf { it > 0 }?.let { ot ->
                val bias = dd["bias"].dbl ?: 0.0
                Text("Fair or trick: caught ${dd["hits"].int ?: 0} of $ot tricks, called ${dd["false_alarms"].int ?: 0} of ${dd["of_fair"].int ?: 0} fair moves tricks. Bias " +
                     (if (bias > 0.15) "toward calling things fair" else if (bias < -0.15) "toward calling things tricks" else "balanced") + " (${"%.2f".format(bias)}).",
                     style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
            }
            BCard(title = "The essay") {
                when {
                    !wroteEssay(r) -> Text("Not written this time.", color = cs.onSurfaceVariant)
                    !eg.isNullish -> if (eg["failed"].bool == true) Text("Grading failed twice. It is logged on the server.", color = cs.onSurfaceVariant) else {
                        Text("structure ${fmt(eg["structure"])}/4 · accuracy ${fmt(eg["accuracy"])}/4 · understanding ${fmt(eg["understanding"])}/4" +
                             if ((eg["spread"].dbl ?: 0.0) >= 2) " · the two readings disagreed, so take this one loosely" else "", style = MaterialTheme.typography.bodyMedium)
                        Feedback(eg)
                    }
                    else -> Waiting("Being graded, twice, and averaged…")
                }
                if (wroteEssay(r)) Disclose("What you wrote", r.answers["essay"]["text"].str ?: "")
            }
            BCard(title = "The talk") {
                when {
                    !talked(r) -> Text("Skipped this time.", color = cs.onSurfaceVariant)
                    !tg.isNullish -> if (tg["failed"].bool == true) Text("Grading failed twice. It is logged on the server.", color = cs.onSurfaceVariant) else {
                        val m = tg["metrics"]
                        Text("${(m["speaking_time"].dbl ?: 0.0).toInt()}s speaking · ${(m["wpm"].dbl ?: 0.0).toInt()} words a minute · ${"%.1f".format(m["fillers_per_min"].dbl ?: 0.0)} fillers a minute",
                             style = MaterialTheme.typography.bodyMedium)
                        Text("hesitation ${fmt(tg["hesitation"])}/4 · repetition ${fmt(tg["repetition"])}/4 · deviation ${fmt(tg["deviation"])}/4 · structure ${fmt(tg["structure"])}/4",
                             style = MaterialTheme.typography.bodyMedium)
                        Feedback(tg)
                        tg["text"].str?.takeIf { it.isNotBlank() }?.let { Disclose("What you said", it) }
                    }
                    else -> Waiting("Transcribing, then grading…")
                }
            }
            val misses = misses(r)
            Text(if (misses.isEmpty()) "What you missed" else "What you missed (${misses.size})", style = MaterialTheme.typography.titleMedium)
            if (misses.isEmpty()) Text("Nothing. Every multiple-choice answer was right.", color = cs.onSurfaceVariant)
            misses.forEach { MissCard(it) }
            FilledTonalButton(onClick = { nav.c.popBackStack("bench", false).let { ok -> if (!ok) nav.c.navigate("bench") } }) { Text("All sittings") }
        }
    }
}

private fun fmt(v: JsonElement?): String {
    val d = v.dbl ?: return "—"
    return if (d == Math.rint(d)) "${d.toInt()}" else "%.1f".format(d)
}

@Composable
private fun Feedback(g: JsonElement?) {
    g["strength"].str?.takeIf { it.isNotBlank() }?.let { IconLine(Icons.Filled.AddCircle, LocalBinah.current.good, it) }
    g["work_on"].str?.takeIf { it.isNotBlank() }?.let { IconLine(Icons.AutoMirrored.Filled.ArrowForward, MaterialTheme.colorScheme.primary, it) }
}

@Composable
private fun Disclose(title: String, text: String) {
    var open by remember { mutableStateOf(false) }
    TextButton(onClick = { open = !open }) { Text(if (open) "Hide" else title) }
    if (open) SelectionContainer { Text(text, style = readingStyle(15), color = MaterialTheme.colorScheme.onSurfaceVariant) }
}

private data class Miss(val sec: String, val item: BenchItem, val mine: JsonElement?)

private fun misses(r: BenchReview): List<Miss> = buildList {
    val a = r.answers
    for (s in r.form.sections) when (s.kind) {
        "argument", "vocab" -> (s.items ?: emptyList()).forEach { val m = a["${s.kind}:${it.key}"]; if (m["choice"].int != it.answer) add(Miss(s.kind, it, m)) }
        "inference" -> (s.passages ?: emptyList()).forEach { p -> p.questions.forEach { q -> val m = a["inference:${q.key}"]; if (m["choice"].int != q.answer) add(Miss("inference", q, m)) } }
        "discern" -> (s.items ?: emptyList()).forEach { val m = a["discern:${it.key}"]; if (m["kind"].str != it.kind) add(Miss("discern", it, m)) }
    }
}

private fun option(it: BenchItem, k: Int?): String {
    val o = it.options ?: return "no answer"
    if (k == null || k < 0 || k >= o.size) return "no answer"
    return "${letters[k]}. ${o[k]}"
}

@Composable
private fun MissCard(m: Miss) {
    val it = m.item
    val cs = MaterialTheme.colorScheme
    val b = LocalBinah.current
    val conf = m.mine["confidence"].int?.let { " ($it% sure)" } ?: ""
    BCard(title = sectionNames[m.sec] ?: m.sec) {
        if (m.sec == "discern") {
            Text(it.text ?: "", style = readingStyle(16))
            val said = m.mine["kind"].str
            Text(buildAnnotatedString {
                append("You said ")
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(if (said == "technique") "manipulation" else if (said == "fair") "fair" else "nothing") }
                append("$conf. It's ")
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(if (it.kind == "fair") "a fair move" else (it.technique ?: "")) }
                append(if (it.kind == "fair") ", resembling ${it.technique ?: ""}." else ".")
            }, style = MaterialTheme.typography.bodyMedium)
            it.tell?.takeIf { t -> t.isNotBlank() }?.let { t -> Text("The tell: “$t”", style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant) }
            it.why?.let { w -> Text(w, style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant) }
        } else {
            if (m.sec == "vocab") Text(it.sentence ?: "")
            if (m.sec == "argument") Disclose("The argument", it.stimulus ?: "")
            Text(if (m.sec == "vocab") "“${it.word ?: ""}”" else (it.stem ?: ""), fontWeight = FontWeight.SemiBold)
            Text("You: " + option(it, m.mine["choice"].int) + conf, style = MaterialTheme.typography.bodyMedium, color = cs.error)
            Text("Answer: " + option(it, it.answer), style = MaterialTheme.typography.bodyMedium, color = b.good)
            it.explanation?.let { e -> Text(e, style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant) }
        }
    }
}
