import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/diagnostics_screen.dart';

void main() {
  testWidgets(
    'help is read-only, shows recovery advice, and copies only allowed fields',
    (tester) async {
      final calls = <String>[];
      String? copied;
      const channel = MethodChannel('dev.kslight/settings');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return {
          'androidApi': 36,
          'bluetoothSupported': true,
          'bluetoothEnabled': false,
          'connectPermission': true,
          'scanPermission': false,
          'bluetoothBusy': false,
          'widgets': 2,
          'quickControlsConfigured': true,
          'hubToken': 'private-secret',
          'address': 'private-address',
        };
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      await tester.pumpWidget(
        const MaterialApp(home: DiagnosticsScreen(demo: false, savedLights: 3)),
      );
      await tester.pumpAndSettle();
      expect(calls, ['diagnostics']);
      await tester.scrollUntilVisible(
        find.text('Turn on Bluetooth in Android Quick Settings, then refresh.'),
        300,
      );
      expect(find.textContaining('Allow Nearby devices'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Copy diagnostics'), 300);
      await tester.tap(find.text('Copy diagnostics'));
      await tester.pumpAndSettle();
      expect(copied, contains('Bluetooth: Off'));
      expect(copied, contains('Saved lights: 3'));
      expect(copied, isNot(contains('private')));
      expect(calls, ['diagnostics']);
    },
  );
}
