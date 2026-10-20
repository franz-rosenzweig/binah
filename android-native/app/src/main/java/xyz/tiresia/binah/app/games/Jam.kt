package xyz.tiresia.binah.app.games

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import xyz.tiresia.binah.app.core.Api
import xyz.tiresia.binah.app.core.Attempt
import xyz.tiresia.binah.app.core.Item
import xyz.tiresia.binah.app.core.PlayContext
import xyz.tiresia.binah.app.core.bool
import xyz.tiresia.binah.app.core.dbl
import xyz.tiresia.binah.app.core.get
import xyz.tiresia.binah.app.core.int
import xyz.tiresia.binah.app.core.list
import xyz.tiresia.binah.app.core.str
import xyz.tiresia.binah.app.core.strings
import xyz.tiresia.binah.app.platform.Recorder
import xyz.tiresia.binah.app.ui.BCard
import xyz.tiresia.binah.app.ui.IconLine
import xyz.tiresia.binah.app.ui.LocalBinah
import xyz.tiresia.binah.app.ui.Nav
import xyz.tiresia.binah.app.ui.RatingDelta
import xyz.tiresia.binah.app.ui.Ring
import xyz.tiresia.binah.app.ui.Tag
import xyz.tiresia.binah.app.ui.Waiting
import xyz.tiresia.binah.app.ui.band
import xyz.tiresia.binah.app.ui.bandColor
import xyz.tiresia.binah.app.ui.readingStyle

/** Just a Minute: sixty seconds on a topic without hesitation, repetition or deviation. The server
 *  transcribes the recording and counts pauses, fillers and repeats; Claude judges deviation and
 *  structure (docs/API.md, Just a Minute). */
@Composable
fun JamGame(item: Item, ctx: PlayContext, nav: Nav) {
    val c = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val recorder = remember { Recorder(c, 60f) }
    var phase by remember { mutableStateOf("ready") }   // ready, recording, sending, grading, result
    var attempt by remember { mutableStateOf<Attempt?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    val b = LocalBinah.current
    val cs = MaterialTheme.colorScheme

    fun upload(data: ByteArray, took: Long) {
        phase = "sending"
        view.keepScreenOn = false
        scope.launch {
            try {
                val a0 = Api.upload<Attempt>("/api/audio", mapOf("item_id" to item.id, "day" to (ctx.day ?: ""), "slot" to "${ctx.slot ?: -1}", "ms" to "$took"),
                                             data, "answer.m4a", "audio/mp4")
                phase = "grading"
                val a = if (a0.grading) Api.waitFor(a0.id) { !it.grading || it.waitsForTomorrow } else a0
                attempt = a
                phase = "result"
                Haptic.verdict(view, (a.score ?: 0.0) >= 0.65)
            } catch (e: Exception) {
                problem = e.message
                phase = "ready"
                recorder.state = Recorder.State.Idle
            }
        }
    }

    fun begin() {
        problem = null
        recorder.onFinish = { data, took -> upload(data, took) }
        try {
            recorder.start(scope)
            phase = "recording"
            view.keepScreenOn = true
            Haptic.confirm(view)
        } catch (e: Exception) { problem = "The microphone didn't start: ${e.message}" }
    }

    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) begin() else problem = "Binah can't use the microphone. Allow it in Settings → Apps → Binah → Permissions."
    }

    DisposableEffect(Unit) { onDispose { if (recorder.state == Recorder.State.Recording) recorder.cancel(); view.keepScreenOn = false } }

    GameColumn(follow = phase.takeIf { it == "result" }) {
        Surface(shape = RoundedCornerShape(28.dp), color = b.pillarContainer["s"]!!, contentColor = b.onPillarContainer["s"]!!) {
            Column(Modifier.fillMaxWidth().padding(22.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("YOUR TOPIC", style = MaterialTheme.typography.labelMedium, letterSpacing = 1.sp)
                Text(item.topic ?: "", style = readingStyle(28, FontWeight.SemiBold))
            }
        }
        when (phase) {
            "ready", "recording" -> {
                val rec = recorder.state == Recorder.State.Recording
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    val frac by animateFloatAsState(recorder.left / recorder.limit, label = "left")
                    Ring(frac, Modifier.size(220.dp), stroke = 12.dp) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(clock(if (rec) recorder.left else recorder.limit), fontSize = 54.sp, fontWeight = FontWeight.Medium)
                            Text("of 1:00", style = MaterialTheme.typography.bodyMedium, color = cs.onSurfaceVariant)
                        }
                    }
                    Levels(recorder.levels, rec)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("No hesitation", "No repetition", "No deviation").forEach { Tag(it) }
                    }
                    FilledIconButton(
                        onClick = {
                            if (rec) recorder.stop()
                            else if (c.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) begin()
                            else ask.launch(Manifest.permission.RECORD_AUDIO)
                        },
                        modifier = Modifier.size(96.dp).semantics { contentDescription = if (rec) "Stop and send" else "Start recording" },
                        shape = RoundedCornerShape(if (rec) 28.dp else 48.dp),
                        colors = IconButtonDefaults.filledIconButtonColors(containerColor = if (rec) cs.error else cs.primary,
                                                                           contentColor = if (rec) cs.onError else cs.onPrimary),
                    ) { Icon(if (rec) Icons.Filled.Stop else Icons.Filled.Mic, null, Modifier.size(40.dp)) }
                    Text(if (rec) "Stop sends it. Your voice goes only to your Binah server."
                         else "Tap to start. It stops by itself at sixty seconds.",
                         style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
                }
            }
            "sending" -> Waiting("Uploading the recording…")
            "grading" -> Waiting("Transcribing on the server, then Claude listens for deviation…")
            else -> attempt?.let { a ->
                JamResult(a)
                EndButtons(ctx, nav, attempt = a)
            }
        }
        problem?.let { Text(it, color = cs.error) }
    }
}

