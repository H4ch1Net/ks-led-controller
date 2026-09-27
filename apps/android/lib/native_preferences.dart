import 'dart:convert';

import 'package:flutter/services.dart';

class NativeChoice {
  const NativeChoice({
    this.effect = 0x89,
    this.speed = 35,
    this.brightness = 50,
  });
  final int effect, speed, brightness;
  Map<String, dynamic> toJson() => {
    'effect': effect,
    'speed': speed,
    'brightness': brightness,
  };
  factory NativeChoice.fromJson(Map<String, dynamic> json) {
    final effect = json['effect'],
        speed = json['speed'],
        brightness = json['brightness'];
    if (effect is! int ||
        effect < 0x82 ||
        effect > 0x8a ||
        speed is! int ||
        speed < 0 ||
        speed > 100 ||
        brightness is! int ||
        brightness < 1 ||
        brightness > 100) {
      throw const FormatException('Invalid saved effect');
    }
    return NativeChoice(effect: effect, speed: speed, brightness: brightness);
  }
}

class NativeLibrary {
  NativeLibrary({
    this.last = const NativeChoice(),
    Map<String, NativeChoice> presets = const {},
  }) : presets = Map.unmodifiable(presets);
  final NativeChoice last;
  final Map<String, NativeChoice> presets;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'last': last.toJson(),
    'presets': presets.map((k, v) => MapEntry(k, v.toJson())),
  };
  factory NativeLibrary.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['last'] is! Map ||
        json['presets'] is! Map) {
      throw const FormatException('Invalid saved effect library');
    }
    final presets = Map<String, dynamic>.from(json['presets'] as Map);
    if (presets.length > 20 ||
        presets.keys.any((n) => n.trim().isEmpty || n.length > 40)) {
      throw const FormatException('Invalid effect presets');
    }
    return NativeLibrary(
      last: NativeChoice.fromJson(
        Map<String, dynamic>.from(json['last'] as Map),
      ),
      presets: presets.map(
        (k, v) => MapEntry(
          k,
          NativeChoice.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      ),
    );
  }
}

class NativePreferencesStore {
  static const channel = MethodChannel('dev.kslight/settings');
  Future<NativeLibrary> load(String id) async {
    final raw = await channel.invokeMethod<String>('loadNativeEffects', id);
    return raw == null
        ? NativeLibrary()
        : NativeLibrary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(String id, NativeLibrary library) async {
    await channel.invokeMethod<void>('saveNativeEffects', {
      'id': id,
      'json': jsonEncode(library.toJson()),
    });
  }
}
