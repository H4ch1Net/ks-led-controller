import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/home_library.dart';
import 'package:ks_light/library_screen.dart';
import 'package:ks_light/library_transfer.dart';
import 'package:ks_light/settings.dart';
import 'package:ks_light/color_picker.dart';

import 'home_library_test.dart' show example, RecordingBackend;

void main() {
  late HomeLibrary saved;
  late RecordingBackend backend;
  var failSave = false;
  String? fileText, exported;
  setUp(() {
    rootBundle.clear();
    saved = example()..defaultLightId = 'a';
    saved.collections['Evening'] = const LightCollection('room', ['a', 'b']);
    saved.scenes['Evening'] = {
      'a': const SceneState(power: true, rgb: [255, 0, 0], brightness: 90),
    };
    backend = RecordingBackend();
    failSave = false;
    fileText = null;
    exported = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SettingsStore.channel, (call) async {
          if (call.method == 'loadLibrary') return jsonEncode(saved.toJson());
          if (call.method == 'importLibraryFile') return fileText;
          if (call.method == 'exportLibraryFile') {
            exported = call.arguments as String;
            return true;
          }
          if (call.method == 'saveLibrary') {
            if (failSave) throw PlatformException(code: 'storage_error');
            saved = HomeLibrary.fromJson(
              jsonDecode((call.arguments as Map)['json'] as String),
            );
          }
          return null;
        });
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          demo: true,
          discovered: const [],
          backend: backend,
          settings: const {
            'a': LightSettings(lastColor: [0, 255, 0], lastBrightness: 180),
          },
          onDelivered: (_, _) async {},
          onFailed: (_) {},
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(
        key.startsWith('edit-scene') ? 'Edit scene' : 'Edit collection',
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'file export and import keep review and cancellation boundaries',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Library backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export backup file'));
      await tester.pumpAndSettle();
      expect(jsonDecode(exported!)['format'], 'ks-light-rooms-scenes');
      await tester.tap(find.byTooltip('Library backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open backup file'));
      await tester.pumpAndSettle();
      expect(find.text('Review'), findsNothing);
      fileText = exported;
      await tester.tap(find.byTooltip('Library backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open backup file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(saved.scenes.length, 1);
      expect(find.text('Review import'), findsOneWidget);
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(saved.scenes.length, 2);
      expect(saved.defaultLightId, 'a');
      expect(backend.calls, isEmpty);
    },
  );

  testWidgets(
    'custom scene colors stay detached until saved and survive recapture',
    (tester) async {
      await open(tester);
      await edit(tester, 'edit-scene-Evening');
      await tester.tap(find.byKey(const Key('scene-color-a')));
      await tester.pumpAndSettle();
      tester.widget<LightColorPicker>(find.byType(LightColorPicker)).onChanged([
        12,
        34,
        56,
      ]);
      tester
          .widget<Slider>(find.byKey(const Key('scene-color-brightness')))
          .onChanged!(128);
      await tester.pump();
      await tester.tap(find.byKey(const Key('scene-color-use')));
      await tester.pumpAndSettle();
      expect(saved.scenes['Evening']!['a']!.rgb, [255, 0, 0]);
      expect(backend.calls, isEmpty);
      await tester.tap(find.text('Use latest applied colors'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved.scenes['Evening']!['a']!.rgb, [12, 34, 56]);
      expect(saved.scenes['Evening']!['a']!.brightness, 128);
      expect(saved.defaultLightId, 'a');
      expect(backend.calls, isEmpty);
      await edit(tester, 'edit-scene-Evening');
      await tester.tap(find.byKey(const Key('scene-color-a')));
      await tester.pumpAndSettle();
      tester.widget<LightColorPicker>(find.byType(LightColorPicker)).onChanged([
        1,
        2,
        3,
      ]);
      await tester.tap(find.byKey(const Key('scene-color-use')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved.scenes['Evening']!['a']!.rgb, [12, 34, 56]);
      expect(backend.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'edit collection renames and changes members without touching same-named scene',
    (tester) async {
      await open(tester);
      await edit(tester, 'edit-collection-Evening');
      await tester.enterText(find.byType(TextFormField), 'Lounge');
      await tester.tap(find.text('Sofa'));
      await tester.tap(find.text('Ceiling'));
      await tester.tap(find.text('Room'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Group').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved.collections.keys, ['Lounge']);
      expect(saved.collections['Lounge']!.kind, 'group');
      expect(saved.collections['Lounge']!.members, ['a', 'c']);
      expect(saved.scenes['Evening']!['a']!.rgb, [255, 0, 0]);
      expect(saved.defaultLightId, 'a');
      expect(backend.calls, isEmpty);
      await edit(tester, 'edit-collection-Lounge');
      await tester.enterText(find.byType(TextFormField), 'Discarded');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved.collections.keys, ['Lounge']);
    },
  );

  testWidgets(
    'scene rename preserves snapshot and explicit recapture updates it',
    (tester) async {
      await open(tester);
      await edit(tester, 'edit-scene-Evening');
      await tester.enterText(find.byType(TextFormField), 'Reading');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved.scenes.keys, ['Reading']);
      expect(saved.scenes['Reading']!.keys, ['a']);
      expect(saved.scenes['Reading']!['a']!.rgb, [255, 0, 0]);
      expect(saved.scenes['Reading']!['a']!.brightness, 90);
      expect(saved.collections.keys, ['Evening']);
      await edit(tester, 'edit-scene-Reading');
      await tester.tap(find.text('Use latest applied colors'));
      await tester.tap(find.text('Sofa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved.scenes['Reading']!['a']!.rgb, [0, 255, 0]);
      expect(saved.scenes['Reading']!['a']!.brightness, 180);
      expect(saved.scenes['Reading']!['b']!.power, isTrue);
      expect(saved.scenes['Reading']!['b']!.rgb, isNull);
      expect(backend.calls, isEmpty);
    },
  );

  testWidgets(
    'editing cannot replace another name or save an empty membership',
    (tester) async {
      saved.collections['Other'] = const LightCollection('group', ['c']);
      await open(tester);
      await edit(tester, 'edit-collection-Evening');
      await tester.enterText(find.byType(TextFormField), 'oThEr');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('That name already exists'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Evening');
      await tester.tap(find.text('Desk'));
      await tester.tap(find.text('Sofa'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Choose 1-32 lights'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved.collections['Evening']!.members, ['a', 'b']);
      expect(saved.collections['Other']!.members, ['c']);
      expect(backend.calls, isEmpty);
    },
  );

  testWidgets('backup copy and import require review and keep originals', (
    tester,
  ) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await open(tester);
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    final original = jsonEncode(saved.toJson());
    await tester.tap(find.byTooltip('Library backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy rooms & scenes'));
    await tester.pumpAndSettle();
    expect(copied, isNotNull);
    expect(jsonEncode(saved.toJson()), original);
    Future<void> preview() async {
      await tester.tap(find.byTooltip('Library backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import rooms & scenes'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('library-import-text')),
        copied!,
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('Review import'), findsOneWidget);
      expect(find.text('Scene: Evening (2)'), findsOneWidget);
    }

    await preview();
    expect(jsonEncode(saved.toJson()), original);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(jsonEncode(saved.toJson()), original);
    await preview();
    failSave = true;
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(jsonEncode(saved.toJson()), original);
    expect(find.textContaining('Could not save'), findsOneWidget);
    failSave = false;
    await preview();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(saved.collections.keys, ['Evening', 'Evening (2)']);
    expect(saved.scenes.keys, ['Evening', 'Evening (2)']);
    expect(saved.defaultLightId, 'a');
    expect(backend.calls, isEmpty);
  });

  testWidgets(
    'invalid backup remains in the import dialog without changing data',
    (tester) async {
      await open(tester);
      final original = jsonEncode(saved.toJson());
      await tester.tap(find.byTooltip('Library backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import rooms & scenes'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('library-import-text')),
        LibraryTransfer.encode(saved, false),
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.textContaining('cannot be mixed'), findsOneWidget);
      expect(find.text('Review import'), findsNothing);
      expect(jsonEncode(saved.toJson()), original);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.calls, isEmpty);
    },
  );

  testWidgets('failed edit keeps original library and its visible name', (
    tester,
  ) async {
    await open(tester);
    failSave = true;
    await edit(tester, 'edit-scene-Evening');
    await tester.enterText(find.byType(TextFormField), 'Unsaved');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved.scenes.keys, ['Evening']);
    expect(find.byKey(const Key('edit-scene-Evening')), findsOneWidget);
    expect(find.byKey(const Key('edit-scene-Unsaved')), findsNothing);
    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(backend.calls, isEmpty);
  });
}
