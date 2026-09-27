import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/color_picker.dart';
import 'package:ks_light/home_library.dart';
import 'package:ks_light/light_backend.dart';
import 'package:ks_light/scene_color_editor.dart';

import 'home_library_test.dart' show ceiling;

void main() {
  testWidgets(
    'ceiling scene editor validates color and saves full brightness on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SceneState? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<SceneState>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SceneColorEditor(
                        light: Light('c', 'Ceiling', ceiling),
                        initial: SceneState(
                          power: false,
                          rgb: [4, 5, 6],
                          brightness: 90,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scene-color-brightness')), findsNothing);
      final picker = tester.widget<LightColorPicker>(
        find.byType(LightColorPicker),
      );
      picker.onValidityChanged!(false);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('scene-color-use')))
            .onPressed,
        isNull,
      );
      picker.onChanged([10, 20, 30]);
      picker.onValidityChanged!(true);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('scene-color-use')));
      await tester.tap(find.byKey(const Key('scene-color-use')));
      await tester.pumpAndSettle();
      expect(result!.power, isFalse);
      expect(result!.rgb, [10, 20, 30]);
      expect(result!.brightness, 255);
      expect(tester.takeException(), isNull);
    },
  );
}
