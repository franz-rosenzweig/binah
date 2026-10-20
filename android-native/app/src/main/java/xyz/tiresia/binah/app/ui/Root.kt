package xyz.tiresia.binah.app.ui

import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import kotlinx.coroutines.launch
import xyz.tiresia.binah.app.bench.BenchOverview
import xyz.tiresia.binah.app.bench.BenchReviewScreen
import xyz.tiresia.binah.app.bench.BenchSitting
import xyz.tiresia.binah.app.core.Api
import xyz.tiresia.binah.app.core.AppModel
import xyz.tiresia.binah.app.core.PlayContext
import xyz.tiresia.binah.app.core.Server
import xyz.tiresia.binah.app.games.GameScreen
import xyz.tiresia.binah.app.games.GoldenPlay
import xyz.tiresia.binah.app.platform.SelfTest

data class Tab(val route: String, val title: String, val on: ImageVector, val off: ImageVector)

val tabs = listOf(
    Tab("today", "Today", Icons.Filled.CalendarToday, Icons.Outlined.CalendarToday),
    Tab("practice", "Practice", Icons.Filled.GridView, Icons.Outlined.GridView),
    Tab("skills", "Skills", Icons.Filled.BarChart, Icons.Outlined.BarChart),
    Tab("golden", "Golden set", Icons.Filled.Star, Icons.Outlined.StarOutline),
)

/** How the screens move: tabs, then games and the benchmark on top of them. */
class Nav(val c: NavHostController, val model: AppModel) {
    fun tab(r: String) = c.navigate(r) { popUpTo("today") { saveState = true }; launchSingleTop = true; restoreState = true }
    fun play(game: String, ids: List<String>, day: String? = null, slot: Int? = null) =
        c.navigate("play/$game/${Uri.encode(ids.joinToString(","))}?day=${day ?: ""}&slot=${slot ?: -1}")
    fun golden(id: String) = c.navigate("goldenplay/${Uri.encode(id)}")
    fun benchRun() = c.navigate("benchrun")
    fun benchReview(run: Int) = c.navigate("benchreview/$run") { popUpTo("bench") }
    fun back() { if (!c.popBackStack()) tab("today") }
    /** After a game: today again, or another round of it. */
    suspend fun finished(ctx: PlayContext) {
        if (ctx.fromToday) { c.popBackStack("today", false); model.refresh() }
        else runCatching { Api.get<xyz.tiresia.binah.app.core.PracticePick>("/api/practice/${ctx.game}") }
            .onSuccess { c.popBackStack(); play(ctx.game, it.items) }
            .onFailure { model.flash(it.message ?: ""); c.popBackStack() }
    }
}

@Composable
fun Root(model: AppModel, pending: MutableState<String?>, selfTest: Boolean = false) {
    if (!model.signedIn) { SignIn(model); return }
    val controller = rememberNavController()
    val nav = remember(controller) { Nav(controller, model) }
    val snack = remember { SnackbarHostState() }
    val entry by controller.currentBackStackEntryAsState()
    val route = entry?.destination?.route ?: "today"
    LaunchedEffect(model.toast) { model.toast?.let { snack.showSnackbar(it) } }
    LaunchedEffect(pending.value) {
        pending.value?.let { r -> pending.value = null; if (r in listOf("today", "practice", "skills", "golden")) nav.tab(r) else if (r == "bench" || r == "settings") controller.navigate(r) }
    }
    if (selfTest) LaunchedEffect(Unit) { SelfTest.run(nav) }
    Scaffold(
        snackbarHost = { SnackbarHost(snack) },
        bottomBar = {
            if (tabs.any { it.route == route }) NavigationBar {
                tabs.forEach { t ->
                    NavigationBarItem(selected = route == t.route, onClick = { nav.tab(t.route) },
                                      icon = { Icon(if (route == t.route) t.on else t.off, null) }, label = { Text(t.title) })
                }
            }
        },
    ) { pad ->
        NavHost(controller, startDestination = "today", modifier = Modifier.padding(bottom = pad.calculateBottomPadding())) {
            composable("today") { TodayScreen(model, nav) }
            composable("practice") { PracticeScreen(model, nav) }
            composable("skills") { SkillsScreen(nav) }
            composable("golden") { GoldenScreen(nav) }
            composable("settings") { SettingsScreen(model, nav) }
            composable("bench") { BenchOverview(nav) }
            composable("benchrun") { BenchSitting(nav) }
            composable("benchreview/{run}", listOf(navArgument("run") { type = NavType.IntType })) {
                BenchReviewScreen(it.arguments?.getInt("run") ?: 0, nav)
            }
            composable("goldenplay/{id}") { GoldenPlay(Uri.decode(it.arguments?.getString("id") ?: ""), model, nav) }
            composable("play/{game}/{ids}?day={day}&slot={slot}", listOf(
                navArgument("day") { type = NavType.StringType; defaultValue = "" },
                navArgument("slot") { type = NavType.IntType; defaultValue = -1 },
            )) {
                val a = it.arguments
                val game = a?.getString("game") ?: ""
                val ids = Uri.decode(a?.getString("ids") ?: "").split(",").filter { s -> s.isNotEmpty() }
                val day = a?.getString("day")?.takeIf { d -> d.isNotEmpty() }
                val slot = a?.getInt("slot")?.takeIf { s -> s >= 0 }
                GameScreen(PlayContext(game, day, slot), ids, model, nav)
            }
        }
    }
}

