import 'dart:convert';

import 'package:flutter/services.dart';

class LightSettings {
  const LightSettings({
    this.name = '',
    this.order = 'RGB',
    this.gains = const [1, 1, 1],
    this.presets = const {},
    this.lastColor,
    this.lastBrightness = 255,
  });
  final List<int>? lastColor;
  final int lastBrightness;
  LightSettings withColor(List<int> rgb, int brightness) => LightSettings(
    name: name,
    order: order,
    gains: gains,
    presets: presets,
    lastColor: List.of(rgb),
    lastBrightness: brightness,
  );
  final String name;
  final String order;
  final List<double> gains;
  final Map<String, List<double>> presets;
  static const builtInPresets = <String, List<double>>{
    'Neutral': [1, 1, 1],
    'Less blue': [1, 1, 0.75],
    'Less red': [0.75, 1, 1],
    'Less green': [1, 0.75, 1],
    'Purple trial': [1, 0.30, 0.75],
  };
  static List<double> parseGains(dynamic value) {
    if (value is! List ||
        value.length != 3 ||
        value.any((v) => v is! num || !v.isFinite || v < 0 || v > 1)) {
      throw const FormatException('Invalid calibration values');
    }
    return value.map((v) => (v as num).toDouble()).toList();
  }

  static const orders = ['RGB', 'RBG', 'GRB', 'GBR', 'BRG', 'BGR'];
  List<int> apply(List<int> rgb) {
    final adjusted = List.generate(
      3,
      (i) => (rgb[i] * gains[i]).round().clamp(0, 255),
    );
    return order.split('').map((c) => adjusted['RGB'.indexOf(c)]).toList();
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'order': order,
    'gains': gains,
    'presets': presets,
    'lastColor': lastColor,
    'lastBrightness': lastBrightness,
  };
  factory LightSettings.fromJson(Map<String, dynamic> value) {
    final name = value['name'];
    final order = value['order'];
    final gains = value['gains'];
    if (name is! String ||
        name.length > 40 ||
        !orders.contains(order) ||
        gains is! List ||
        gains.length != 3 ||
        gains.any((v) => v is! num || !v.isFinite || v < 0 || v > 1)) {
      throw const FormatException('Invalid saved light settings');
    }
    final lastColor = value['lastColor'];
    final lastBrightness = value['lastBrightness'] ?? 255;
    if ((lastColor != null &&
            (lastColor is! List ||
                lastColor.length != 3 ||
                lastColor.any((v) => v is! int || v < 0 || v > 255))) ||
        lastBrightness is! int ||
        lastBrightness < 0 ||
        lastBrightness > 255) {
      throw const FormatException('Invalid saved color');
    }
    final saved = value['presets'];
    final presets = <String, List<double>>{};
    if (saved != null) {
      if (saved is! Map || saved.length > 20) {
        throw const FormatException('Invalid calibration presets');
      }
      for (final entry in saved.entries) {
        if (entry.key is! String ||
            (entry.key as String).trim().isEmpty ||
            (entry.key as String).length > 40) {
          throw const FormatException('Invalid calibration name');
        }
        presets[entry.key as String] = parseGains(entry.value);
      }
    } else if (gains.any((v) => v != 1)) {
      // Preserve the calibration from versions with only one saved balance.
      presets['Previous balance'] = parseGains(gains);
    }
    return LightSettings(
      presets: presets,
      lastColor: lastColor == null ? null : List<int>.from(lastColor as List),
      lastBrightness: lastBrightness,
      name: name,
      order: order as String,
      gains: gains.map((v) => (v as num).toDouble()).toList(),
    );
  }
}

class SettingsStore {
  static const channel = MethodChannel('dev.kslight/settings');
  Future<Map<String, LightSettings>> load() async {
    final raw = await channel.invokeMethod<String>('load');
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (key, value) =>
          MapEntry(key, LightSettings.fromJson(value as Map<String, dynamic>)),
    );
  }

  Future<void> save(Map<String, LightSettings> settings) async {
    await channel.invokeMethod<void>(
      'save',
      jsonEncode(settings.map((key, value) => MapEntry(key, value.toJson()))),
    );
  }
}
