import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/calibration_dialog.dart';
import 'package:ks_light/settings.dart';

void main() {
  testWidgets('named profile snapshots gains; cancel preserves original', (
    tester,
  ) async {
    const original = LightSettings(gains: [1, 0.3, 0.75]);
    LightSettings? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<LightSettings>(
                  context: context,
                  builder: (_) => const CalibrationDialog(settings: original),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'Evening');
    await tester.ensureVisible(find.text('Add preset'));
    await tester.tap(find.text('Add preset'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reset balance'));
    await tester.tap(find.text('Reset balance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result!.gains, [1, 1, 1]);
    expect(result!.presets['Evening'], [1, 0.3, 0.75]);
    expect(original.presets, isEmpty);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(original.gains, [1, 0.3, 0.75]);
  });
  testWidgets('built-in preset changes draft without sending commands', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CalibrationDialog(settings: LightSettings())),
    );
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purple trial').last);
    await tester.pumpAndSettle();
    expect(find.text('Green balance: 30%'), findsOneWidget);
    expect(find.text('Blue balance: 75%'), findsOneWidget);
  });
}
