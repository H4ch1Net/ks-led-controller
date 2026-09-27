import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/effects.dart';
import 'package:ks_light/home_library.dart';
import 'package:ks_light/light_backend.dart';
import 'package:ks_light/settings.dart';

const profile = {
  'prefix': 'KS03~',
  'service': 'AFD0',
  'write': 'AFD1',
  'color_type': 'floor',
};
const a = Light('a', 'Desk', profile), b = Light('b', 'Sofa', profile);
EffectSpec spec([EffectKind kind = EffectKind.breathing]) =>
    EffectSpec(kind: kind, palette: effectPalettes['Aurora']!);

class GateBackend extends DemoBackend {
  final calls = <String>[];
  final data = <List<List<int>>>[];
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> send(Light light, List<List<int>> packets) async {
    calls.add(light.id);
    data.add(packets);
    if (calls.length == 1) {
      entered.complete();
      await release.future;
    }
  }
}

class BrokenBackend extends DemoBackend {
  final calls = <String>[];
  @override
  Future<void> send(Light light, List<List<int>> packets) async {
    calls.add(light.id);
    if (light.id == 'a') throw StateError('offline');
    await super.send(light, packets);
  }
}

class SessionBackend extends DemoBackend {
  int opens = 0, closes = 0;
  final batches = <List<List<int>>>[];
  @override
  Future<LightSession> openSession(Light light) async {
    opens++;
    return LightSession(
      write: (packets) async {
        batches.add(packets);
      },
      disconnect: () async {
        closes++;
      },
    );
  }
}

void main() {
  test('frames reuse connection, power on once, restore then close', () async {
    final backend = SessionBackend();
    final runner = EffectRunner(backend: backend);
    await runner.start(
      lights: [a],
      spec: spec(EffectKind.rainbow),
      settings: {},
      previous: {'a': const SceneState(power: false)},
      onUpdate: () {
        if (runner.writes == 3) runner.stop(restore: true);
      },
    );
    expect(backend.opens, 1);
    expect(backend.closes, 1);
    expect(backend.batches.map((b) => b.length), [2, 1, 1, 1]);
    expect(backend.batches.last.single, [0x5b, 0x0f, 1, 0xb5]);
  });
  test('session rejects overlapping writes and closes once', () async {
    final gate = Completer<void>();
    var closes = 0;
    final session = LightSession(
      write: (_) => gate.future,
      disconnect: () async {
        closes++;
      },
    );
    final active = session.send([
      [1],
    ]);
    await expectLater(
      session.send([
        [2],
      ]),
      throwsStateError,
    );
    gate.complete();
    await active;
    await session.close();
    await session.close();
    expect(closes, 1);
    await expectLater(
      session.send([
        [3],
      ]),
      throwsStateError,
    );
  });
  test('all effects stay in RGB bounds and vary over time', () {
    for (final kind in EffectKind.values) {
      final effect = spec(kind);
      final frames = [
        for (var t = 0; t <= 30; t += 2)
          effect.sample(Duration(seconds: t), 0, 2),
      ];
      expect(
        frames.expand((rgb) => rgb).every((v) => v >= 0 && v <= 255),
        true,
      );
      expect(
        frames.map((rgb) => rgb.join(',')).toSet().length,
        greaterThan(1),
        reason: kind.name,
      );
    }
  });
  test('wave uses ordered targets, sunset holds its final frame', () {
    expect(
      spec(EffectKind.wave).sample(Duration.zero, 0, 3),
      isNot(spec(EffectKind.wave).sample(Duration.zero, 1, 3)),
    );
    final sunset = spec(EffectKind.sunset);
    expect(sunset.complete(const Duration(seconds: 30)), true);
    expect(
      sunset.sample(const Duration(seconds: 30), 0, 1),
      sunset.sample(const Duration(seconds: 90), 0, 1),
    );
  });
  test('invalid speed and intensity are rejected', () {
    expect(
      () => EffectSpec(
        kind: EffectKind.candle,
        palette: [
          [255, 0, 0],
        ],
        intensity: double.nan,
      ),
      throwsArgumentError,
    );
    expect(
      () => EffectSpec(
        kind: EffectKind.candle,
        palette: [
          [255, 0, 0],
        ],
        period: const Duration(seconds: 1),
      ),
      throwsArgumentError,
    );
    expect(
      () => EffectRunner(
        backend: DemoBackend(),
        interval: const Duration(milliseconds: 10),
      ),
      throwsArgumentError,
    );
  });
  test(
    'stop drains active transaction, skips pending light and restores last',
    () async {
      final backend = GateBackend();
      final runner = EffectRunner(backend: backend);
      final task = runner.start(
        lights: [a, b],
        spec: spec(),
        settings: {},
        previous: {'a': const SceneState(power: false)},
      );
      await backend.entered.future;
      expect(
        () =>
            runner.start(lights: [a], spec: spec(), settings: {}, previous: {}),
        throwsStateError,
      );
      final stopping = runner.stop(restore: true);
      expect(backend.calls, ['a']);
      backend.release.complete();
      await stopping;
      await task;
      expect(backend.calls, ['a', 'a']);
      expect(backend.data.last, [
        [0x5b, 0x0f, 1, 0xb5],
      ]);
      expect(runner.lastStates['a']!.power, false);
      expect(runner.running, false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(backend.calls.length, 2);
    },
  );
  test('unknown prior state is skipped instead of guessed', () async {
    final backend = GateBackend();
    final runner = EffectRunner(backend: backend);
    final task = runner.start(
      lights: [a],
      spec: spec(),
      settings: {},
      previous: {},
    );
    await backend.entered.future;
    runner.stop(restore: true);
    backend.release.complete();
    await task;
    expect(backend.calls, ['a']);
    expect(runner.restoreSkipped, ['a']);
  });
  test('offline member does not stop healthy light', () async {
    final backend = BrokenBackend();
    final runner = EffectRunner(backend: backend);
    await runner.start(
      lights: [a, b],
      spec: spec(),
      settings: {
        'b': const LightSettings(gains: [0.5, 1, 1]),
      },
      previous: {},
      onUpdate: () {
        if (runner.writes == 1) runner.stop();
      },
    );
    expect(backend.calls, ['a', 'b']);
    expect(runner.errors.keys, ['a']);
    expect(runner.lastStates.containsKey('b'), true);
    final original = runner.lastStates['b']!.rgb!;
    expect(backend.sent.last[3], (original[0] * 0.5).round());
  });
  test('stop wakes sleeping scheduler immediately', () async {
    final backend = DemoBackend();
    final runner = EffectRunner(backend: backend);
    final first = Completer<void>();
    final task = runner.start(
      lights: [a],
      spec: spec(),
      settings: {},
      previous: {},
      onUpdate: () {
        if (!first.isCompleted) first.complete();
      },
    );
    await first.future;
    await runner.stop().timeout(const Duration(seconds: 1));
    await task;
    expect(runner.writes, 1);
  });
  test('background stop overrides queued restoration', () async {
    final backend = GateBackend();
    final runner = EffectRunner(backend: backend);
    final task = runner.start(
      lights: [a],
      spec: spec(),
      settings: {},
      previous: {'a': const SceneState(power: false)},
    );
    await backend.entered.future;
    runner.stop(restore: true);
    runner.stop();
    backend.release.complete();
    await task;
    expect(backend.calls, ['a']);
  });
}
