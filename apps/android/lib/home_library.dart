import 'dart:convert';

import 'light_backend.dart';
import 'protocol.dart';
import 'settings.dart';

void validName(String name) {
  if (name.trim().isEmpty || name.length > 40) {
    throw const FormatException('Use a name of 1-40 characters');
  }
}

class SceneState {
  const SceneState({required this.power, this.rgb, this.brightness = 255});
  final bool power;
  final List<int>? rgb;
  final int brightness;
  Map<String, dynamic> toJson() => {
    'power': power,
    'rgb': rgb,
    'brightness': brightness,
  };
  factory SceneState.fromJson(Map<String, dynamic> json) {
    final power = json['power'];
    final rgb = json['rgb'];
    final brightness = json['brightness'];
    if (power is! bool ||
        brightness is! int ||
        brightness < 0 ||
        brightness > 255 ||
        (rgb != null &&
            (rgb is! List ||
                rgb.length != 3 ||
                rgb.any((v) => v is! int || v < 0 || v > 255)))) {
      throw const FormatException('Invalid scene state');
    }
    return SceneState(
      power: power,
      rgb: rgb == null ? null : List<int>.from(rgb as List),
      brightness: brightness,
    );
  }
  List<List<int>> packets(Light light, LightSettings settings) {
    if (!power) return [powerPacket(false)];
    // Build the whole sequence before any write, so incompatible state cannot partially turn on a light.
    final color = rgb == null
        ? null
        : colorPacket(
            settings.apply(rgb!),
            light.profile['color_type'] as String? ?? '',
            deviceBrightness(brightness, light.profile['prefix'] as String),
          );
    return [powerPacket(true), ?color];
  }
}

class LightCollection {
  const LightCollection(this.kind, this.members);
  final String kind;
  final List<String> members;
  Map<String, dynamic> toJson() => {'kind': kind, 'members': members};
}

class HomeLibrary {
  HomeLibrary({
    this.defaultLightId,
    Map<String, Map<String, String>>? lights,
    Map<String, LightCollection>? collections,
    Map<String, Map<String, SceneState>>? scenes,
  }) : lights = lights ?? {},
       collections = collections ?? {},
       scenes = scenes ?? {};
  String? defaultLightId;
  final Map<String, Map<String, String>> lights;
  final Map<String, LightCollection> collections;
  final Map<String, Map<String, SceneState>> scenes;
  void remember(Iterable<Light> found) {
    for (final light in found) {
      lights[light.id] = {
        'name': light.name,
        'prefix': light.profile['prefix'] as String,
      };
    }
  }

  void forget(String id) {
    lights.remove(id);
    if (defaultLightId == id) defaultLightId = null;
    for (final name in collections.keys.toList()) {
      final collection = collections[name]!;
      final remaining = collection.members
          .where((member) => member != id)
          .toList();
      if (remaining.isEmpty) {
        collections.remove(name);
      } else {
        collections[name] = LightCollection(collection.kind, remaining);
      }
    }
    for (final name in scenes.keys.toList()) {
      scenes[name]!.remove(id);
      if (scenes[name]!.isEmpty) scenes.remove(name);
    }
  }

