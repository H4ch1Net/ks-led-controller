import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/hub_screen.dart';
import 'package:ks_light/settings.dart';

import 'hub_test_fixtures.dart';

void main() {
  testWidgets(
    'saved pairing requires explicit connect and can be forgotten without light commands',
    (tester) async {
      Map<String, String>? saved = {
        'address': 'https://hub.example',
        'token': testToken,
      };
      var connections = 0;
      final hub = FakeHub();
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SettingsStore.channel, (call) async {
        if (call.method == 'loadHubPairing') return saved;
        if (call.method == 'saveHubPairing') {
          saved = Map<String, String>.from(call.arguments as Map);
        }
        if (call.method == 'forgetHubPairing') saved = null;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SettingsStore.channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HubScreen(
            clientFactory: (address, token) {
              expect(address, 'https://hub.example');
              expect(token, testToken);
              connections++;
              return hub;
            },
          ),
        ),
      );
      await tester.tap(find.text('Load saved hub'));
      await tester.pumpAndSettle();
      expect(connections, 0);
      await tester.tap(find.text('Connect to hub'));
      await tester.pumpAndSettle();
      expect(connections, 1);
      expect(saved!['token'], testToken);
      expect(hub.calls, isEmpty);
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forget saved hub'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(hub.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
