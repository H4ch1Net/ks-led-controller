import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/color_picker.dart';
import 'package:ks_light/hub_group_controls.dart';
import 'package:ks_light/hub_screen.dart';

import 'hub_test_fixtures.dart';

class ColorHub extends FakeHub {
  bool nativeCalled = false;
  @override
  Future<List<Map<String, dynamic>>> lights() async => [
    for (final id in ['desk', 'sofa'])
      {
        'id': id,
        'name': id,
        'capabilities': {
          'rgb': true,
          'brightness': true,
          'native_effects': true,
        },
      },
  ];
  @override
  Future<String> command(
    String id,
    Map<String, dynamic> body, {
    bool native = false,
    String targetKind = 'lights',
  }) {
    nativeCalled = native;
    return super.command(id, body, native: native, targetKind: targetKind);
  }
}

Future<void> openGroup(WidgetTester tester, ColorHub hub) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(home: HubScreen(clientFactory: (_, _) => hub)),
  );
  await tester.tap(find.text('Connect to hub'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('hub-group-room-controls')));
  await tester.tap(find.byKey(const Key('hub-group-room-controls')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'group preview cancels without sending and applies one color command',
    (tester) async {
      final hub = ColorHub();
      await openGroup(tester, hub);
      final sheet = find.byType(HubGroupControls);
      tester
          .widget<Slider>(find.byKey(const Key('hub-group-brightness')))
          .onChanged!(67);
      tester
          .widget<LightColorPicker>(
            find.descendant(of: sheet, matching: find.byType(LightColorPicker)),
          )
          .onChanged([10, 20, 30]);
      await tester.pump();
      expect(hub.calls, isEmpty);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(hub.calls, isEmpty);
      await tester.tap(find.byKey(const Key('hub-group-room-controls')));
      await tester.pumpAndSettle();
      tester
          .widget<Slider>(find.byKey(const Key('hub-group-brightness')))
          .onChanged!(67);
      tester
          .widget<LightColorPicker>(
            find.descendant(of: sheet, matching: find.byType(LightColorPicker)),
          )
          .onChanged([10, 20, 30]);
      await tester.pump();
      final apply = tester
          .widget<FilledButton>(find.byKey(const Key('hub-group-apply-color')))
          .onPressed!;
      apply();
      apply();
      await tester.pumpAndSettle();
      expect(hub.calls, [
        'groups/room:{"power":true,"rgb":[10,20,30],"brightness":67}',
      ]);
      expect(hub.nativeCalled, isFalse);
      expect(find.text('Failed or uncertain'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('group effect uses native endpoint and selected brightness', (
    tester,
  ) async {
    final hub = ColorHub();
    await openGroup(tester, hub);
    tester
        .widget<Slider>(find.byKey(const Key('hub-group-brightness')))
        .onChanged!(35);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('hub-group-apply-effect')));
    await tester.tap(find.byKey(const Key('hub-group-apply-effect')));
    await tester.pumpAndSettle();
    expect(hub.calls, [
      'groups/room:{"effect":137,"speed":35,"brightness":35}',
    ]);
    expect(hub.nativeCalled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mixed profiles show only shared capabilities and missing members show none',
    (tester) async {
      final catalog = [
        {
          'id': 'desk',
          'capabilities': {
            'rgb': true,
            'brightness': true,
            'native_effects': true,
          },
        },
        {
          'id': 'sofa',
          'capabilities': {'rgb': true},
        },
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HubGroupControls(group: groups.first, lights: catalog),
          ),
        ),
      );
      expect(find.byKey(const Key('hub-group-apply-color')), findsOneWidget);
      expect(find.byKey(const Key('hub-group-brightness')), findsNothing);
      expect(find.byKey(const Key('hub-group-apply-effect')), findsNothing);
      tester
          .widget<LightColorPicker>(find.byType(LightColorPicker))
          .onValidityChanged!(false);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('hub-group-apply-color')),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HubGroupControls(
              group: groups.first,
              lights: catalog.take(1).toList(),
            ),
          ),
        ),
      );
      expect(find.byType(LightColorPicker), findsNothing);
      expect(find.byKey(const Key('hub-group-apply-brightness')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
