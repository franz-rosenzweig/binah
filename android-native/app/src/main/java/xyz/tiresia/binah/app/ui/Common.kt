package xyz.tiresia.binah.app.ui

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.GraphicEq
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.serialization.json.JsonObject
import xyz.tiresia.binah.app.core.Attempt
import xyz.tiresia.binah.app.core.Criteria
import xyz.tiresia.binah.app.core.Games
import xyz.tiresia.binah.app.core.ItemSource
import xyz.tiresia.binah.app.core.get
import xyz.tiresia.binah.app.core.int
import xyz.tiresia.binah.app.core.isNumber
import xyz.tiresia.binah.app.core.str

object Pillar {
    fun icon(p: String): ImageVector = when (p) {
        "u" -> Icons.AutoMirrored.Outlined.MenuBook
        "r" -> Icons.Outlined.AccountTree
        "e" -> Icons.Outlined.Edit
        else -> Icons.Outlined.GraphicEq
    }
    fun name(p: String) = Games.pillarNames[p] ?: ""
}

/** A pillar's icon in its tonal container, the Material way. */
@Composable
fun PillarIcon(pillar: String, size: Dp = 44.dp) {
    val b = LocalBinah.current
    Box(Modifier.size(size).clip(RoundedCornerShape(size * 0.32f)).background(b.pillarContainer[pillar] ?: Color.Gray),
        contentAlignment = Alignment.Center) {
        Icon(Pillar.icon(pillar), contentDescription = null, tint = b.onPillarContainer[pillar] ?: Color.Black, modifier = Modifier.size(size * 0.5f))
    }
}

/** A progress ring, with whatever goes in its middle. */
@Composable
fun Ring(fraction: Float, modifier: Modifier, stroke: Dp = 7.dp, color: Color = MaterialTheme.colorScheme.primary,
         track: Color = MaterialTheme.colorScheme.surfaceContainerHighest, content: @Composable () -> Unit = {}) {
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val w = stroke.toPx()
            val inset = w / 2
            val s = Size(size.width - w, size.height - w)
            drawArc(track, 0f, 360f, false, Offset(inset, inset), s, style = Stroke(w))
            drawArc(color, -90f, 360f * fraction.coerceIn(0.002f, 1f), false, Offset(inset, inset), s, style = Stroke(w, cap = StrokeCap.Round))
        }
        content()
    }
}

/** Material 3's expressive progress: a wave for what's done, a flat track for the rest, a stop dot
 *  at the end. (The library's own is still experimental.) */
@Composable
fun WavyProgress(fraction: Float, modifier: Modifier, color: Color = MaterialTheme.colorScheme.primary,
                 track: Color = MaterialTheme.colorScheme.primary.copy(alpha = 0.22f)) {
    Canvas(modifier) {
        val w = 4.dp.toPx()
        val mid = size.height / 2
        val amp = (size.height - w) / 2 * 0.55f
        val wave = 22.dp.toPx()
        val end = size.width * fraction.coerceIn(0f, 1f)
        val gap = if (fraction in 0.001f..0.999f) 6.dp.toPx() else 0f
        if (end > w) {
            val p = androidx.compose.ui.graphics.Path()
            var x = w / 2
            p.moveTo(x, mid)
            while (x < end - w / 2) {
                x = minOf(x + 1.5f, end - w / 2)
                p.lineTo(x, mid + amp * kotlin.math.sin(2 * Math.PI * x / wave).toFloat())
            }
            drawPath(p, color, style = Stroke(w, cap = StrokeCap.Round))
        }
        val from = if (end > w) end + gap else w / 2
        if (from < size.width - w / 2) {
            drawLine(track, Offset(from, mid), Offset(size.width - w / 2, mid), strokeWidth = w, cap = StrokeCap.Round)
            drawCircle(color, w / 2, Offset(size.width - w / 2, mid))
        }
    }
}

/** What a 0–1 score is called (play.js bandOf). */
fun band(s: Double?): String = when {
    s == null -> "Graded"
    s >= 0.85 -> "Strong"
    s >= 0.65 -> "Solid"
    s >= 0.4 -> "Partial"
    else -> "Missed"
}

@Composable
fun bandColor(s: Double?): Color = when {
    s == null -> MaterialTheme.colorScheme.onSurfaceVariant
    s >= 0.65 -> LocalBinah.current.good
    s >= 0.4 -> LocalBinah.current.amber
    else -> MaterialTheme.colorScheme.error
}

/** A labelled card in the surface's container colour. */
@Composable
fun BCard(title: String? = null, modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.surfaceContainer,
          content: @Composable ColumnScope.() -> Unit) {
    Surface(modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp), color = color) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (title != null) Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            content()
        }
    }
}

