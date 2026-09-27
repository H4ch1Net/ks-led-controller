import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/home_library.dart';
import 'package:ks_light/main.dart';
import 'package:ks_light/light_backend.dart';
import 'package:ks_light/settings.dart';

HomeLibrary saved() => HomeLibrary(
  lights: {
    'saved-a': {'name': 'Desk', 'prefix': 'KS03~'},
    'saved-b': {'name': 'Shelf', 'prefix': 'KS03~'},
  },
);
void main() {
  setUp(() => rootBundle.clear());
  test('default roundtrip, old libraries and dangling ID validation', () {
    final library = saved()..defaultLightId = 'saved-b';
    expect(library.copy().defaultLightId, 'saved-b');
    final old = library.toJson()..remove('default_light_id');
    expect(HomeLibrary.fromJson(old).defaultLightId, isNull);
    expect(
      () => HomeLibrary.fromJson({...old, 'default_light_id': 'missing'}),
      throwsFormatException,
    );
  });
  test('forget cleans memberships/default and preserves other devices', () {
    final library = saved()..defaultLightId = 'saved-a';
    library.collections['Both'] = const LightCollection('group', [
      'saved-a',
      'saved-b',
    ]);
    library.collections['Only'] = const LightCollection('room', ['saved-a']);
    library.scenes['Both'] = {
      'saved-a': const SceneState(power: true),
      'saved-b': const SceneState(power: false),
    };
    library.scenes['Only'] = {'saved-a': const SceneState(power: true)};
    library.forget('saved-a');
    final restored = library.copy();
    expect(restored.defaultLightId, isNull);
    expect(restored.lights.keys, ['saved-b']);
    expect(restored.collections['Both']!.members, ['saved-b']);
    expect(restored.collections.containsKey('Only'), isFalse);
    expect(restored.scenes['Both']!.keys, ['saved-b']);
    expect(restored.scenes.containsKey('Only'), isFalse);
  });
  testWidgets('remove cancellation, failed save, successful save and restart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var stored = jsonEncode(saved().toJson());
    var fail = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SettingsStore.channel, (call) async {
          if (call.method == 'loadLibrary') return stored;
          if (call.method == 'saveLibrary') {
            if (fail) throw StateError('disk unavailable');
            stored = (call.arguments as Map)['json'] as String;
          }
          return null;
        });
    final backend = DemoBackend();
    await tester.pumpWidget(KsLightApp(backend: backend));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove device').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Desk'), findsOneWidget);
    fail = true;
    await tester.tap(find.byTooltip('Remove device').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Desk'), findsOneWidget);
    fail = false;
    await tester.tap(find.byTooltip('Remove device').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Desk'), findsNothing);
    expect(find.text('Shelf'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(KsLightApp(backend: backend));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Desk'), findsNothing);
    expect(find.text('Shelf'), findsOneWidget);
    expect(backend.sent, isEmpty);
  });
  testWidgets(
    'saved devices merge scans and default survives restart without writes',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var stored = jsonEncode(saved().toJson());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SettingsStore.channel, (call) async {
            if (call.method == 'loadLibrary') return stored;
            if (call.method == 'saveLibrary') {
              stored = (call.arguments as Map)['json'] as String;
            }
            return null;
          });
      final backend = DemoBackend();
      await tester.pumpWidget(KsLightApp(backend: backend));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Desk'), findsOneWidget);
      expect(find.text('Shelf'), findsOneWidget);
      await tester.tap(find.text('Add devices'));
      await tester.pumpAndSettle();
      expect(find.text('Desk'), findsOneWidget);
      expect(find.text('Shelf'), findsOneWidget);
      expect(find.text('Demo floor lamp'), findsOneWidget);
      await tester.tap(find.byTooltip('Set as default device').at(1));
      await tester.pumpAndSettle();
      expect(
        HomeLibrary.fromJson(jsonDecode(stored)).defaultLightId,
        'saved-b',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(KsLightApp(backend: backend));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shelf'), findsOneWidget);
      expect(
        find.text('Default light ready. No command sent.'),
        findsOneWidget,
      );
      expect(backend.sent, isEmpty);
      await tester.tap(find.text('Default device • tap to clear'));
      await tester.pumpAndSettle();
      expect(HomeLibrary.fromJson(jsonDecode(stored)).defaultLightId, isNull);
    },
  );
  testWidgets('failed save does not mark a device as default', (tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SettingsStore.channel, (call) async {
          if (call.method == 'loadLibrary') return jsonEncode(saved().toJson());
          if (call.method == 'saveLibrary') {
            throw StateError('disk unavailable');
          }
          return null;
        });
    await tester.pumpWidget(KsLightApp(backend: DemoBackend()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Set as default device'),
      findsWidgets,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    await tester.tap(find.byTooltip('Set as default device').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Clear default device'), findsNothing);
    expect(find.textContaining('Could not complete:'), findsOneWidget);
  });
}
