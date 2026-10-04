import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/app_preferences.dart';
import 'package:ks_light/app_style.dart';
import 'package:ks_light/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? stored;
  bool fail = false;
  setUp(() {
    stored = null;
    fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SettingsStore.channel, (call) async {
          if (call.method == 'loadAppPreferences') return stored;
          if (call.method == 'saveAppPreferences') {
            if (fail) throw PlatformException(code: 'SAVE_FAILED');
            stored = call.arguments as String;
          }
          return null;
        });
  });
  test(
    'themes and color brightness survive reload; failed saves preserve data',
    () async {
      final prefs = AppPreferences();
      await prefs.load();
      expect(
        await prefs.save(
          theme: AppAppearance.ocean,
          presets: {
            'Evening': SavedColor([239, 66, 255], 128),
          },
        ),
        isTrue,
      );
      final loaded = AppPreferences();
      await loaded.load();
      expect(loaded.appearance, AppAppearance.ocean);
      expect(loaded.colors['Evening']!.rgb, [239, 66, 255]);
      expect(loaded.colors['Evening']!.brightness, 128);
      fail = true;
      expect(
        await loaded.save(theme: AppAppearance.rose, presets: {}),
        isFalse,
      );
      expect(loaded.appearance, AppAppearance.ocean);
      expect(loaded.colors, contains('Evening'));
      prefs.dispose();
      loaded.dispose();
    },
  );
  test('unreadable preferences are never overwritten', () async {
    stored = '{broken';
    final prefs = AppPreferences();
    await prefs.load();
    expect(prefs.ready, isFalse);
    expect(await prefs.save(theme: AppAppearance.violet), isFalse);
    expect(stored, '{broken');
    prefs.dispose();
  });
  testWidgets('visible save, recall, delete and appearance controls', (
    tester,
  ) async {
    final prefs = AppPreferences();
    await prefs.load();
    SavedColor? recalled;
    await tester.pumpWidget(
      PreferencesScope(
        preferences: prefs,
        child: AnimatedBuilder(
          animation: prefs,
          builder: (_, _) => MaterialApp(
            theme: lightAppTheme(prefs.appearance),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    SavedColors(
                      rgb: const [239, 66, 255],
                      brightness: 128,
                      onSelected: (v) => recalled = v,
                    ),
                    const AppearancePicker(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save current'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Evening');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(recalled, isNull);
    await tester.tap(find.text('Evening'));
    await tester.pump();
    expect(recalled!.rgb, [239, 66, 255]);
    expect(recalled!.brightness, 128);
    await tester.tap(find.text('Violet'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('SAVED COLORS'))).colorScheme.primary,
      AppAppearance.violet.accent,
    );
    final reopened = AppPreferences();
    await reopened.load();
    expect(reopened.appearance, AppAppearance.violet);
    expect(reopened.colors, contains('Evening'));
    await tester.tap(find.byTooltip('Delete Evening'));
    await tester.pumpAndSettle();
    expect(prefs.colors, isEmpty);
    await tester.pumpWidget(const SizedBox());
    prefs.dispose();
    reopened.dispose();
  });
}
