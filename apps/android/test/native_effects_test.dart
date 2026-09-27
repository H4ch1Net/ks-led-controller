import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/light_backend.dart';
import 'package:ks_light/native_effects.dart';
import 'package:ks_light/effects.dart';
import 'package:ks_light/protocol.dart';
import 'package:ks_light/native_preferences.dart';

class NativeTestBackend extends DemoBackend {
  int closes = 0;
  @override
  Future<LightSession> openSession(Light light) async => LightSession(
    write: (packets) => send(light, packets),
    disconnect: () async {
      closes++;
    },
  );
}

class MemoryNativeStore extends NativePreferencesStore {
  final values = <String, NativeLibrary>{};
  @override
  Future<NativeLibrary> load(String id) async => values[id] ?? NativeLibrary();
  @override
  Future<void> save(String id, NativeLibrary value) async {
    values[id] = NativeLibrary.fromJson(value.toJson());
  }
}

class FailingNativeStore extends NativePreferencesStore {
  @override
  Future<NativeLibrary> load(String id) async => NativeLibrary();
  @override
  Future<void> save(String id, NativeLibrary value) async =>
      throw StateError('disk full');
}

void main() {
  testWidgets(
    'animation and color compose the native command without preview writes',
    (tester) async {
      final backend = NativeTestBackend();
      await tester.binding.setSurfaceSize(const Size(500, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: NativeEffectsScreen(
            light: const Light('a', 'Desk', {'prefix': 'KS03~'}),
            backend: backend,
            store: MemoryNativeStore(),
            onChanged: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Green'));
      await tester.pumpAndSettle();
      expect(backend.sent, isEmpty);
      await tester.tap(find.text('Color fade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RGB'));
      await tester.pumpAndSettle();
      expect(backend.sent, isEmpty);
      await tester.tap(find.text('Breathing'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Green'))
            .selected,
        isTrue,
      );
      await tester.tap(find.text('Apply effect'));
      await tester.pumpAndSettle();
      expect(backend.sent.last, nativeEffectPacket(0x85, 35, 50));
    },
  );

  testWidgets(
    'named preset saves without transmitting and survives screen reopening',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final backend = NativeTestBackend();
      final store = MemoryNativeStore();
      Widget page() => MaterialApp(
        home: NativeEffectsScreen(
          light: const Light('a', 'Desk', {'prefix': 'KS03~'}),
          backend: backend,
          store: store,
          onChanged: () {},
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      tester.widgetList<Slider>(find.byType(Slider)).first.onChanged!(60);
      await tester.pump();
      await tester.ensureVisible(find.text('Save preset'));
      await tester.tap(find.text('Save preset'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Evening');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.values['a']!.presets['Evening']!.speed, 60);
      expect(backend.sent, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Evening'));
      await tester.tap(find.text('Evening'));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Speed: 60%'), 180);
      await tester.pumpAndSettle();
      expect(find.text('Speed: 60%'), findsOneWidget);
      expect(backend.sent, isEmpty);
      tester.widget<InputChip>(find.byType(InputChip)).onDeleted!();
      await tester.pumpAndSettle();
      expect(store.values['a']!.presets, isEmpty);
    },
  );
  testWidgets('save failure does not hide successful command or resend it', (
    tester,
  ) async {
    final backend = NativeTestBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: NativeEffectsScreen(
          light: const Light('a', 'Desk', {'prefix': 'KS03~'}),
          backend: backend,
          store: FailingNativeStore(),
          onChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply effect'));
    await tester.pumpAndSettle();
    expect(backend.sent.length, 2);
    expect(find.textContaining('settings could not be saved'), findsOneWidget);
    expect(find.textContaining('Connection failed'), findsNothing);
  });
  testWidgets(
    'background closes connection and returning does not send settings',
    (tester) async {
      final backend = NativeTestBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: NativeEffectsScreen(
            light: const Light('a', 'Desk', {'prefix': 'KS03~'}),
            backend: backend,
            store: MemoryNativeStore(),
            onChanged: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply effect'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(backend.closes, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('native-speed')),
        180,
      );
      await tester.pumpAndSettle();
      final slider = tester.widgetList<Slider>(find.byType(Slider)).first;
      slider.onChanged!(70);
      slider.onChangeEnd!(70);
      await tester.pumpAndSettle();
      expect(backend.sent.length, 2);
    },
  );
  testWidgets(
    'native effect sends once, off sends once and leaving closes connection',
    (tester) async {
      final backend = NativeTestBackend();
      var changed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NativeEffectsScreen(
            light: const Light('a', 'Desk', {'prefix': 'KS03~'}),
            backend: backend,
            store: MemoryNativeStore(),
            onChanged: () {
              changed++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Apply effect'));
      await tester.tap(find.text('Apply effect'));
      await tester.pumpAndSettle();
      expect(backend.sent, [
        [0x5b, 0xf0, 1, 0xb5],
        [0x5c, 0, 0x89, 35, 50, 0, 0xc5],
      ]);
      await tester.pump(const Duration(seconds: 10));
      expect(
        backend.sent.length,
        2,
        reason: 'No phone animation or polling loop',
      );
      await tester.ensureVisible(find.text('Turn off'));
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      expect(backend.sent.last, [0x5b, 0x0f, 1, 0xb5]);
      expect(changed, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(backend.closes, 1);
    },
  );
  testWidgets(
    'live slider sends once on release; saved choices reopen without writes',
    (tester) async {
      final store = MemoryNativeStore();
      final backend = NativeTestBackend();
      Widget page() => MaterialApp(
        home: NativeEffectsScreen(
          light: const Light('saved', 'Desk', {'prefix': 'KS03~'}),
          backend: backend,
          store: store,
          onChanged: () {},
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply effect'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('native-speed')),
        180,
      );
      await tester.pumpAndSettle();
      final slider = tester.widgetList<Slider>(find.byType(Slider)).first;
      slider.onChanged!(60);
      await tester.pump();
      expect(backend.sent.length, 2);
      slider.onChangeEnd!(60);
      await tester.pumpAndSettle();
      expect(backend.sent.length, 4);
      expect(backend.sent.last[3], 60);
      expect(store.values['saved']!.last.speed, 60);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Speed: 60%'), 180);
      await tester.pumpAndSettle();
      expect(find.text('Speed: 60%'), findsOneWidget);
      expect(
        backend.sent.length,
        4,
        reason: 'Restoring choices must not restart lights',
      );
    },
  );
  test(
    'native preferences validate fields, isolate IDs and roundtrip presets',
    () async {
      final store = MemoryNativeStore();
      await store.save(
        'a',
        NativeLibrary(
          last: const NativeChoice(speed: 70),
          presets: {'Evening': const NativeChoice(brightness: 25)},
        ),
      );
      expect((await store.load('a')).presets['Evening']!.brightness, 25);
      expect((await store.load('b')).presets, isEmpty);
      expect(
        () => NativeChoice.fromJson({
          'effect': 0x89,
          'speed': 101,
          'brightness': 50,
        }),
        throwsFormatException,
      );
      expect(
        () => NativeLibrary.fromJson({'version': 2, 'last': {}, 'presets': {}}),
        throwsFormatException,
      );
    },
  );
  test('KS03 brightness uses percent and breathing keeps RGB unchanged', () {
    expect(deviceBrightness(255, 'KS03~'), 100);
    expect(deviceBrightness(128, 'KS03~'), 50);
    expect(deviceBrightness(255, 'KS03-'), 255);
    final spec = EffectSpec(
      kind: EffectKind.breathing,
      palette: [
        [239, 66, 255],
      ],
    );
    final low = spec.frame(Duration.zero, 0, 1, separateBrightness: true);
    final high = spec.frame(
      const Duration(seconds: 15),
      0,
      1,
      separateBrightness: true,
    );
    expect(low.rgb, [239, 66, 255]);
    expect(high.rgb, low.rgb);
    expect(high.brightness, greaterThan(low.brightness));
  });
  test(
    'read characteristic fallback and repeated queries release listeners',
    () async {
      var reads = 0;
      final session = LightSession(
        notifications: () => const Stream.empty(),
        write: (_) async {},
        read: () async {
          reads++;
          return [0x5f, 2];
        },
        disconnect: () async {},
      );
      expect(await session.queryState(), [0x5f, 2]);
      expect(await session.queryState(), [0x5f, 2]);
      expect(reads, 2);
      await session.close();
    },
  );
  test('gradual native effect uses one bounded effect command', () {
    expect(nativeEffectPacket(0x89, 35, 50), [0x5c, 0, 0x89, 35, 50, 0, 0xc5]);
    expect(() => nativeEffectPacket(0x90, 35, 50), throwsArgumentError);
    expect(() => nativeEffectPacket(0x89, 35, 255), throwsArgumentError);
    expect(() => nativeEffectPacket(0x89, -1, 50), throwsArgumentError);
  });
  test('state parser distinguishes dynamic output, static color and off', () {
    final reply = [
      0x5f,
      2,
      1,
      1,
      255,
      0,
      255,
      0,
      50,
      35,
      0x89,
      0xf0,
      0x0f,
      0xf5,
    ];
    final state = ReportedLightState(reply);
    expect(state.dynamicMode, true);
    expect(state.power, true);
    expect(state.effect, 0x89);
    expect(state.brightness, 50);
    reply[2] = 0;
    expect(ReportedLightState(reply).dynamicMode, false);
    reply[11] = 0x0f;
    expect(ReportedLightState(reply).power, false);
    expect(state.dynamicMode, true, reason: 'snapshot must not mutate');
    expect(
      () => ReportedLightState(reply.sublist(0, 12)),
      throwsFormatException,
    );
    reply[13] = 0;
    expect(() => ReportedLightState(reply), throwsFormatException);
  });
  test(
    'state query listens before sending and ignores unrelated replies',
    () async {
      final stream = StreamController<List<int>>.broadcast();
      final reply = [0x5f, 2, 1];
      final session = LightSession(
        notifications: () => stream.stream,
        write: (packets) async {
          expect(stream.hasListener, true);
          expect(packets.single, [0x5f, 1, 0, 0xf5]);
          stream.add([0xff, 0, 1]);
          stream.add(reply);
        },
        disconnect: () async {},
      );
      expect(await session.queryState(), reply);
      expect(stream.hasListener, false);
      await session.close();
      await expectLater(session.queryState(), throwsStateError);
      await stream.close();
    },
  );
}
