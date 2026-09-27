import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/main.dart';
import 'package:ks_light/light_backend.dart';
import 'package:ks_light/settings.dart';

class FailingBackend extends DemoBackend {
  @override
  Future<void> send(Light light, List<List<int>> packets) async {
    throw StateError('offline');
  }
}

void main() {
  setUp(() {
    rootBundle.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SettingsStore.channel, (call) async => null);
  });
  testWidgets('demo scan selection and power do not use Bluetooth', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = DemoBackend();
    await tester.pumpWidget(KsLightApp(backend: backend));
    expect(find.text('Demo mode'), findsOneWidget);
    await tester.tap(find.text('Scan for lights'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Demo floor lamp'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    await tester.tap(find.text('Demo floor lamp'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('On'));
    await tester.pumpAndSettle();
    expect(backend.sent.single, [0x5b, 0xf0, 1, 0xb5]);
    expect(find.text('Last sent: On'), findsOneWidget);
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(find.text('Last sent: Off'), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .selected,
      {false},
    );
    expect(
      find.text('Demo command applied. No Bluetooth writes.'),
      findsOneWidget,
    );
  });
  testWidgets('failure is visible and controls recover', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(KsLightApp(backend: FailingBackend()));
    await tester.tap(find.text('Scan for lights'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Demo floor lamp'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    await tester.tap(find.text('Demo floor lamp'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('On'));
    await tester.pumpAndSettle();
    expect(find.textContaining('offline'), findsOneWidget);
    expect(find.text('Power: unknown'), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .onSelectionChanged,
      isNotNull,
    );
  });
  testWidgets('rename persists and calibrated color reaches the backend', (
    tester,
  ) async {
    String? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SettingsStore.channel, (call) async {
          if (call.method == 'save') {
            saved = call.arguments as String;
            return null;
          }
          return saved;
        });
    final backend = DemoBackend();
    await tester.pumpWidget(KsLightApp(backend: backend));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for lights'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo floor lamp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Desk lamp');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Desk lamp'), findsOneWidget);
    expect(saved, contains('Desk lamp'));
    await tester.tap(find.text('Color balance'));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byKey(const ValueKey('balance-0'))).onChanged!(
      0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Pink')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pink'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply color & turn on'));
    await tester.pumpAndSettle();
    expect(backend.sent.last, [0x5a, 0, 1, 120, 66, 255, 0, 100, 0, 0xa5]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(KsLightApp(backend: backend));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for lights'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Desk lamp'), findsOneWidget);
    await tester.tap(find.text('Desk lamp'));
    await tester.pumpAndSettle();
    expect(find.text('Power: unknown'), findsOneWidget);
    expect(saved, contains('lastColor'));
    expect(
      find.textContaining(RegExp(r'^#EF42FF .*Not applied$')),
      findsOneWidget,
    );
  });
}
