package xyz.tiresia.binah.app.platform

import android.util.Log
import kotlinx.coroutines.delay
import xyz.tiresia.binah.app.core.Api
import xyz.tiresia.binah.app.core.Attempt
import xyz.tiresia.binah.app.core.BenchStatus
import xyz.tiresia.binah.app.core.GoldenInfo
import xyz.tiresia.binah.app.core.Item
import xyz.tiresia.binah.app.core.Nav as NavInfo
import xyz.tiresia.binah.app.core.PlayContext
import xyz.tiresia.binah.app.core.PracticeGame
import xyz.tiresia.binah.app.core.PracticePick
import xyz.tiresia.binah.app.core.Server
import xyz.tiresia.binah.app.core.ServerSettings
import xyz.tiresia.binah.app.core.SkillsInfo
import xyz.tiresia.binah.app.core.TodayInfo
import xyz.tiresia.binah.app.core.Widget
import xyz.tiresia.binah.app.core.get
import xyz.tiresia.binah.app.core.str
import xyz.tiresia.binah.app.core.submitAnswer
import xyz.tiresia.binah.app.ui.Nav
import xyz.tiresia.binah.app.ui.ThemeOverride

/**
 * The self-test (check.sh), in the debug build only: started with a sandbox's address and a device
 * token there (never the real Binah). It reads every endpoint the app reads and decodes it as the app
 * does; opens every room and game, saying "SHOT <name>" in the log so check.sh can picture the
 * screen, light and dark; and plays The Author's Word once, end to end (one answer written to the
 * sandbox). It ends with "SELFTEST passed" or "SELFTEST <n> failed".
 */
object SelfTest {
    private const val TAG = "BinahSelfTest"
    private var failures = 0

    fun log(s: String) { Log.i(TAG, s) }

    fun check(ok: Boolean, what: String, detail: String = "") {
        log((if (ok) "PASS  " else "FAIL  ") + what + if (detail.isEmpty()) "" else "  [${detail.take(300)}]")
        if (!ok) failures++
    }

    private suspend inline fun <reified T> decodes(what: String, path: String): T? =
        try { Api.get<T>(path).also { check(true, "$what decodes") } } catch (e: Exception) { check(false, "$what decodes", e.message ?: "$e"); null }

    /** Says the screen is ready to picture, and gives check.sh time to take it. */
    private suspend fun shot(name: String, settle: Long = 2500) {
        delay(settle)
        log("SHOT $name")
        delay(1800)
    }

    fun usable(it: Item): Boolean = when (it.game) {
        "gist" -> it.passage != null && it.inference_q != null
        "subtext" -> it.passage != null && it.question != null
        "bloat" -> it.padded != null && it.par != null
        "weak" -> !it.sentences.isNullOrEmpty() && !it.flaws.isNullOrEmpty()
        "word" -> it.sentence?.contains("_____") == true && !it.options.isNullOrEmpty()
        "tech" -> it.text != null && !it.techniques.isNullOrEmpty()
        "jam" -> it.topic != null
        else -> false
    }

    suspend fun run(nav: Nav) {
        failures = 0
        log("SELFTEST against ${Server.base(Api.app)}")
        // every answer the app reads, decoded as the app decodes it
        decodes<TodayInfo>("today", "/api/today")
        decodes<NavInfo>("nav", "/api/nav")
        decodes<Widget>("widget", "/api/widget")
        val practice = decodes<List<PracticeGame>>("practice", "/api/practice")
        decodes<SkillsInfo>("skills", "/api/skills")
        val golden = decodes<GoldenInfo>("golden", "/api/golden")
        decodes<BenchStatus>("benchmark", "/api/benchmark")
        decodes<ServerSettings>("settings", "/api/settings")
        val picks = sortedMapOf<String, List<String>>()
        for (g in practice ?: emptyList()) {
            if (g.live <= 0) continue
            val p = decodes<PracticePick>("practice/${g.game}", "/api/practice/${g.game}") ?: continue
            picks[g.game] = p.items
            for (id in if (g.game == "tech") p.items else p.items.take(1)) {
                val it = decodes<Item>("item $id", "/api/item/${Api.escape(id)}")
                check(it?.let(::usable) ?: false, "$id has what ${g.name} shows")
            }
        }

        // the rooms, then each game as it opens, pictured
        nav.model.refresh()
        for (r in listOf("today", "practice", "skills", "golden")) { nav.tab(r); shot("room-$r") }
        nav.c.navigate("settings"); shot("room-settings")
        nav.c.navigate("bench"); shot("room-bench")
        for ((game, ids) in picks) {
            nav.tab("practice"); delay(400)
            nav.play(game, ids); shot("game-$game")
        }
        golden?.next?.firstOrNull()?.let { id -> nav.tab("golden"); delay(400); nav.golden(id); shot("golden-play") }
        nav.tab("today")
        ThemeOverride.dark = true
        shot("room-today-dark", 1500)
        picks["weak"]?.let { nav.play("weak", it); shot("game-weak-dark") }
        picks["jam"]?.let { nav.tab("today"); delay(300); nav.play("jam", it); shot("game-jam-dark") }
        ThemeOverride.dark = null
        nav.tab("today")

        // one game end to end: The Author's Word answers at once, with the key and the rating's move
        val id = picks["word"]?.firstOrNull()
        if (id != null) try {
            val item = Api.get<Item>("/api/item/${Api.escape(id)}")
            val a = submitAnswer(item, mapOf("choice" to item.options!!.first()), null, System.currentTimeMillis() - 5000, PlayContext("word", null, null))
            check(a.status == "done" && a.key["target"].str != null && a.score != null,
                  "The Author's Word answers at once, with the key and a score", "score ${a.score}, target ${a.key["target"].str}")
            val again = Api.get<Attempt>("/api/attempts/${a.id}")
            check(again.id == a.id, "the answer reads back")
        } catch (e: Exception) { check(false, "The Author's Word answers", e.message ?: "$e") }
        log(if (failures == 0) "SELFTEST passed" else "SELFTEST $failures failed")
    }
}
