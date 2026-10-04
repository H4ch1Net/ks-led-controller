import 'dart:math' as math;

import 'package:flutter/material.dart';

// Lamp-lit instrument design system (docs/DESIGN.md). A neutral graphite body,
// printed labels and one signal accent; the only saturated color is light.
const ink = Color(0xff111514);
const panel = Color(0xff191e1c);
const accent = Color(0xffd4efa3);
const textPrimary = Color(0xffecf0ec);
const textMuted = Color(0xff95a09b);
const textFaint = Color(0xff808b86);
const warnColor = Color(0xfff3c871);
const dangerColor = Color(0xffff8f80);
const hairline = Color(0x12ffffff);
const hairlineStrong = Color(0x21ffffff);

enum AppAppearance {
  lime('Lime', Color(0xffd4efa3), Color(0xff111514)),
  ocean('Ocean', Color(0xff8cd5ff), Color(0xff10151d)),
  violet('Violet', Color(0xffd0b4ff), Color(0xff17121e)),
  rose('Rose', Color(0xffffb4cc), Color(0xff1c1217)),
  amber('Amber', Color(0xffffd08a), Color(0xff1b1610));

  const AppAppearance(this.label, this.accent, this.background);
  final String label;
  final Color accent, background;
}

/// Surface tones derived from an appearance's background.
class Surfaces {
  Surfaces(Color ink)
    : base = ink,
      panel = Color.lerp(ink, Colors.white, .035)!,
      raised = Color.lerp(ink, Colors.white, .07)!,
      well = Color.lerp(ink, Colors.black, .28)!;
  final Color base, panel, raised, well;
}

ThemeData lightAppTheme([AppAppearance appearance = AppAppearance.lime]) {
  final accent = appearance.accent;
  final surfaces = Surfaces(appearance.background);
  final ink = surfaces.base;
  final panel = surfaces.panel;
  const onAccent = Color(0xff151a14);
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
    surface: ink,
    primary: accent,
    onPrimary: onAccent,
    error: dangerColor,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      surfaceContainer: panel,
      surfaceContainerHigh: surfaces.raised,
      surfaceContainerHighest: surfaces.raised,
      surfaceContainerLowest: surfaces.well,
      onSurface: textPrimary,
      onSurfaceVariant: textMuted,
      outline: hairlineStrong,
      outlineVariant: hairline,
    ),
  );
  RoundedRectangleBorder control([BorderSide side = BorderSide.none]) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: side,
      );
  return base.copyWith(
    scaffoldBackgroundColor: ink,
    textTheme: base.textTheme
        .copyWith(
          headlineLarge: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.1,
            height: 1.1,
          ),
          headlineSmall: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -.6,
          ),
          titleLarge: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -.4,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -.1,
          ),
          bodyMedium: const TextStyle(fontSize: 14, height: 1.4),
          labelSmall: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: textMuted,
          ),
        )
        .apply(bodyColor: textPrimary, displayColor: textPrimary),
    appBarTheme: AppBarTheme(
      backgroundColor: ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      elevation: 0,
      titleSpacing: 20,
      titleTextStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -.2,
        color: textPrimary,
      ),
      iconTheme: const IconThemeData(color: textMuted),
      actionsIconTheme: const IconThemeData(color: textMuted),
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: hairline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaces.well,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: hairlineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: hairlineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: control(),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: textPrimary,
        backgroundColor: surfaces.raised,
        shape: control(),
        side: const BorderSide(color: hairlineStrong),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: control()),
    ),
    // Rocker switch: recessed track, accent for the active side.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        shape: WidgetStatePropertyAll(control()),
        side: const WidgetStatePropertyAll(BorderSide(color: hairline)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? accent : surfaces.well,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? textFaint
              : states.contains(WidgetState.selected)
              ? onAccent
              : textMuted,
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: .8,
          ),
        ),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 4,
      activeTrackColor: accent,
      inactiveTrackColor: surfaces.well,
      thumbColor: const Color(0xffe6eae6),
      overlayColor: accent.withValues(alpha: .12),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
      thumbShape: const FaderThumbShape(),
      trackShape: const FaderTrackShape(),
      tickMarkShape: SliderTickMarkShape.noTickMark,
      showValueIndicator: ShowValueIndicator.onDrag,
      valueIndicatorColor: surfaces.raised,
      valueIndicatorTextStyle: const TextStyle(color: textPrimary),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: surfaces.well,
      selectedColor: accent.withValues(alpha: .16),
      side: const BorderSide(color: hairlineStrong),
      shape: const StadiumBorder(side: BorderSide(color: hairlineStrong)),
      labelStyle: const TextStyle(color: textPrimary, fontSize: 13),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ink,
      surfaceTintColor: Colors.transparent,
      indicatorColor: accent.withValues(alpha: .16),
      indicatorShape: control(),
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? accent : textMuted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: .3,
          color: states.contains(WidgetState.selected)
              ? textPrimary
              : textMuted,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(color: hairline, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: hairline),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: hairlineStrong,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surfaces.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: hairline),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaces.raised,
      contentTextStyle: const TextStyle(color: textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: hairlineStrong),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: const WidgetStatePropertyAll(hairlineStrong),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      iconColor: textMuted,
    ),
  );
}