/** A screen's top: back (on screens above the tabs), the title, a subtitle, and actions. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GameBar(title: String, subtitle: String, onBack: () -> Unit, actions: @Composable () -> Unit = {}) {
    TopAppBar(
        title = {
            Column {
                Text(title, style = MaterialTheme.typography.titleLarge)
                if (subtitle.isNotEmpty()) Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
        actions = { actions() },
    )
}

/** A tab's large title: the date (or a line) over the title, with actions at the right. */
@Composable
fun LargeTitle(title: String, kicker: String? = null, actions: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().statusBarsPadding().padding(start = 20.dp, end = 8.dp, top = 16.dp, bottom = 4.dp),
        verticalAlignment = Alignment.Bottom) {
        Column(Modifier.weight(1f)) {
            if (kicker != null) Text(kicker, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(title, style = MaterialTheme.typography.headlineLarge.copy(fontSize = 34.sp))
        }
        actions()
    }
}

/** Sign in once with the username and password; Binah then knows this phone by a device token. */
@Composable
fun SignIn(model: AppModel) {
    val c = LocalContext.current
    var user by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var problem by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    fun go() {
        if (busy || user.isBlank() || password.isBlank()) return
        busy = true; problem = null
        scope.launch {
            runCatching { Api.signIn(c, user, password) }.onSuccess { password = ""; model.signedIn() }.onFailure { problem = it.message }
            busy = false
        }
    }
    Box(Modifier.fillMaxSize().imePadding().padding(24.dp), contentAlignment = Alignment.Center) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(buildAnnotatedString {
                withStyle(SpanStyle(fontFamily = Reading, fontStyle = FontStyle.Italic, fontSize = 44.sp)) { append("binah ") }
                withStyle(SpanStyle(fontFamily = Reading, fontWeight = FontWeight.Bold, fontSize = 32.sp, color = MaterialTheme.colorScheme.primary)) { append("בינה") }
            })
            Text("Understanding, trained on real text.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(user, { user = it }, Modifier.fillMaxWidth(), label = { Text("Username") }, singleLine = true,
                              keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Next))
            OutlinedTextField(password, { password = it }, Modifier.fillMaxWidth(), label = { Text("Password") }, singleLine = true,
                              visualTransformation = PasswordVisualTransformation(),
                              keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Go),
                              keyboardActions = KeyboardActions(onGo = { go() }))
            problem?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            Button(onClick = { go() }, enabled = !busy && user.isNotBlank() && password.isNotBlank(),
                   modifier = Modifier.fillMaxWidth().height(56.dp)) { Text(if (busy) "Signing in…" else "Sign in") }
            Text("Binah at ${Uri.parse(Server.base(c)).host}. Another address: in Settings once signed in.",
                 style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
