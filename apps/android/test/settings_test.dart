import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('balance adjusts channels without mutating requested color', () {
    final rgb = [200, 100, 50];
    const settings = LightSettings(gains: [0.5, 1, 0.8]);
    expect(settings.apply(rgb), [100, 100, 40]);
    expect(rgb, [200, 100, 50]);
    expect(const LightSettings().apply(rgb), rgb);
  });
  test(
    'settings survive store recreation and stay isolated by light',
    () async {
      String? saved;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SettingsStore.channel, (call) async {
            if (call.method == 'save') {
              saved = call.arguments as String;
              return null;
            }
            return saved;
          });
      await SettingsStore().save({
        'lamp-a': const LightSettings(name: 'Desk', gains: [0.7, 1, 0.8]),
        'lamp-b': const LightSettings(name: 'Sofa'),
      });
      final loaded = await SettingsStore().load();
      expect(loaded['lamp-a']!.name, 'Desk');
      expect(loaded['lamp-a']!.apply([100, 100, 100]), [70, 100, 80]);
      expect(loaded['lamp-b']!.gains, [1, 1, 1]);
      expect(jsonDecode(saved!)['lamp-a']['name'], 'Desk');
    },
  );
  test('invalid persisted balance is rejected', () {
    for (final gains in [
      [1, 1],
      [1, -1, 1],
      [1, 1.1, 1],
      [1, 'bad', 1],
    ]) {
      expect(
        () => LightSettings.fromJson({
          'name': 'Desk',
          'order': 'RGB',
          'gains': gains,
        }),
        throwsFormatException,
      );
    }
  });
  test('existing balance migrates without changing outgoing color', () {
    final settings = LightSettings.fromJson({
      'name': 'Desk',
      'order': 'RGB',
      'gains': [1, 0.3, 0.75],
    });
    expect(settings.presets['Previous balance'], [1, 0.3, 0.75]);
    expect(settings.apply([239, 66, 255]), [239, 20, 191]);
    final reloaded = LightSettings.fromJson(settings.toJson());
    expect(reloaded.presets, settings.presets);
    expect(reloaded.gains, settings.gains);
  });
  test('malformed saved presets are rejected', () {
    for (final presets in [
      {
        'Bad': [2, 1, 1],
      },
      {
        '': [1, 1, 1],
      },
      {'Bad': 'oops'},
    ]) {
      expect(
        () => LightSettings.fromJson({
          'name': '',
          'order': 'RGB',
          'gains': [1, 1, 1],
          'presets': presets,
        }),
        throwsFormatException,
      );
    }
  });
  test('last color persists without replacing calibration profiles', () {
    const original = LightSettings(
      name: 'Desk',
      gains: [1, 0.3, 0.75],
      presets: {
        'Evening': [1, 0.3, 0.75],
      },
    );
    final saved = LightSettings.fromJson(
      original.withColor([239, 66, 255], 128).toJson(),
    );
    expect(saved.lastColor, [239, 66, 255]);
    expect(saved.lastBrightness, 128);
    expect(saved.presets, original.presets);
    expect(saved.gains, original.gains);
  });
}
