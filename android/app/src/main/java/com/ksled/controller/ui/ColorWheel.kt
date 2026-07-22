package com.ksled.controller.ui

import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.Modifier
import androidx.compose.runtime.Composable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.Canvas
import androidx.compose.ui.unit.dp
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.sin

/**
 * Interactive HSV colour wheel. Angle selects hue, distance from centre selects
 * saturation. Value (brightness) is controlled separately by a slider.
 */
@Composable
fun ColorWheel(
    hue: Float,
    saturation: Float,
    modifier: Modifier = Modifier,
    onChange: (hue: Float, saturation: Float) -> Unit,
) {
    val hueColors = (0..360 step 30).map { h ->
        Color(android.graphics.Color.HSVToColor(floatArrayOf(h.toFloat(), 1f, 1f)))
    }

    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .pointerInput(Unit) {
                detectTapGestures { pos -> emit(pos, size.width, size.height, onChange) }
            }
            .pointerInput(Unit) {
                detectDragGestures { change, _ ->
                    change.consume()
                    emit(change.position, size.width, size.height, onChange)
                }
            },
    ) {
        val radius = min(size.width, size.height) / 2f
        val center = Offset(size.width / 2f, size.height / 2f)

        // Hue ring.
        drawCircle(brush = Brush.sweepGradient(hueColors, center), radius = radius, center = center)
        // Saturation falloff: white centre fading out.
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(Color.White, Color.Transparent),
                center = center,
                radius = radius,
            ),
            radius = radius,
            center = center,
        )

        drawSelector(center, radius, hue, saturation)
    }
}

private fun DrawScope.drawSelector(center: Offset, radius: Float, hue: Float, sat: Float) {
    val angle = Math.toRadians(hue.toDouble())
    val dist = sat * radius
    val pos = Offset(
        (center.x + cos(angle) * dist).toFloat(),
        (center.y + sin(angle) * dist).toFloat(),
    )
    val selColor = Color(android.graphics.Color.HSVToColor(floatArrayOf(hue, sat, 1f)))
    drawCircle(Color.White, radius = 14.dp.toPx(), center = pos)
    drawCircle(selColor, radius = 11.dp.toPx(), center = pos)
}

private fun emit(
    pos: Offset,
    width: Int,
    height: Int,
    onChange: (Float, Float) -> Unit,
) {
    val radius = min(width, height) / 2f
    val cx = width / 2f
    val cy = height / 2f
    val dx = pos.x - cx
    val dy = pos.y - cy
    var angle = Math.toDegrees(atan2(dy.toDouble(), dx.toDouble())).toFloat()
    if (angle < 0) angle += 360f
    val dist = hypot(dx, dy)
    val sat = (dist / radius).coerceIn(0f, 1f)
    onChange(angle, sat)
}

/** Convenience: current HSV colour as a Compose [Color] at full value. */
fun hsvColor(hue: Float, sat: Float, value: Float = 1f): Color =
    Color(android.graphics.Color.HSVToColor(floatArrayOf(hue, sat, value)))