/// Slider cap: a small rounded fader knob instead of a material dot.
class FaderThumbShape extends SliderComponentShape {
  const FaderThumbShape();
  static const size = Size(16, 26);

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => size;

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final scale = 1 + .08 * activationAnimation.value;
    final rect = Rect.fromCenter(
      center: center,
      width: size.width * scale,
      height: size.height * scale,
    );
    final cap = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas.drawRRect(
      cap.shift(const Offset(0, 1.5)),
      Paint()
        ..color = Colors.black.withValues(alpha: .45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    final enabled = enableAnimation.value > .5;
    canvas.drawRRect(
      cap,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: enabled
              ? const [Color(0xfff2f5f2), Color(0xffc9cfcb)]
              : const [Color(0xff5c6460), Color(0xff4a514e)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      cap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: .4),
    );
    canvas.drawLine(
      Offset(rect.left + 4, center.dy),
      Offset(rect.right - 4, center.dy),
      Paint()
        ..strokeWidth = 1.2
        ..color = Colors.black.withValues(alpha: .28),
    );
  }
}

/// Fader track with printed 10% tick marks beneath it.
class FaderTrackShape extends RoundedRectSliderTrackShape {
  const FaderTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: 0,
    );
    final track = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final tick = Paint()
      ..color = hairlineStrong
      ..strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      final x = track.left + track.width * i / 10;
      final long = i % 5 == 0;
      context.canvas.drawLine(
        Offset(x, track.bottom + 7),
        Offset(x, track.bottom + (long ? 13 : 10)),
        tick,
      );
    }
  }
}

/// Printed panel label: small, uppercase, tracked. Optional icon and trailing widget.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing, this.icon});
  final String title;
  final Widget? trailing;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: textMuted),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Semantics(
              header: true,
              label: title,
              excludeSemantics: true,
              child: Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          if (trailing != null)
            // Large text: shrink the trailing control instead of overflowing.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * .6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: trailing,
              ),
            ),
        ],
      ),
    ),
  );
}

/// Indicator LED, as on a hardware panel.
class Led extends StatelessWidget {
  const Led({super.key, this.color, this.glow = true, this.size = 7});
  final Color? color;
  final bool glow;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c,
        boxShadow: glow
            ? [BoxShadow(color: c.withValues(alpha: .6), blurRadius: 6)]
            : null,
      ),
    );
  }
}

enum PillTone { ok, warn, neutral }

/// Status indicator: an LED and a short label in a hairline capsule.
class StatePill extends StatelessWidget {
  const StatePill(
    this.label, {
    super.key,
    this.icon = Icons.circle_outlined,
    this.tone = PillTone.ok,
  });
  final String label;
  final IconData icon;
  final PillTone tone;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: hairlineStrong),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Led(
          color: switch (tone) {
            PillTone.ok => Theme.of(context).colorScheme.primary,
            PillTone.warn => warnColor,
            PillTone.neutral => textFaint,
          },
          glow: tone != PillTone.neutral,
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 14, color: textMuted),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xffc5ccc7),
            ),
          ),
        ),
      ],
    ),
  );
}

class StatusNotice extends StatelessWidget {
  const StatusNotice(this.message, {super.key, this.busy = false});
  final String message;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    final lower = message.toLowerCase();
    final error = [
      'failed',
      'could not',
      'unavailable',
      'offline',
      'error',
      'no ks lights',
      'unrecognized',
      'not return',
    ].any(lower.contains);
    final color = error
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      error ? Icons.error_outline : Icons.info_outline,
                      size: 17,
                      color: color,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  color: error ? color : const Color(0xffc5ccc7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state with the articulated desk lamp drawing used across KS Light.
class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 30),
      child: Column(
        children: [
          ExcludeSemantics(
            child: SizedBox(
              width: 120,
              height: 90,
              child: CustomPaint(
                painter: LampPainter(
                  color: textMuted,
                  beam: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: textMuted),
          ),
        ],
      ),
    ),
  );
}

/// The KS Light desk lamp line drawing (160 x 120 design grid).
class LampPainter extends CustomPainter {
  const LampPainter({required this.color, this.beam});
  final Color color;
  final Color? beam;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / 160, size.height / 120);
    canvas.translate((size.width - 160 * s) / 2, (size.height - 120 * s) / 2);
    canvas.scale(s);
    if (beam != null) {
      final cone = Path()
        ..moveTo(34, 52)
        ..lineTo(62, 70)
        ..lineTo(40, 112)
        ..lineTo(-6, 112)
        ..close();
      canvas.drawPath(
        cone,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              beam!.withValues(alpha: .28),
              beam!.withValues(alpha: .02),
            ],
          ).createShader(const Rect.fromLTWH(-6, 52, 68, 60)),
      );
    }
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(const Offset(90, 112), const Offset(142, 112), line);
    canvas.drawLine(const Offset(116, 112), const Offset(116, 106), line);
    canvas.drawLine(const Offset(116, 106), const Offset(86, 62), line);
    canvas.drawLine(const Offset(86, 62), const Offset(60, 40), line);
    canvas.drawPath(
      Path()
        ..moveTo(64, 27)
        ..lineTo(78, 41)
        ..lineTo(62, 70)
        ..lineTo(34, 52)
        ..close(),
      line,
    );
    for (final (point, r) in [
      (const Offset(86, 62), 3.5),
      (const Offset(116, 106), 3.5),
      (const Offset(60, 40), 3.0),
    ]) {
      canvas.drawCircle(point, r, line);
    }
  }

  @override
  bool shouldRepaint(LampPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.beam != beam;
}

