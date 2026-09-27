import 'dart:async';
import 'dart:math' as math;

import 'home_library.dart';
import 'light_backend.dart';
import 'settings.dart';

enum EffectKind { breathing, candle, sunset, rainbow, drift, wave }

const effectNames = {
  EffectKind.breathing: 'Breathing',
  EffectKind.candle: 'Candle',
  EffectKind.sunset: 'Sunset',
  EffectKind.rainbow: 'Rainbow',
  EffectKind.drift: 'Color drift',
  EffectKind.wave: 'Palette wave',
};
const effectPalettes = <String, List<List<int>>>{
  'Aurora': [
    [70, 255, 160],
    [40, 110, 255],
    [200, 40, 255],
  ],
  'Warm': [
    [255, 130, 30],
    [255, 40, 10],
    [255, 190, 80],
  ],
  'Ocean': [
    [0, 80, 255],
    [0, 220, 210],
    [50, 130, 255],
  ],
  'Pink & violet': [
    [239, 66, 255],
    [120, 30, 255],
    [255, 40, 110],
  ],
};

class EffectSpec {
  EffectSpec({
    required this.kind,
    required List<List<int>> palette,
    this.period = const Duration(seconds: 30),
    this.intensity = 0.7,
  }) : palette = [for (final rgb in palette) List<int>.unmodifiable(rgb)] {
    if (period < const Duration(seconds: 10) ||
        period > const Duration(minutes: 5) ||
        !intensity.isFinite ||
        intensity < 0.05 ||
        intensity > 1 ||
        palette.isEmpty ||
        palette.length > 8 ||
        palette.any(
          (rgb) => rgb.length != 3 || rgb.any((v) => v < 0 || v > 255),
        )) {
      throw ArgumentError('Invalid effect parameters');
    }
  }
  final EffectKind kind;
  final List<List<int>> palette;
  final Duration period;
  final double intensity;
  bool complete(Duration elapsed) =>
      kind == EffectKind.sunset && elapsed >= period;
  SceneState frame(
    Duration elapsed,
    int index,
    int count, {
    required bool separateBrightness,
  }) {
    if (kind == EffectKind.breathing && separateBrightness) {
      final phase = elapsed.inMicroseconds / period.inMicroseconds;
      final level = 0.15 + 0.85 * (1 - math.cos(2 * math.pi * phase)) / 2;
      return SceneState(
        power: true,
        rgb: List.of(palette.first),
        brightness: (255 * intensity * level).round().clamp(0, 255),
      );
    }
    return SceneState(power: true, rgb: sample(elapsed, index, count));
  }

  List<int> sample(Duration elapsed, int index, int count) {
    if (count < 1 || index < 0 || index >= count || elapsed.isNegative) {
      throw ArgumentError('Invalid sample');
    }
    final progress = elapsed.inMicroseconds / period.inMicroseconds;
    final phase = progress % 1;
    List<double> mix(List<int> a, List<int> b, double t) =>
        List.generate(3, (i) => a[i] + (b[i] - a[i]) * t);
    List<double> cycle(double position) {
      final scaled = (position % 1) * palette.length;
      final n = scaled.floor();
      final t = (1 - math.cos((scaled - n) * math.pi)) / 2;
      return mix(palette[n], palette[(n + 1) % palette.length], t);
    }

    late List<double> rgb;
    switch (kind) {
      case EffectKind.breathing:
        final level = 0.15 + 0.85 * (1 - math.cos(2 * math.pi * phase)) / 2;
        rgb = palette.first.map((v) => v * level).toList();
      case EffectKind.candle:
        final level =
            (0.75 +
                    0.15 * math.sin(phase * math.pi * 14) +
                    0.1 * math.sin(phase * math.pi * 22))
                .clamp(0.35, 1.0);
        rgb = [255 * level, 95 * level, 18 * level];
      case EffectKind.sunset:
        final t = progress.clamp(0.0, 1.0);
        rgb = t < 0.5
            ? mix([255, 160, 60], [220, 45, 8], t * 2)
            : mix([220, 45, 8], [20, 0, 0], (t - 0.5) * 2);
      case EffectKind.rainbow:
        final h = phase * 6;
        final x = 255 * (1 - ((h % 2) - 1).abs());
        rgb = switch (h.floor()) {
          0 => [255, x, 0],
          1 => [x, 255, 0],
          2 => [0, 255, x],
          3 => [0, x, 255],
          4 => [x, 0, 255],
          _ => [255, 0, x],
        };
      case EffectKind.drift:
        rgb = cycle(phase);
      case EffectKind.wave:
        rgb = cycle(phase + index / count);
    }
    return rgb.map((v) => (v * intensity).round().clamp(0, 255)).toList();
  }
}

