import 'package:flutter/material.dart';

const ink = Color(0xff111514);
const panel = Color(0xff1c2220);
const accent = Color(0xffd4efa3);

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

ThemeData lightAppTheme([AppAppearance appearance = AppAppearance.lime]) {
  final accent = appearance.accent;
  final ink = appearance.background;
  final panel = Color.lerp(ink, accent, .065)!;
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
    surface: ink,
    primary: accent,
    onPrimary: const Color(0xff161b17),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(surfaceContainer: panel),
  );
  return base.copyWith(
    scaffoldBackgroundColor: ink,
    textTheme: base.textTheme.copyWith(
      headlineLarge: const TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.3,
      ),
      headlineSmall: const TextStyle(
        fontSize: 25,
        fontWeight: FontWeight.w600,
        letterSpacing: -.6,
      ),
      titleLarge: const TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w600,
        letterSpacing: -.4,
      ),
      titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      bodyMedium: const TextStyle(fontSize: 14, height: 1.4),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      titleSpacing: 20,
      titleTextStyle: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: accent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: Color(0xff414a43)),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 10,
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ink,
      indicatorColor: scheme.primaryContainer,
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xff323a34),
      thickness: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: ink,
      showDragHandle: true,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?trailing,
      ],
    ),
  );
}

class StatePill extends StatelessWidget {
  const StatePill(this.label, {super.key, this.icon = Icons.circle_outlined});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xffc5ccc3)),
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
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                error ? Icons.error_outline : Icons.info_outline,
                size: 17,
                color: error
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  color: error
                      ? Theme.of(context).colorScheme.error
                      : const Color(0xffb9c4b9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xffadb8ae)),
          ),
        ],
      ),
    ),
  );
}
