import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/effects_screen.dart';
import 'package:ks_light/light_backend.dart';
import 'package:ks_light/settings.dart';

import 'effects_test.dart' show a;

void main() {
  test('restore snapshot excludes unknown power and unknown on-color', () {
    expect(
      effectSnapshots(
        [a],
        {
          'a': const LightSettings(lastColor: [1, 2, 3]),
        },
        {},
      ),
      isEmpty,
    );
    expect(effectSnapshots([a], {}, {'a': true}), isEmpty);
    expect(effectSnapshots([a], {}, {'a': false})['a']!.power, false);
  });
  testWidgets('backgrounding stops and returning does not restart effect', (
    tester,
  ) async {
    final backend = DemoBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: EffectsScreen(
          lights: [a],
          backend: backend,
          settings: {},
          previous: {},
          demo: true,
          onDelivered: (_, s) async {},
          onFailed: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Start effect'));
    await tester.pump();
    expect(find.text('Stop effect'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    final count = backend.sent.length;
    expect(find.text('Start effect'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 5));
    expect(backend.sent.length, count);
  });
}
