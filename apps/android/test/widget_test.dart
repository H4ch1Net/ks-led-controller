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
    expect(find.text('Demo mode'), findsOneWidget);
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
    await tester.tap(find.byTooltip('Light settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Desk lamp');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Desk lamp'), findsOneWidget);
    expect(saved, contains('Desk lamp'));
    await tester.tap(find.byTooltip('Light settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Color balance'));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byKey(const ValueKey('balance-0'))).onChanged!(
      0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byTooltip('Pink')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pink'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply-color')));
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
    expect(find.text('Preview'), findsOneWidget);
  });
  testWidgets(
    'compact screen with large text keeps navigation and preview safe',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final backend = DemoBackend();
      await tester.pumpWidget(KsLightApp(backend: backend));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Scan for lights'));
      await tester.tap(find.text('Scan for lights'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Demo floor lamp'));
      await tester.tap(find.text('Demo floor lamp'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('apply-color')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Brightness'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Pink'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Pink'));
      await tester.pumpAndSettle();
      expect(backend.sent, isEmpty, reason: 'Preview must not send a command');
      await tester.tap(find.byTooltip('Light settings'));
      await tester.pumpAndSettle();
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Color balance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('fresh launch opens the real catalog without scanning', (
    tester,
  ) async {
    await tester.pumpWidget(const KsLightApp());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bluetooth'), findsOneWidget);
    expect(find.text('Demo mode'), findsNothing);
    expect(find.text('Scan for lights'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