class EffectRunner {
  EffectRunner({
    required this.backend,
    this.interval = const Duration(milliseconds: 150),
  }) {
    if (interval < const Duration(milliseconds: 150)) {
      throw ArgumentError('Minimum frame interval is 150 milliseconds');
    }
  }
  final LightBackend backend;
  final Duration interval;
  final Map<String, SceneState> lastStates = {};
  final Map<String, String> errors = {};
  final List<String> restoreSkipped = [];
  int writes = 0;
  bool running = false, _stop = false, _restore = false;
  Completer<void>? _wake;
  Future<void>? _task;
  Future<void> start({
    required List<Light> lights,
    required EffectSpec spec,
    required Map<String, LightSettings> settings,
    required Map<String, SceneState> previous,
    void Function()? onUpdate,
  }) {
    if (running) throw StateError('An effect is already running');
    if (lights.isEmpty ||
        lights.length > 32 ||
        lights.map((l) => l.id).toSet().length != lights.length ||
        lights.any(
          (l) => !['floor', 'ceiling'].contains(l.profile['color_type']),
        )) {
      throw ArgumentError('Effects need 1-32 unique RGB-capable lights');
    }

    // Immutable snapshot: later configuration changes cannot alter the restore target.
    final snapshot = {
      for (final e in previous.entries)
        e.key: SceneState.fromJson(e.value.toJson()),
    };
    final calibration = {
      for (final light in lights)
        light.id: LightSettings.fromJson(
          (settings[light.id] ?? const LightSettings()).toJson(),
        ),
    };
    running = true;
    _stop = false;
    _restore = false;
    writes = 0;
    lastStates.clear();
    errors.clear();
    restoreSkipped.clear();
    return _task = _run(List.of(lights), spec, calibration, snapshot, onUpdate);
  }

  Future<void> stop({bool restore = false}) {
    _stop = true;
    _restore = restore;
    if (!(_wake?.isCompleted ?? true)) _wake!.complete();
    return _task ?? Future<void>.value();
  }

  Future<void> _run(
    List<Light> lights,
    EffectSpec spec,
    Map<String, LightSettings> settings,
    Map<String, SceneState> snapshot,
    void Function()? onUpdate,
  ) async {
    final clock = Stopwatch()..start();
    final touched = <String>{};
    final sessions = <String, LightSession>{};
    final lastPackets = <String, String>{};
    // Bound simultaneous GATT connections. Larger groups retain sequential sends.
    final persistent = lights.length <= 4;
    try {
      while (!_stop) {
        final frameStart = clock.elapsed;
        var attempted = false;
        for (var index = 0; index < lights.length; index++) {
          if (_stop) break;
          final light = lights[index];
          if (errors.containsKey(light.id)) continue;
          attempted = true;
          final state = spec.frame(
            clock.elapsed,
            index,
            lights.length,
            separateBrightness: light.profile['prefix'] == 'KS03~',
          );
          touched.add(light.id);
          try {
            if (persistent && !sessions.containsKey(light.id)) {
              sessions[light.id] = await backend.openSession(light);
              if (_stop) break;
            }
            final packets = state.packets(light, settings[light.id]!);
            final colorKey = packets.last.join(',');
            if (lastPackets[light.id] == colorKey) continue;
            final changed = lastPackets.containsKey(light.id)
                ? packets.sublist(1)
                : packets;
            if (persistent) {
              await sessions[light.id]!.send(changed);
            } else {
              await backend.send(light, changed);
            }
            lastPackets[light.id] = colorKey;
            lastStates[light.id] = state;
            writes++;
          } catch (e) {
            errors[light.id] = e.toString();
            lastStates.remove(light.id);
            try {
              await sessions.remove(light.id)?.close();
            } catch (_) {}
          }
          onUpdate?.call();
        }
        if (_stop ||
            !attempted ||
            errors.length == lights.length ||
            spec.complete(frameStart)) {
          break;
        }
        // No frame queue. Recompute from monotonic elapsed time after each transaction.
        final delay = interval - (clock.elapsed - frameStart);
        if (delay > Duration.zero) {
          _wake = Completer<void>();
          final timer = Timer(delay, () {
            if (!(_wake?.isCompleted ?? true)) _wake!.complete();
          });
          await _wake!.future;
          timer.cancel();
          _wake = null;
        }
      }
      if (_restore) {
        for (final light in lights.where((l) => touched.contains(l.id))) {
          // Backgrounding may revoke restoration between targets.
          if (!_restore) break;
          final state = snapshot[light.id];
          if (state == null) {
            restoreSkipped.add(light.id);
            continue;
          }
          try {
            final packets = state.packets(light, settings[light.id]!);
            if (sessions.containsKey(light.id) &&
                !errors.containsKey(light.id)) {
              await sessions[light.id]!.send(packets);
            } else {
              await backend.send(light, packets);
            }
            lastStates[light.id] = state;
            errors.remove(light.id);
          } catch (e) {
            errors[light.id] = 'Restore failed: $e';
            lastStates.remove(light.id);
          }
        }
      }
    } finally {
      for (final entry in sessions.entries) {
        try {
          await entry.value.close();
        } catch (e) {
          errors[entry.key] = 'Disconnect failed: $e';
        }
      }
      clock.stop();
      running = false;
      onUpdate?.call();
    }
  }
}
