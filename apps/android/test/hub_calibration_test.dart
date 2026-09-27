import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/hub_client.dart';
import 'package:ks_light/hub_calibration_screen.dart';

class CalibrationHub extends HubClient {
  CalibrationHub() : super('http://127.0.0.1', 'x' * 32);
  final tag = '"${'a' * 64}"';
  int writes = 0;
  Map<String, dynamic>? saved;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? key,
    String? ifMatch,
    void Function(String?)? onRevision,
  }) async {
    if (method == 'PUT') {
      writes++;
      expect(ifMatch, tag);
      saved = body;
    }
    onRevision?.call(tag);
    return {
      'calibration': {
        'rgb_gains': [1, 1, 1],
        'presets': {},
      },
      'built_in_presets': {
        'Less blue': [1, 1, .75],
      },
    };
  }
}

void main() {
  testWidgets(
    'preset selection stays a preview until explicit versioned save',
    (tester) async {
      final hub = CalibrationHub();
      await tester.pumpWidget(
        MaterialApp(
          home: HubCalibrationScreen(client: hub, id: 'desk', name: 'Desk'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Less blue'));
      await tester.pump();
      expect(hub.writes, 0);
      await tester.ensureVisible(find.text('Save to hub'));
      await tester.tap(find.text('Save to hub'));
      await tester.pumpAndSettle();
      expect(hub.writes, 1);
      expect(hub.saved!['rgb_gains'], [1, 1, .75]);
    },
  );
  test('calibration import validates shape and preset limits', () {
    expect(
      parseHubCalibration(
        '{"rgb_gains":[1,0.3,0.75],"presets":{"Purple":[1,0.3,0.75]}}',
      )['presets'],
      {
        'Purple': [1, .3, .75],
      },
    );
    for (final text in [
      '{}',
      '{"rgb_gains":[true,1,1]}',
      '{"rgb_gains":[1,1,1],"order":"BGR"}',
      'x' * 16385,
    ]) {
      expect(() => parseHubCalibration(text), throwsFormatException);
    }
  });
}
