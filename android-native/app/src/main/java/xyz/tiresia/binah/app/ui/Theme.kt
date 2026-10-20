package xyz.tiresia.binah.app.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// Material 3 seeded from Binah's teal (#12617F), as the design canvas has it, light and dark.

private val Light = lightColorScheme(
    primary = Color(0xFF12617F), onPrimary = Color.White, primaryContainer = Color(0xFFC1E8FF), onPrimaryContainer = Color(0xFF001E2C),
    secondary = Color(0xFF4D616C), onSecondary = Color.White, secondaryContainer = Color(0xFFD0E6F3), onSecondaryContainer = Color(0xFF091E28),
    tertiary = Color(0xFF5F5A7D), onTertiary = Color.White, tertiaryContainer = Color(0xFFE6DEFF), onTertiaryContainer = Color(0xFF1C1736),
    background = Color(0xFFF5FAFD), onBackground = Color(0xFF171C1F), surface = Color(0xFFF5FAFD), onSurface = Color(0xFF171C1F),
    surfaceVariant = Color(0xFFDCE4E9), onSurfaceVariant = Color(0xFF3F484D), outline = Color(0xFF6F787D), outlineVariant = Color(0xFFBFC8CD),
    surfaceContainerLowest = Color.White, surfaceContainerLow = Color(0xFFEFF4F8), surfaceContainer = Color(0xFFE9EFF2),
    surfaceContainerHigh = Color(0xFFE3E9EC), surfaceContainerHighest = Color(0xFFDEE3E6),
    error = Color(0xFFBA1A1A), onError = Color.White, errorContainer = Color(0xFFFFDAD6), onErrorContainer = Color(0xFF410002),
)

private val Dark = darkColorScheme(
    primary = Color(0xFF8FCDEE), onPrimary = Color(0xFF003548), primaryContainer = Color(0xFF004D67), onPrimaryContainer = Color(0xFFC1E8FF),
    secondary = Color(0xFFB4CAD6), onSecondary = Color(0xFF1F333D), secondaryContainer = Color(0xFF354A54), onSecondaryContainer = Color(0xFFD0E6F3),
    tertiary = Color(0xFFC9C1EA), onTertiary = Color(0xFF312C4C), tertiaryContainer = Color(0xFF47425F), onTertiaryContainer = Color(0xFFE6DEFF),
    background = Color(0xFF0F1417), onBackground = Color(0xFFDEE3E6), surface = Color(0xFF0F1417), onSurface = Color(0xFFDEE3E6),
    surfaceVariant = Color(0xFF3F484D), onSurfaceVariant = Color(0xFFBFC8CD), outline = Color(0xFF899297), outlineVariant = Color(0xFF3F484D),
    surfaceContainerLowest = Color(0xFF0A0F12), surfaceContainerLow = Color(0xFF171C1F), surfaceContainer = Color(0xFF1B2023),
    surfaceContainerHigh = Color(0xFF252B2E), surfaceContainerHighest = Color(0xFF303538),
    error = Color(0xFFFFB4AB), onError = Color(0xFF690005), errorContainer = Color(0xFF93000A), onErrorContainer = Color(0xFFFFDAD6),
)

/** The pillars' tonal containers (Understand, Reason, Express, Speak) and the right/wrong colours. */
@Immutable
data class BinahColors(
    val pillarContainer: Map<String, Color>, val onPillarContainer: Map<String, Color>,
    val good: Color, val goodContainer: Color, val onGoodContainer: Color, val amber: Color,
)

private val LightExtra = BinahColors(
    pillarContainer = mapOf("u" to Color(0xFFC1E8FF), "r" to Color(0xFFFFDCBE), "e" to Color(0xFFFFD9E2), "s" to Color(0xFFE9DDFF)),
    onPillarContainer = mapOf("u" to Color(0xFF001E2C), "r" to Color(0xFF2C1600), "e" to Color(0xFF3E001D), "s" to Color(0xFF23005C)),
    good = Color(0xFF1F7A3F), goodContainer = Color(0xFFC8ECCF), onGoodContainer = Color(0xFF00210B), amber = Color(0xFF8A5100),
)
private val DarkExtra = BinahColors(
    pillarContainer = mapOf("u" to Color(0xFF004D67), "r" to Color(0xFF6A3B00), "e" to Color(0xFF7A2948), "s" to Color(0xFF4F378B)),
    onPillarContainer = mapOf("u" to Color(0xFFC1E8FF), "r" to Color(0xFFFFDCBE), "e" to Color(0xFFFFD9E2), "s" to Color(0xFFEADDFF)),
    good = Color(0xFFA6D189), goodContainer = Color(0xFF1E5130), onGoodContainer = Color(0xFFC8ECCF), amber = Color(0xFFE5C890),
)

val LocalBinah = staticCompositionLocalOf { LightExtra }

/** Light or dark regardless of the phone's setting: the self-test's dark pictures. */
object ThemeOverride { var dark by mutableStateOf<Boolean?>(null) }

/** The reading face: the phone's serif. */
val Reading = FontFamily.Serif

@Composable
fun BinahTheme(content: @Composable () -> Unit) {
    val dark = ThemeOverride.dark ?: isSystemInDarkTheme()
    val base = MaterialTheme.typography
    val type = base.copy(
        displaySmall = base.displaySmall.copy(fontWeight = FontWeight.SemiBold),
        headlineLarge = base.headlineLarge.copy(fontWeight = FontWeight.SemiBold, letterSpacing = (-0.3).sp),
        titleLarge = base.titleLarge.copy(fontWeight = FontWeight.SemiBold),
    )
    androidx.compose.runtime.CompositionLocalProvider(LocalBinah provides if (dark) DarkExtra else LightExtra) {
        MaterialTheme(colorScheme = if (dark) Dark else Light, typography = type, content = content)
    }
}

fun readingStyle(size: Int = 18, weight: FontWeight = FontWeight.Normal) =
    TextStyle(fontFamily = Reading, fontSize = size.sp, lineHeight = (size * 1.5).sp, fontWeight = weight)