enum LensMotion { none, breathing, fading }

/// A lamp diffuser seen head-on: dark glass when off, the last-sent light when on.
/// Effects are drawn as still marks (rings for breathing, a hue sweep for fades)
/// so the app never runs an endless animation of its own.
class Lens extends StatelessWidget {
  const Lens({
    super.key,
    required this.color,
    this.lit = true,
    this.level = 1,
    this.motion = LensMotion.none,
    this.size = 52,
    this.standby = false,
  });
  final Color color;
  final bool lit;
  final double level;
  final LensMotion motion;
  final double size;

  /// Power unknown: show the remembered color faintly, without a halo.
  final bool standby;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _LensPainter(
          color,
          lit
              ? .8 + .2 * level.clamp(0, 1)
              : standby
              ? .3
              : 0.0,
          lit ? level.clamp(0, 1).toDouble() : 0,
          halo: lit,
          motion: lit ? motion : LensMotion.none,
        ),
      ),
    ),
  );
}

class _LensPainter extends CustomPainter {
  _LensPainter(
    this.color,
    this.opacity,
    this.level, {
    this.halo = true,
    this.motion = LensMotion.none,
  });
  final Color color;
  final double opacity, level;
  final bool halo;
  final LensMotion motion;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    // Dark glass housing.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.3),
          colors: [Color(0xff2b3330), Color(0xff151a18)],
          stops: [0, .7],
        ).createShader(rect),
    );
    if (opacity > 0) {
      if (halo) {
        canvas.drawCircle(
          center,
          radius * (1 + .25 * level),
          Paint()
            ..color = color.withValues(alpha: .35 * opacity)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 10 * level),
        );
      }
      if (motion == LensMotion.fading) {
        // Fade effects cycle hues on the lamp: show the cycle as a sweep.
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..shader = SweepGradient(
              colors: [
                for (var h = 0; h <= 360; h += 60)
                  HSVColor.fromAHSV(opacity, h % 360, .72, 1).toColor(),
              ],
            ).createShader(rect),
        );
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..shader = RadialGradient(
              colors: [
                Colors.white.withValues(alpha: .55 * opacity),
                Colors.white.withValues(alpha: 0),
              ],
              stops: const [0, .6],
            ).createShader(rect),
        );
      } else {
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(0, -.24),
              colors: [
                Color.lerp(color, Colors.white, .7)!.withValues(alpha: opacity),
                color.withValues(alpha: opacity),
                Color.lerp(
                  color,
                  Colors.black,
                  .28,
                )!.withValues(alpha: opacity),
              ],
              stops: const [0, .45, 1],
            ).createShader(rect),
        );
      }
      if (motion == LensMotion.breathing) {
        // Breathing: concentric pulse rings in the light's color.
        for (final (scale, alpha) in [(.52, .5), (.3, .35)]) {
          canvas.drawCircle(
            center,
            radius * scale,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = Colors.white.withValues(alpha: alpha * opacity),
          );
        }
      }
    }
    canvas.drawCircle(
      center,
      radius - .5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = hairlineStrong,
    );
    canvas.drawCircle(
      center,
      radius * .73,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white.withValues(alpha: .05),
    );
  }

  @override
  bool shouldRepaint(_LensPainter old) =>
      old.color != color ||
      old.opacity != opacity ||
      old.level != level ||
      old.motion != motion;
}

/// One segment of a scene strip: a light's color, or off.
class StripSegment {
  const StripSegment(this.label, {this.color, this.off = false});
  final String label;
  final Color? color;
  final bool off;
}

/// A scene's lights as a strip of their colors, matching the hub dashboard.
class SceneStrip extends StatelessWidget {
  const SceneStrip(this.segments, {super.key, this.height = 22});
  final List<StripSegment> segments;
  final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(7),
    child: SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, segment) in segments.take(8).indexed) ...[
            if (index > 0) const SizedBox(width: 2),
            Expanded(
              child: Tooltip(
                message: segment.label,
                child: segment.off || segment.color == null
                    ? CustomPaint(
                        painter: _HatchPainter(segment.off),
                        child: const SizedBox.expand(),
                      )
                    : ColoredBox(color: segment.color!),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter(this.off);
  final bool off;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = off ? const Color(0xff181d1b) : const Color(0xffe9ece6),
    );
    if (!off) return;
    final stripe = Paint()
      ..color = const Color(0xff222826)
      ..strokeWidth = 4;
    for (var x = -size.height; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stripe,
      );
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.off != off;
}
