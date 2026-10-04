import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/hub_screen.dart';

import 'hub_test_fixtures.dart';

void main() {
  testWidgets(
    'hub groups and scenes show results and disable commands while busy',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final hub = FakeHub();
      await tester.pumpWidget(
        MaterialApp(home: HubScreen(clientFactory: (_, _) => hub)),
      );
      await tester.tap(find.text('Connect to hub'));
      await tester.pumpAndSettle();
      expect(find.text('HUB GROUPS'), findsOneWidget);
      expect(find.text('HUB SCENES'), findsOneWidget);
      expect(hub.calls, isEmpty);
      expect(find.text('Hub color balance: R100%  G30%  B75%'), findsOneWidget);
      hub.gate = Completer<void>();
      final press = tester
          .widget<OutlinedButton>(find.byKey(const Key('hub-group-room-off')))
          .onPressed!;
      press();
      press(); // Two callbacks before the disabled-button rebuild must still submit once.
      await tester.pump();
      expect(hub.calls, ['groups/room:{"power":false}']);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('hub-group-room-on')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('hub-scene-evening')))
            .onPressed,
        isNull,
      );
      hub.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Failed or uncertain'), findsOneWidget);
      expect(find.text('Simulated'), findsOneWidget);
      expect(find.textContaining('1 of 2 lights completed'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('hub-scene-evening')));
      await tester.tap(find.byKey(const Key('hub-scene-evening')));
      await tester.pumpAndSettle();
      expect(hub.calls.last, 'scenes/evening:{}');
      expect(hub.calls.length, 2);
      await tester.pumpWidget(const SizedBox());
      expect(hub.disconnected, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
