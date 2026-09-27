import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/library_screen.dart';
import 'package:ks_light/light_backend.dart';
import 'package:ks_light/settings.dart';

import 'home_library_test.dart' show floor, RecordingBackend;

void main() {
  setUp(() => rootBundle.clear());
  testWidgets('room creation persists and group reports an offline member', (
    tester,
  ) async {
    String? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SettingsStore.channel, (call) async {
          if (call.method == 'loadLibrary') return saved;
          if (call.method == 'saveLibrary') {
            saved = (call.arguments as Map)['json'] as String;
          }
          return null;
        });
    final backend = RecordingBackend({'b'});
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          demo: true,
          discovered: const [
            Light('a', 'Desk', floor),
            Light('b', 'Sofa', floor),
          ],
          backend: backend,
          settings: {},
          onDelivered: (_, s) async {},
          onFailed: (_) {},
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New room / group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Living room');
    await tester.tap(find.text('Desk'));
    await tester.tap(find.text('Sofa'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Living room'), findsOneWidget);
    expect(saved, contains('Living room'));
    await tester.tap(find.text('All on'));
    await tester.pumpAndSettle();
    expect(
      find.text('1/2 commands delivered. Physical state is unconfirmed.'),
      findsOneWidget,
    );
    expect(find.textContaining('offline'), findsOneWidget);
    expect(backend.calls, ['a', 'b']);
  });
  testWidgets('scene captures distinct saved colors and survives reopen', (
    tester,
  ) async {
    String? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SettingsStore.channel, (call) async {
          if (call.method == 'loadLibrary') return saved;
          if (call.method == 'saveLibrary') {
            saved = (call.arguments as Map)['json'] as String;
          }
          return null;
        });
    final backend = RecordingBackend();
    Widget screen() => MaterialApp(
      home: LibraryScreen(
        demo: true,
        discovered: const [
          Light('a', 'Desk', floor),
          Light('b', 'Sofa', floor),
        ],
        backend: backend,
        settings: const {
          'a': LightSettings(lastColor: [255, 0, 0], lastBrightness: 100),
          'b': LightSettings(lastColor: [0, 0, 255], lastBrightness: 200),
        },
        onDelivered: (_, s) async {},
        onFailed: (_) {},
      ),
    );
    await tester.pumpWidget(screen());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save scene'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Evening');
    await tester.tap(find.text('Desk'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sofa'));
    await tester.tap(find.text('Sofa'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Evening'), findsOneWidget);
    await tester.ensureVisible(find.text('Activate'));
    await tester.tap(find.text('Activate'));
    await tester.pumpAndSettle();
    expect(backend.packets['a']!.last, [
      0x5a,
      0,
      1,
      255,
      0,
      0,
      0,
      39,
      0,
      0xa5,
    ]);
    expect(backend.packets['b']!.last, [
      0x5a,
      0,
      1,
      0,
      0,
      255,
      0,
      78,
      0,
      0xa5,
    ]);
  });
}