fun clock(t: Float): String {
    val s = Math.ceil(t.toDouble()).toInt()
    return "${s / 60}:" + "%02d".format(s % 60)
}

/** The microphone's level, as a row of bars. */
@Composable
fun Levels(levels: List<Float>, active: Boolean) {
    val color = if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant
    Row(Modifier.height(44.dp), horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        levels.forEach { l ->
            val h by animateFloatAsState(maxOf(4f, l * 40f), label = "level")
            Box(Modifier.width(4.dp).height(h.dp).clip(CircleShape).background(color))
        }
    }
}

/** What the server measured and Claude judged. */
@Composable
fun JamResult(a: Attempt) {
    val m = a.instant["metrics"] ?: a.answer["metrics"]
    val g = a.grade
    val ins = a.instant
    val cs = MaterialTheme.colorScheme
    fun num(v: JsonElement?, digits: Int = 0) = v.dbl?.let { "%.${digits}f".format(it) } ?: "—"
    BCard {
        listOf(listOf(num(m["speaking_time"]) + "s" to "speaking", num(m["wpm"]) to "words a minute", num(m["fillers_per_min"], 1) to "fillers a minute"),
               listOf(num(m["long_pauses"]) to "long pauses", "${m["repeats"].list.size}" to "repeated words",
                      (if (m["first_sentence_clean"].bool == true) "clean" else "not yet") to "first sentence"))
            .forEach { row ->
                Row(Modifier.fillMaxWidth()) {
                    row.forEach { (v, label) ->
                        Column(Modifier.weight(1f).padding(vertical = 4.dp)) {
                            Text(v, style = MaterialTheme.typography.titleLarge)
                            Text(label, style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
                        }
                    }
                }
            }
    }
    BCard {
        val later = a.later || (a.grade == null && a.waitsForTomorrow)
        Text(if (later) "Grading later" else band(a.score), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold,
             color = bandColor(a.score))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Tag("hesitation ${ins["hesitation"].int ?: "—"}/4")
            Tag("repetition ${ins["repetition"].int ?: "—"}/4")
            Tag("deviation ${g["deviation"].int ?: "—"}/4")
            Tag("structure ${g["structure"].int ?: "—"}/4")
        }
        g["strength"].str?.takeIf { it.isNotBlank() }?.let { IconLine(Icons.Filled.AddCircle, LocalBinah.current.good, it) }
        g["work_on"].str?.takeIf { it.isNotBlank() }?.let { IconLine(Icons.AutoMirrored.Filled.ArrowForward, cs.primary, it) }
        g["deviations"].strings.takeIf { it.isNotEmpty() }?.let {
            Text("Wandered at: " + it.joinToString(", ") { d -> "“$d”" }, style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
        }
        m["repeats"].list.takeIf { it.isNotEmpty() }?.let {
            Text("Said more than twice: " + it.joinToString(", ") { r -> "${r["word"].str ?: ""} ×${r["count"].int ?: 0}" },
                 style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
        }
    }
    RatingDelta(a)
    a.answer["text"].str?.takeIf { it.isNotBlank() }?.let { t ->
        var open by remember { mutableStateOf(false) }
        TextButton(onClick = { open = !open }) { Text(if (open) "Hide what you said" else "What you said") }
        if (open) Text(t, style = readingStyle(15), color = cs.onSurfaceVariant)
    }
}
