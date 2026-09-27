import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/home_library.dart';
import 'package:ks_light/light_backend.dart';
import 'package:ks_light/settings.dart';

const floor = {
  'prefix': 'KS03~',
  'service': 'AFD0',
  'write': 'AFD1',
  'color_type': 'floor',
};
const ceiling = {
  'prefix': 'KS03-',
  'service': 'FFF0',
  'write': 'FFF3',
  'color_type': 'ceiling',
};

class RecordingBackend extends DemoBackend {
  final calls = <String>[];
  final packets = <String, List<List<int>>>{};
  final Set<String> offline;
  int active = 0, peak = 0;
  RecordingBackend([this.offline = const {}]);
  @override
  Future<void> send(Light light, List<List<int>> data) async {
    active++;
    if (active > peak) peak = active;
    try {
      calls.add(light.id);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (offline.contains(light.id)) throw StateError('offline');
      packets[light.id] = data;
    } finally {
      active--;
    }
  }
}

HomeLibrary example() => HomeLibrary()
  ..remember(const [
    Light('a', 'Desk', floor),
    Light('b', 'Sofa', floor),
    Light('c', 'Ceiling', ceiling),
  ]);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('room and per-light scene persist with isolated demo storage', () async {
    final saved = <bool, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SettingsStore.channel, (call) async {
          if (call.method == 'loadLibrary') {
            return saved[call.arguments as bool];
          }
          final args = call.arguments as Map;
          saved[args['demo'] as bool] = args['json'] as String;
          return null;
        });
    final library = example();
    library.collections['Living room'] = const LightCollection('room', [
      'a',
      'b',
    ]);
    library.scenes['Evening'] = {
      'a': const SceneState(power: true, rgb: [239, 66, 255], brightness: 100),
      'b': const SceneState(power: false),
    };
    await HomeLibraryStore().save(false, library);
    final loaded = await HomeLibraryStore().load(false);
    expect(loaded.collections['Living room']!.members, ['a', 'b']);
    expect(loaded.scenes['Evening']!['a']!.rgb, [239, 66, 255]);
    expect(loaded.scenes['Evening']!['b']!.power, false);
    expect((await HomeLibraryStore().load(true)).lights, isEmpty);
    expect(jsonDecode(saved[false]!)['version'], 1);
  });
  test('offline target does not block others; writes are serialized and calibrated', () async {
    final backend = RecordingBackend({'a'});
    final successful = <String>[];
    final result = await runLightBatch(
      library: example(),
      profiles: [floor, ceiling],
      targets: {
        'a': const SceneState(power: true),
        'b': const SceneState(power: true, rgb: [239, 66, 255], brightness: 80),
        'c': const SceneState(power: false),
      },
      settings: {
        'b': const LightSettings(gains: [1, 0.3, 0.75]),
      },
      backend: backend,
      onDelivered: (light, state) async => successful.add(light.id),
    );
    expect(result.map((r) => r.delivered), [false, true, true]);
    expect(successful, ['b', 'c']);
    expect(backend.peak, 1);
    expect(backend.packets['b']!.last, [
      0x5a,
      0,
      1,
      239,
      20,
      191,
      0,
      31,
      0,
      0xa5,
    ]);
    expect(backend.packets['c'], [
      [0x5b, 0x0f, 1, 0xb5],
    ]);
  });
  test('incompatible scene sends nothing to that target', () async {
    final backend = RecordingBackend();
    final result = await runLightBatch(
      library: example(),
      profiles: [floor, ceiling],
      targets: {
        'c': const SceneState(power: true, rgb: [255, 0, 0], brightness: 100),
      },
      settings: {},
      backend: backend,
      onDelivered: (_, s) async {},
    );
    expect(result.single.delivered, false);
    expect(backend.calls, isEmpty);
  });
  test('storage failure is distinguished from delivery failure', () async {
    final result = await runLightBatch(
      library: example(),
      profiles: [floor],
      targets: {'a': const SceneState(power: true)},
      settings: {},
      backend: RecordingBackend(),
      onDelivered: (_, s) async => throw StateError('disk'),
    );
    expect(result.single.delivered, true);
    expect(result.single.persistenceWarning, isNotNull);
  });
  test('unrecognized references and duplicate group members are rejected', () {
    final library = example();
    for (final members in [
      ['a', 'a'],
      ['unknown'],
      <String>[],
    ]) {
      library.collections['Bad'] = LightCollection('group', members);
      expect(
        () => HomeLibrary.fromJson(library.toJson()),
        throwsFormatException,
      );
    }
  });
  test('copying a scene does not alias another snapshot', () {
    final original = example();
    original.scenes['Evening'] = {
      'a': SceneState(power: true, rgb: [1, 2, 3]),
    };
    final copied = original.copy();
    copied.scenes['Evening']!['a']!.rgb![0] = 200;
    expect(original.scenes['Evening']!['a']!.rgb, [1, 2, 3]);
  });
  test('stop skips remaining targets without another write', () async {
    var stop = false;
    final backend = RecordingBackend();
    final result = await runLightBatch(
      library: example(),
      profiles: [floor],
      targets: {
        'a': const SceneState(power: true),
        'b': const SceneState(power: true),
      },
      settings: {},
      backend: backend,
      shouldStop: () => stop,
      onDelivered: (_, s) async {
        stop = true;
      },
    );
    expect(backend.calls, ['a']);
    expect(result.last.cancelled, true);
  });
}
