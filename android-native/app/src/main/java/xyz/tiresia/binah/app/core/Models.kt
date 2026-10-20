package xyz.tiresia.binah.app.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.contentOrNull

// The API's answers (binah/app.py, docs/API.md), as the app reads them. Anything that may be
// missing has a default, and unknown fields are ignored, so a new field never breaks the app.

@Serializable data class TodayInfo(
    val edition: Edition,
    val week: Week,
    val counts: Counts,
    val ratings: Map<String, Rating> = emptyMap(),
    val skills: Map<String, SkillMeta> = emptyMap(),
    val games: Map<String, GameMeta> = emptyMap(),
)

@Serializable data class Edition(val day: String, val slots: List<Slot> = emptyList(), val recall: Recall? = null, val finished: Boolean = false) {
    val done get() = slots.count { it.done }
    val next get() = slots.firstOrNull { !it.done }
    val minutesLeft get() = slots.filter { !it.done }.sumOf { it.minutes }
}

@Serializable data class Slot(
    val slot: Int, val game: String, val name: String? = null, val pillar: String? = null, val minutes: Int = 2,
    val items: List<String> = emptyList(), val done: Boolean = false, val answered: Int? = null, val source: String? = null,
    val scores: List<Double?> = emptyList(),
) {
    val average: Double? get() = scores.filterNotNull().takeIf { it.isNotEmpty() }?.average()
}

@Serializable data class Recall(val item: String? = null, val book: String? = null, val reference: String? = null,
                                val key_points: List<String> = emptyList(), val mark: String? = null)

@Serializable data class Week(val days: List<WeekDay> = emptyList(), val active: Int = 0, val goal: Int = 4)
@Serializable data class WeekDay(val day: String, val answers: Int = 0, val rest: Boolean = false, val future: Boolean = false, val today: Boolean = false)
@Serializable data class Counts(val editions: Int = 0, val answers: Int = 0, val passages: Int = 0, val arguments: Int = 0,
                                val minutes_spoken: Double = 0.0, val active_weeks: Int = 0)
@Serializable data class Rating(val rating: Int, val n: Int = 0, val calibrating: Boolean = false)
@Serializable data class SkillMeta(val pillar: String, val name: String)
@Serializable data class GameMeta(val name: String, val skill: String = "", val lane: String = "", val minutes: Int = 2, val blurb: String = "")

@Serializable data class PracticeGame(val game: String, val name: String, val minutes: Int = 2, val blurb: String = "", val live: Int = 0)
@Serializable data class PracticePick(val items: List<String>)

@Serializable data class SkillsInfo(
    val ratings: Map<String, Rating> = emptyMap(), val skills: Map<String, SkillMeta> = emptyMap(),
    val recent: Map<String, List<Double>> = emptyMap(), val discern: Discern = Discern(), val self_gap: Double? = null,
    val bench_due: Boolean = false,
)
@Serializable data class Discern(val n: Int = 0, val dprime: Double? = null, val bias: Double? = null, val hit_rate: Double? = null,
                                 val false_alarms: Double? = null, val brier: Double? = null)

@Serializable data class Nav(val today: DoneOf = DoneOf(), val golden: GoldenN = GoldenN(), val bench_due: Boolean = false,
                             val week: ActiveOf = ActiveOf(), val rest_weekday: Int? = null) {
    @Serializable data class DoneOf(val done: Int = 0, val total: Int = 0)
    @Serializable data class GoldenN(val n: Int = 0, val target: Int = 50)
    @Serializable data class ActiveOf(val active: Int = 0, val goal: Int = 4)
}

@Serializable data class ServerSettings(val weekly_goal_days: Int? = null, val rest_weekday: Int? = null, val grading_tone: String? = null)

@Serializable data class Widget(val day: String = "", val done: Int = 0, val total: Int = 0, val finished: Boolean = false,
                                val minutes_left: Double? = null, val next: Next? = null, val week: Nav.ActiveOf? = null) {
    @Serializable data class Next(val game: String, val name: String)
}

@Serializable data class Saved(val ok: Boolean = false, val message: String? = null)
@Serializable data class Device(val name: String, val token: String)

@Serializable data class ItemSource(val book: String? = null, val author: String? = null, val highlighted: Boolean? = null)

/** One playable item, as /api/item sends it: never the key. */
@Serializable data class Item(
    val id: String, val game: String, val skill: String? = null, val source: ItemSource? = null,
    val passage: String? = null, val inference_q: String? = null, val question: String? = null,
    val sentences: List<String>? = null, val flaws: List<String>? = null,
    val text: String? = null, val context: String? = null, val techniques: List<String>? = null,
    val sentence: String? = null, val options: List<String>? = null,
    val padded: String? = null, val par: Int? = null, val topic: String? = null,
)

/** One answer and what came of it: answer → verdict → one revision → the reference (docs/API.md). */
@Serializable data class Attempt(
    val id: Int, val item_id: String, val game: String, val status: String, val self_rating: Int? = null,
    val answer: JsonElement? = null, val instant: JsonElement? = null, val grade: JsonElement? = null,
    val revision: JsonElement? = null, val grade2: JsonElement? = null, val score: Double? = null, val score2: Double? = null,
    val rating_before: Int? = null, val rating_after: Int? = null, val skill: String? = null, val disputed: String? = null,
    val key: JsonElement? = null, val grading_later: Boolean? = null,
) {
    val grading get() = status == "grading"
    val later get() = status == "later"
    /** Nothing more will come today: stop polling. */
    val waitsForTomorrow get() = grading_later == true || later
}

