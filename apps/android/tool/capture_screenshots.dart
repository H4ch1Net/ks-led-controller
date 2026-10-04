// Documentation captures of real Flutter widgets using synthetic, in-memory data.
// No Bluetooth, hub, phone settings, or user files are accessed.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/main.dart';
import 'package:ks_light/light_backend.dart';
import 'package:ks_light/settings.dart';
import 'package:ks_light/home_library.dart';
import 'package:ks_light/native_effects.dart';
import 'package:ks_light/app_style.dart';

void main() {
  testWidgets('capture documentation screens', (tester) async {
    const fontDir = String.fromEnvironment('KS_SCREENSHOT_FONT_DIR');
    const outputDir = String.fromEnvironment('KS_SCREENSHOT_DIR');
    if (fontDir.isEmpty || outputDir.isEmpty) {
      throw ArgumentError(
        'Provide KS_SCREENSHOT_FONT_DIR and KS_SCREENSHOT_DIR',
      );
    }
    await tester.runAsync(() async {
      // Match file names case-insensitively; load every Roboto weight so
      // semibold headings render as they do on Android.
      final files = Directory(fontDir).listSync().whereType<File>().toList();
      for (final (family, pattern) in [
        ('Roboto', RegExp(r'^roboto-(regular|medium|bold)\.ttf$')),
        ('MaterialIcons', RegExp(r'^materialicons-regular\.otf$')),
      ]) {
        final loader = FontLoader(family);
        for (final file in files.where(
          (f) => pattern.hasMatch(f.uri.pathSegments.last.toLowerCase()),
        )) {
          loader.addFont(
            file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        }
        await loader.load();
      }
    });
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = HomeLibrary(
      lights: {
        'demo': {'name': 'Demo floor lamp', 'prefix': 'KS03~'},
      },
      collections: {
        'Living room': const LightCollection('room', ['demo']),
      },
      scenes: {
        'Evening': {
          'demo': const SceneState(
            power: true,
            rgb: [239, 66, 255],
            brightness: 128,
          ),
        },
        'Reading': {
          'demo': const SceneState(
            power: true,
            rgb: [255, 180, 100],
            brightness: 210,
          ),
        },
      },
    );
    String libraryJson = jsonEncode(library.toJson());
    String preferencesJson = jsonEncode({
      'version': 1,
      'appearance': 'lime',
      'colors': {
        'Evening': {
          'rgb': [239, 66, 255],
          'brightness': 128,
        },
        'Ocean': {
          'rgb': [30, 160, 255],
          'brightness': 180,
        },
        'Reading': {
          'rgb': [255, 180, 100],
          'brightness': 210,
        },
      },
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SettingsStore.channel, (call) async {
          switch (call.method) {
            case 'load':
              return jsonEncode({
                'demo': const LightSettings(
                  lastColor: [239, 66, 255],
                  lastBrightness: 128,
                ).toJson(),
              });
            case 'loadLibrary':
              return libraryJson;
            case 'saveLibrary':
              libraryJson = (call.arguments as Map)['json'] as String;
              return null;
            case 'loadAppPreferences':
              return preferencesJson;
            case 'saveAppPreferences':
              preferencesJson = call.arguments as String;
              return null;
            default:
              return null;
          }
        });
    final captureKey = GlobalKey();
    // Flutter's test engine substitutes Ahem for unspecified platform fonts.
    // Restore Android's Roboto at render time, without changing app widgets.
    InlineSpan androidFont(InlineSpan span) {
      if (span is! TextSpan) return span;
      return TextSpan(
        text: span.text,
        style: (span.style ?? const TextStyle()).copyWith(
          fontFamily: span.style?.fontFamily == 'MaterialIcons'
              ? 'MaterialIcons'
              : 'Roboto',
        ),
        children: span.children?.map(androidFont).toList(),
      );
    }

    void restoreFonts(RenderObject node) {
      if (node is RenderParagraph) node.text = androidFont(node.text);
      node.visitChildren(restoreFonts);
    }

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      restoreFonts(boundary);
      await tester.pump();
      await tester.runAsync(() async {
        final frame = await boundary.toImage(pixelRatio: 2);
        final png = await frame.toByteData(format: ui.ImageByteFormat.png);
        await Directory(outputDir).create(recursive: true);
        await File('$outputDir/$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
        frame.dispose();
      });
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: KsLightApp(backend: DemoBackend()),
      ),
    );
    await tester.pumpAndSettle();
    await capture('lights');
    await tester.tap(find.text('Demo floor lamp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('On'));
    await tester.pumpAndSettle();
    await capture('controls');
    await tester.ensureVisible(find.text('SAVED COLORS'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -200),
    );
    await capture('colors');
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Violet'));
    await tester.pumpAndSettle();
    tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Violet'))
        .onSelected!(true);
    await tester.pumpAndSettle();
    await capture('appearance');
    Navigator.of(tester.element(find.text('APPEARANCE'))).pop();
    await tester.pumpAndSettle();
    // Open the actual library route, populated with synthetic rooms and scenes.
    await tester.tap(find.text('Scenes'));
    await capture('scenes');
    // Native controls are rendered against DemoBackend; no commands are needed.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: lightAppTheme(),
          home: NativeEffectsScreen(
            light: const Light('demo', 'Demo floor lamp', {'prefix': 'KS03~'}),
            backend: DemoBackend(),
            onChanged: () {},
          ),
        ),
      ),
    );
    await capture('effects');
  });
}