  Light resolve(String id, List<Map<String, dynamic>> profiles) {
    final record = lights[id];
    if (record == null) throw StateError('Saved light is missing');
    final matches = profiles
        .where((p) => p['prefix'] == record['prefix'])
        .toList();
    if (matches.length != 1) throw StateError('Light profile is unavailable');
    return Light(id, record['name']!, matches.single);
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'default_light_id': defaultLightId,
    'lights': lights,
    'collections': collections.map((k, v) => MapEntry(k, v.toJson())),
    'scenes': scenes.map(
      (k, v) => MapEntry(k, v.map((id, state) => MapEntry(id, state.toJson()))),
    ),
  };
  HomeLibrary copy() => HomeLibrary.fromJson(toJson());
  factory HomeLibrary.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['lights'] is! Map ||
        json['collections'] is! Map ||
        json['scenes'] is! Map) {
      throw const FormatException('Unsupported lighting library');
    }
    final result = HomeLibrary();
    for (final entry in (json['lights'] as Map).entries) {
      final value = entry.value;
      if (entry.key is! String ||
          (entry.key as String).isEmpty ||
          value is! Map ||
          value['name'] is! String ||
          value['prefix'] is! String) {
        throw const FormatException('Invalid saved light');
      }
      result.lights[entry.key as String] = {
        'name': value['name'] as String,
        'prefix': value['prefix'] as String,
      };
    }
    final defaultId = json['default_light_id'];
    if (defaultId != null &&
        (defaultId is! String || !result.lights.containsKey(defaultId))) {
      throw const FormatException('Default light must be a saved device');
    }
    result.defaultLightId = defaultId as String?;
    void members(Iterable<dynamic> ids) {
      if (ids.isEmpty ||
          ids.length > 32 ||
          ids.toSet().length != ids.length ||
          ids.any((id) => id is! String || !result.lights.containsKey(id))) {
        throw const FormatException('Choose 1-32 known lights');
      }
    }

    for (final entry in (json['collections'] as Map).entries) {
      if (entry.key is! String) {
        throw const FormatException('Invalid collection name');
      }
      validName(entry.key as String);
      final value = entry.value;
      if (value is! Map ||
          !['room', 'group'].contains(value['kind']) ||
          value['members'] is! List) {
        throw const FormatException('Invalid collection');
      }
      members(value['members'] as List);
      result.collections[entry.key as String] = LightCollection(
        value['kind'] as String,
        List<String>.from(value['members'] as List),
      );
    }
    for (final entry in (json['scenes'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid scene');
      }
      validName(entry.key as String);
      final targets = entry.value as Map;
      members(targets.keys);
      result.scenes[entry.key as String] = targets.map(
        (id, value) => MapEntry(
          id as String,
          SceneState.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      );
    }
    return result;
  }
}

class HomeLibraryStore {
  Future<HomeLibrary> load(bool demo) async {
    final raw = await SettingsStore.channel.invokeMethod<String>(
      'loadLibrary',
      demo,
    );
    return raw == null
        ? HomeLibrary()
        : HomeLibrary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(bool demo, HomeLibrary library) async {
    final validated = HomeLibrary.fromJson(library.toJson());
    await SettingsStore.channel.invokeMethod<void>('saveLibrary', {
      'demo': demo,
      'json': jsonEncode(validated.toJson()),
    });
  }
}

class TargetResult {
  const TargetResult(
    this.id,
    this.error,
    this.persistenceWarning, {
    this.cancelled = false,
  });
  final bool cancelled;
  final String id;
  final String? error;
  final String? persistenceWarning;
  bool get delivered => error == null;
}

Future<List<TargetResult>> runLightBatch({
  required HomeLibrary library,
  required List<Map<String, dynamic>> profiles,
  required Map<String, SceneState> targets,
  required Map<String, LightSettings> settings,
  required LightBackend backend,
  required Future<void> Function(Light, SceneState) onDelivered,
  void Function(String)? onProgress,
  bool Function()? shouldStop,
}) async {
  if (targets.isEmpty || targets.length > 32) {
    throw ArgumentError('Choose 1-32 lights');
  }
  final results = <TargetResult>[];
  // One connection at a time until physical multi-light capacity is measured.
  for (final entry in targets.entries) {
    if (shouldStop?.call() ?? false) {
      results.add(
        TargetResult(
          entry.key,
          'Cancelled before sending',
          null,
          cancelled: true,
        ),
      );
      continue;
    }
    onProgress?.call(entry.key);
    late Light light;
    try {
      light = library.resolve(entry.key, profiles);
      final packets = entry.value.packets(
        light,
        settings[entry.key] ?? const LightSettings(),
      );
      await backend.send(light, packets);
    } catch (error) {
      results.add(TargetResult(entry.key, error.toString(), null));
      continue;
    }
    String? warning;
    try {
      await onDelivered(light, entry.value);
    } catch (_) {
      warning = 'Sent, but could not save last color';
    }
    results.add(TargetResult(entry.key, null, warning));
  }
  return results;
}