@Serializable data class GoldenInfo(val report: GoldenReport, val next: List<String> = emptyList(),
                                    val rubrics: Map<String, Rubric> = emptyMap(), val disputed: List<Attempt> = emptyList())
@Serializable data class GoldenReport(val target: Int = 50, val total: Int = 0, val games: Map<String, GoldenGame> = emptyMap())
@Serializable data class GoldenGame(val scored: Int = 0, val graded: Int = 0, val criteria: Map<String, Agreement> = emptyMap())
@Serializable data class Agreement(val n: Int = 0, val exact: Double? = null, val within1: Double? = null, val lenient: Double? = null, val qwk: Double? = null)
@Serializable data class Rubric(val version: Int = 1, val criteria: Map<String, List<String>> = emptyMap()) {
    val ordered get() = Criteria.sorted(criteria.keys)
}
@Serializable data class GoldenKey(val key: JsonElement)

@Serializable data class BenchStatus(val forms: List<BenchFormInfo> = emptyList(), val runs: List<BenchRun> = emptyList())
@Serializable data class BenchFormInfo(val id: String, val created: String? = null, val sections: List<String> = emptyList())
@Serializable data class BenchRun(val id: Int, val form: String, val started: String? = null, val finished: String? = null, val results: JsonElement? = null)
@Serializable data class BenchStart(val run: Int, val form: BenchForm, val answers: Map<String, JsonElement> = emptyMap())
@Serializable data class BenchReview(val run: Int, val form: BenchForm, val answers: Map<String, JsonElement> = emptyMap(),
                                     val results: JsonElement? = null, val started: String? = null, val finished: String? = null)
@Serializable data class BenchForm(val id: String, val sections: List<BenchSection> = emptyList())
@Serializable data class BenchSection(val kind: String, val items: List<BenchItem>? = null, val passages: List<BenchPassage>? = null,
                                      val prompt: String? = null, val minutes: Int? = null, val seconds: Int? = null)
@Serializable data class BenchPassage(val source: String? = null, val text: String = "", val questions: List<BenchItem> = emptyList())
/** A question on a form; the review adds `answer`, `explanation`, and for fair-or-trick `kind`, `technique`, `tell`, `why`. */
@Serializable data class BenchItem(
    val id: JsonPrimitive, val stimulus: String? = null, val stem: String? = null, val options: List<String>? = null,
    val sentence: String? = null, val word: String? = null, val text: String? = null, val context: String? = null,
    val answer: Int? = null, val explanation: String? = null, val kind: String? = null, val technique: String? = null,
    val tell: String? = null, val why: String? = null,
) { val key get() = id.contentOrNull ?: id.toString() }

// MARK: reading free-form JSON (answers, grades, keys)

operator fun JsonElement?.get(k: String): JsonElement? = (this as? JsonObject)?.get(k)
val JsonElement?.str: String? get() = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
val JsonElement?.dbl: Double? get() = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.doubleOrNull
val JsonElement?.int: Int? get() = dbl?.let { Math.round(it).toInt() }
val JsonElement?.bool: Boolean? get() = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.booleanOrNull
val JsonElement?.list: List<JsonElement> get() = runCatching { this?.jsonArray?.toList() }.getOrNull() ?: emptyList()
val JsonElement?.strings: List<String> get() = list.mapNotNull { it.str }
val JsonElement?.isNullish: Boolean get() = this == null || this is JsonNull
/** Is this value a number (a criterion's score)? */
val JsonElement?.isNumber: Boolean get() = (this as? JsonPrimitive)?.let { !it.isString && it.doubleOrNull != null } ?: false

/** The order criteria are listed in (games.py RUBRICS); anything new comes after, alphabetically. */
object Criteria {
    private val known = listOf("main_idea", "accuracy", "concision", "inference", "precision", "meaning",
                               "hesitation", "repetition", "deviation", "structure", "understanding", "reason")
    fun sorted(keys: Collection<String>) = keys.sortedWith(compareBy({ known.indexOf(it).let { i -> if (i < 0) Int.MAX_VALUE else i } }, { it }))
    fun label(k: String) = k.replace('_', ' ')
}

/** The games' names and pillars, known without a network answer. */
object Games {
    val names = mapOf("gist" to "Gist & Infer", "subtext" to "Subtext", "weak" to "Find the Weak Step",
                      "tech" to "Technique or Fair Move?", "word" to "The Author's Word", "bloat" to "Cut the Bloat",
                      "jam" to "Just a Minute")
    val pillar = mapOf("gist" to "u", "subtext" to "u", "weak" to "r", "tech" to "r", "word" to "e", "bloat" to "e", "jam" to "s")
    val skillNames = mapOf("gist" to "Gist", "inference" to "Inference", "weak" to "Weak steps", "discern" to "Fair or trick",
                           "precision" to "Precision", "concision" to "Concision", "fluency" to "Fluency")
    val skillOrder = listOf("gist", "inference", "weak", "discern", "precision", "concision", "fluency")
    val pillarNames = mapOf("u" to "Understand", "r" to "Reason", "e" to "Express", "s" to "Speak")
    fun name(g: String) = names[g] ?: g
}

/** The word count of some text, as the server counts it. */
fun wordCount(s: String) = s.trim().split(Regex("\\s+")).count { it.isNotEmpty() }