/** A little tonal tag for a criterion's score. */
@Composable
fun Tag(text: String, color: Color = MaterialTheme.colorScheme.secondaryContainer, on: Color = MaterialTheme.colorScheme.onSecondaryContainer) {
    Text(text, style = MaterialTheme.typography.labelMedium, color = on,
         modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(color).padding(horizontal = 10.dp, vertical = 5.dp))
}

/** A line with a leading icon: the strength, the thing to work on, the hint. */
@Composable
fun IconLine(icon: ImageVector, tint: Color, text: String, color: Color = MaterialTheme.colorScheme.onSurface) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(20.dp).padding(top = 1.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium, color = color)
    }
}

/** Claude's verdict on an open answer: the band, the criteria, a strength, a thing to work on, a hint. */
@Composable
fun VerdictCard(a: Attempt, second: Boolean = false) {
    val g = if (second) a.grade2 else a.grade
    val score = if (second) a.score2 else a.score
    BCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(band(score) + if (second) " · revised" else "", style = MaterialTheme.typography.headlineSmall,
                 fontWeight = FontWeight.SemiBold, color = bandColor(score), modifier = Modifier.weight(1f))
            if (!second && a.self_rating != null) Text("You said ${a.self_rating}/4", style = MaterialTheme.typography.bodyMedium,
                                                       color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        val crit = Criteria.sorted((g as? JsonObject)?.filter { (k, v) -> k != "covered" && v.isNumber }?.keys ?: emptySet())
        if (crit.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            crit.forEach { Tag("${Criteria.label(it)} ${g[it].int ?: 0}/4") }
        }
        g["strength"].str?.takeIf { it.isNotBlank() }?.let { IconLine(Icons.Filled.AddCircle, LocalBinah.current.good, it) }
        g["work_on"].str?.takeIf { it.isNotBlank() }?.let { IconLine(Icons.AutoMirrored.Filled.ArrowForward, MaterialTheme.colorScheme.primary, it) }
        if (!second) g["hint"].str?.takeIf { it.isNotBlank() }?.let {
            IconLine(Icons.Outlined.Lightbulb, MaterialTheme.colorScheme.onSurfaceVariant, "Hint: $it", MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** The rating's move on the first try: "Gist 1180 → 1196  +16". */
@Composable
fun RatingDelta(a: Attempt) {
    val b = a.rating_before ?: return
    val after = a.rating_after ?: return
    val d = after - b
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(Games.skillNames[a.skill] ?: a.skill ?: "", modifier = Modifier.weight(1f))
            Text("$b → $after", fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.width(12.dp))
            Text((if (d >= 0) "+" else "") + d, fontWeight = FontWeight.SemiBold,
                 color = if (d >= 0) LocalBinah.current.good else MaterialTheme.colorScheme.error)
        }
    }
}

/** A 0–4 self-rating, asked before the verdict. */
@Composable
fun SelfRating(value: Int?, onChange: (Int) -> Unit) {
    val view = LocalView.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("How sure are you? Rate it before the verdict.", style = MaterialTheme.typography.bodyMedium,
             color = MaterialTheme.colorScheme.onSurfaceVariant)
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            (0..4).forEach { n ->
                SegmentedButton(selected = value == n, onClick = { onChange(n); view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) },
                                shape = SegmentedButtonDefaults.itemShape(n, 5)) { Text("$n") }
            }
        }
    }
}

@Composable
fun Waiting(text: String) {
    Row(Modifier.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.5.dp)
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** A passage in the reading face, its paragraphs apart; text can be selected. */
@Composable
fun Passage(text: String, size: Int = 18) {
    SelectionContainer {
        Column(verticalArrangement = Arrangement.spacedBy((size * 0.8).dp)) {
            text.split(Regex("\\n\\s*\\n")).map { it.replace('\n', ' ').trim() }.filter { it.isNotEmpty() }.forEach {
                Text(it, style = readingStyle(size), color = MaterialTheme.colorScheme.onSurface)
            }
        }
    }
}

/** "From <book> · <author> · you highlighted this". */
@Composable
fun SourceLine(s: ItemSource?) {
    val book = s?.book ?: return
    val author = s.author?.split("&")?.first()?.trim()
    Text(buildString {
        append("From "); append(book)
        if (!author.isNullOrBlank()) append(" · $author")
        if (s.highlighted == true) append(" · you highlighted this")
    }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
}

/** A multi-line answer box. */
@Composable
fun AnswerBox(value: String, onChange: (String) -> Unit, label: String, minLines: Int = 3, enabled: Boolean = true, reading: Boolean = false) {
    OutlinedTextField(value, onChange, Modifier.fillMaxWidth(), label = { Text(label) }, minLines = minLines, enabled = enabled,
                      textStyle = if (reading) readingStyle(17) else MaterialTheme.typography.bodyLarge, shape = RoundedCornerShape(16.dp))
}

/** A question asked of the player. */
@Composable
fun Ask(text: String) { Text(text, style = MaterialTheme.typography.titleMedium) }
