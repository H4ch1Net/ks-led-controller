import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/color_picker.dart';

void main() {
  test('hex parsing accepts exact colors and rejects malformed input', () {
    expect(parseColorHex('#EF42ff'), [239, 66, 255]);
    expect(parseColorHex(' 8a2be2 '), [138, 43, 226]);
    for (final value in ['xyz123', '#abc', '1234567', '']) {
      expect(parseColorHex(value), isNull);
    }
    expect(colorHex([239, 66, 255]), '#EF42FF');
  });
  testWidgets('hex and quick choices update target; invalid text is reported', (
    tester,
  ) async {
    List<int> rgb = [255, 0, 0];
    bool valid = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => SingleChildScrollView(
              child: LightColorPicker(
                rgb: rgb,
                onChanged: (value) => update(() => rgb = value),
                onValidityChanged: (value) => valid = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fine adjustments'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('hex-color')), '#EF42FF');
    await tester.pumpAndSettle();
    expect(rgb, [239, 66, 255]);
    await tester.enterText(find.byKey(const ValueKey('hex-color')), '#oops');
    await tester.pumpAndSettle();
    expect(valid, false);
    expect(rgb, [239, 66, 255]);
    await tester.ensureVisible(find.byTooltip('Pink'));
    await tester.tap(find.byTooltip('Pink'));
    await tester.pumpAndSettle();
    expect(valid, true);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('hex-color')))
          .controller!
          .text,
      '#EF42FF',
    );
  });
  testWidgets('shade area selects white and black corners', (tester) async {
    List<int>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LightColorPicker(
              rgb: const [255, 0, 0],
              onChanged: (v) => selected = v,
            ),
          ),
        ),
      ),
    );
    final area = find.byKey(const ValueKey('shade-area'));
    await tester.tapAt(tester.getTopLeft(area) + const Offset(1, 1));
    expect(selected!.every((v) => v >= 252), true);
    await tester.tapAt(tester.getBottomLeft(area) + const Offset(1, -1));
    expect(selected!.every((v) => v <= 2), true);
  });
  testWidgets('shade drag wins over scrolling inside the picker', (
    tester,
  ) async {
    List<int>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              LightColorPicker(
                rgb: const [255, 0, 0],
                onChanged: (v) => selected = v,
              ),
              const SizedBox(height: 800),
            ],
          ),
        ),
      ),
    );
    final area = find.byKey(const ValueKey('shade-area'));
    final start = tester.getTopLeft(area) + const Offset(100, 10);
    await tester.dragFrom(start, const Offset(0, 140));
    await tester.pumpAndSettle();
    expect(selected![0], lessThan(60));
    expect(tester.getTopLeft(area).dy, greaterThanOrEqualTo(0));
  });
}
