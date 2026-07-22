package com.ksled.controller.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Accent = Color(0xFF7C4DFF)
private val AccentVariant = Color(0xFF00E5FF)

private val DarkColors = darkColorScheme(
    primary = Accent,
    onPrimary = Color.White,
    secondary = AccentVariant,
    onSecondary = Color.Black,
    background = Color(0xFF0B0B0F),
    onBackground = Color(0xFFECECF1),
    surface = Color(0xFF16161C),
    onSurface = Color(0xFFECECF1),
    surfaceVariant = Color(0xFF23232C),
    onSurfaceVariant = Color(0xFFB9B9C6),
    outline = Color(0xFF3A3A46),
)

private val LightColors = lightColorScheme(
    primary = Accent,
    secondary = AccentVariant,
)

@Composable
fun KsLedTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = Typography(),
        content = content,
    )
}
