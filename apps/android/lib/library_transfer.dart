import 'dart:convert';

import 'home_library.dart';
import 'settings.dart';

class LibraryImport {
  const LibraryImport(
    this.library,
    this.collections,
    this.scenes, [
    this.deviceMatches = const {},
  ]);
  final HomeLibrary library;
  final List<String> collections, scenes;
  final Map<String, String> deviceMatches;
}

class LibraryTransfer {
  static const maxBytes = 262144;
  static const maxEntries = 100;

  static void checkSize(HomeLibrary library) {
    if (library.collections.length > maxEntries ||
        library.scenes.length > maxEntries ||
        library.lights.length > 256) {
      throw const FormatException(
        'Backups support up to 100 collections, 100 scenes and 256 lights.',
      );
    }
  }

  static String encode(HomeLibrary library, bool demo) {
    final copy = library.copy();
    final referenced = {
      for (final group in copy.collections.values) ...group.members,
      for (final scene in copy.scenes.values) ...scene.keys,
    };
    copy.lights.removeWhere((id, _) => !referenced.contains(id));
    copy.defaultLightId = null;
    checkSize(copy);
    if (copy.collections.isEmpty && copy.scenes.isEmpty) {
      throw const FormatException('Create a room, group or scene first.');
    }
    final text = jsonEncode({
      'format': 'ks-light-rooms-scenes',
      'version': 1,
      'demo': demo,
      'library': copy.toJson(),
    });
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('Backup is too large.');
    }
    return text;
  }

  static HomeLibrary read(String text, bool demo) {
    if (text.length > maxBytes || utf8.encode(text).length > maxBytes) {
      throw const FormatException('Backup is too large.');
    }
    dynamic data;
    try {
      data = jsonDecode(text);
    } catch (_) {
      throw const FormatException(
        'Paste a valid KS Light rooms-and-scenes backup.',
      );
    }
    if (data is! Map<String, dynamic> ||
        data.keys.toSet().difference({
          'format',
          'version',
          'demo',
          'library',
        }).isNotEmpty ||
        data['format'] != 'ks-light-rooms-scenes' ||
        data['version'] is! int ||
        data['version'] != 1 ||
        data['demo'] is! bool ||
        data['library'] is! Map<String, dynamic>) {
      throw const FormatException('Unsupported rooms-and-scenes backup.');
    }
    if (data['demo'] != demo) {
      throw const FormatException(
        'Demo and Bluetooth backups cannot be mixed.',
      );
    }
    late HomeLibrary imported;
    try {
      imported = HomeLibrary.fromJson(data['library'] as Map<String, dynamic>);
    } catch (_) {
      throw const FormatException('The backup contains an invalid library.');
    }
    checkSize(imported);
    if (imported.collections.isEmpty && imported.scenes.isEmpty) {
      throw const FormatException('The backup contains no rooms or scenes.');
    }
    return imported;
  }

  static LibraryImport preview(
    String text,
    HomeLibrary current,
    bool demo,
    List<Map<String, dynamic>> profiles, {
    Map<String, String> mapping = const {},
  }) {
    final source = read(text, demo);
    if (mapping.keys.any((id) => !source.lights.containsKey(id))) {
      throw const FormatException('Unknown source light in device matching.');
    }
    final targets = <String, String>{
      for (final id in source.lights.keys) id: mapping[id] ?? id,
    };
    if (targets.values.toSet().length != targets.length) {
      throw const FormatException(
        'Choose a different target for each backup light.',
      );
    }
    for (final entry in source.lights.entries) {
      final target = current.lights[targets[entry.key]];
      if (target == null || target['prefix'] != entry.value['prefix']) {
        throw const FormatException(
          'Match each backup light to a saved light with the same model.',
        );
      }
    }
    final imported = HomeLibrary()
      ..lights.addAll({
        for (final entry in source.lights.entries)
          targets[entry.key]!: Map<String, String>.of(
            current.lights[targets[entry.key]]!,
          ),
      })
      ..collections.addAll({
        for (final entry in source.collections.entries)
          entry.key: LightCollection(entry.value.kind, [
            for (final id in entry.value.members) targets[id]!,
          ]),
      })
      ..scenes.addAll({
        for (final entry in source.scenes.entries)
          entry.key: {
            for (final state in entry.value.entries)
              targets[state.key]!: state.value,
          },
      });
    for (final entry in imported.lights.entries) {
      if (entry.key.length > 128 ||
          !current.lights.containsKey(entry.key) ||
          current.lights[entry.key]!['prefix'] != entry.value['prefix']) {
        throw const FormatException(
          'Scan the same lights on this phone before importing.',
        );
      }
      imported.resolve(entry.key, profiles);
    }
    // Validate capability/packet compatibility without opening a transport.
    for (final scene in imported.scenes.values) {
      for (final entry in scene.entries) {
        entry.value.packets(
          imported.resolve(entry.key, profiles),
          const LightSettings(),
        );
      }
    }
    final next = current.copy();
    final collections = <String>[], scenes = <String>[];
    for (final entry in imported.collections.entries) {
      final name = uniqueName(entry.key, next.collections.keys);
      next.collections[name] = entry.value;
      collections.add(name);
    }
    for (final entry in imported.scenes.entries) {
      final name = uniqueName(entry.key, next.scenes.keys);
      next.scenes[name] = entry.value;
      scenes.add(name);
    }
    checkSize(next);
    // Keep device names, the default device and all existing definitions.
    return LibraryImport(next, collections, scenes, {
      for (final entry in targets.entries)
        '${source.lights[entry.key]!['name']} (${entry.key})':
            '${current.lights[entry.value]!['name']} (${entry.value})',
    });
  }

  static String uniqueName(String original, Iterable<String> existing) {
    final names = existing.map((name) => name.toLowerCase()).toSet();
    if (!names.contains(original.toLowerCase())) return original;
    for (var n = 2; n <= maxEntries + 1; n++) {
      final suffix = ' ($n)';
      var base = original;
      while (base.length + suffix.length > 40) {
        base = String.fromCharCodes(base.runes.take(base.runes.length - 1));
      }
      final candidate = '$base$suffix';
      if (!names.contains(candidate.toLowerCase())) return candidate;
    }
    throw const FormatException('Too many copies with the same name.');
  }
}
