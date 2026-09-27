import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/home_library.dart';
import 'package:ks_light/library_transfer.dart';

import 'home_library_test.dart' show example, floor, ceiling;

HomeLibrary source() => example()
  ..defaultLightId = 'a'
  ..collections['Room'] = const LightCollection('room', ['a', 'b'])
  ..scenes['Evening'] = {
    'a': const SceneState(power: true, rgb: [239, 66, 255], brightness: 90),
  };

void main() {
  test('explicit device matching remaps memberships and snapshots without merging targets', () {
    final backup = LibraryTransfer.encode(source(), true);
    final current = example();
    final matched = LibraryTransfer.preview(
      backup,
      current,
      true,
      [floor, ceiling],
      mapping: {'a': 'b', 'b': 'a'},
    );
    expect(matched.library.collections['Room']!.members, ['b', 'a']);
    expect(matched.library.scenes['Evening']!['b']!.rgb, [239, 66, 255]);
    expect(matched.library.lights['b']!['name'], 'Sofa');
    expect(current.scenes, isEmpty);
    for (final mapping in [
      {'a': 'b'},
      {'a': 'c'},
      {'missing': 'a'},
    ]) {
      expect(
        () => LibraryTransfer.preview(backup, current, true, [
          floor,
          ceiling,
        ], mapping: mapping),
        throwsFormatException,
      );
    }
  });
  test('backup includes referenced lights and snapshots but not the default device', () {
    final original = source();
    final raw = LibraryTransfer.encode(original, true);
    final data = jsonDecode(raw) as Map;
    final saved = HomeLibrary.fromJson(data['library'] as Map<String, dynamic>);
    expect(saved.lights.keys, ['a', 'b']);
    expect(saved.defaultLightId, isNull);
    expect(saved.scenes['Evening']!['a']!.rgb, [239, 66, 255]);
    expect(original.defaultLightId, 'a');
    expect(original.lights.keys, ['a', 'b', 'c']);
  });

  test(
    'preview merges detached copies and preserves current names and default',
    () {
      final current = source()..defaultLightId = 'b';
      current.lights['a']!['name'] = 'Current name';
      final before = jsonEncode(current.toJson());
      final preview = LibraryTransfer.preview(
        LibraryTransfer.encode(source(), true),
        current,
        true,
        [floor, ceiling],
      );
      expect(preview.collections, ['Room (2)']);
      expect(preview.scenes, ['Evening (2)']);
      expect(preview.library.defaultLightId, 'b');
      expect(preview.library.lights['a']!['name'], 'Current name');
      expect(preview.library.scenes['Evening (2)']!['a']!.rgb, [239, 66, 255]);
      preview.library.scenes['Evening']!.clear();
      expect(jsonEncode(current.toJson()), before);
    },
  );

  test(
    'mode, identity and profile mismatches never change current library',
    () {
      final backup = LibraryTransfer.encode(source(), true);
      final current = example();
      final before = jsonEncode(current.toJson());
      expect(
        () => LibraryTransfer.preview(backup, current, false, [floor, ceiling]),
        throwsFormatException,
      );
      expect(
        () => LibraryTransfer.preview(backup, HomeLibrary(), true, [
          floor,
          ceiling,
        ]),
        throwsFormatException,
      );
      final changed = current.copy()..lights['a']!['prefix'] = 'KS03-';
      expect(
        () => LibraryTransfer.preview(backup, changed, true, [floor, ceiling]),
        throwsFormatException,
      );
      expect(
        () => LibraryTransfer.preview(backup, current, true, []),
        throwsStateError,
      );
      expect(jsonEncode(current.toJson()), before);
    },
  );

  test('malformed, oversized and future backups are rejected', () {
    final current = example();
    final raw = LibraryTransfer.encode(source(), true);
    for (final text in [
      'broken',
      '[]',
      'null',
      'x' * (LibraryTransfer.maxBytes + 1),
      'é' * 150000,
    ]) {
      expect(
        () => LibraryTransfer.preview(text, current, true, [floor, ceiling]),
        throwsFormatException,
      );
    }
    for (final version in [true, 1.0, 2]) {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      value['version'] = version;
      expect(
        () => LibraryTransfer.preview(jsonEncode(value), current, true, [
          floor,
          ceiling,
        ]),
        throwsFormatException,
      );
    }
    final value = jsonDecode(raw) as Map<String, dynamic>;
    value['unexpected'] = true;
    expect(
      () => LibraryTransfer.preview(jsonEncode(value), current, true, [
        floor,
        ceiling,
      ]),
      throwsFormatException,
    );
    expect(
      () => LibraryTransfer.encode(example(), true),
      throwsFormatException,
    );
  });

  test('unusable scene brightness is rejected before any import', () {
    final imported = example()
      ..scenes['Unsupported'] = {
        'c': const SceneState(power: true, rgb: [1, 2, 3], brightness: 80),
      };
    expect(
      () => LibraryTransfer.preview(
        LibraryTransfer.encode(imported, true),
        example(),
        true,
        [floor, ceiling],
      ),
      throwsArgumentError,
    );
  });

  test('name collision handling is case-insensitive and preserves Unicode boundaries', () {
    expect(
      LibraryTransfer.uniqueName('ROOM', ['room', 'ROOM (2)']),
      'ROOM (3)',
    );
    final longName = '💡' * 20;
    final renamed = LibraryTransfer.uniqueName(longName, [longName]);
    expect(renamed.length, lessThanOrEqualTo(40));
    expect(utf8.decode(utf8.encode(renamed)), renamed);
    validName(renamed);
    final full = source();
    for (var i = 0; i < 100; i++) {
      full.collections['Room $i'] = const LightCollection('group', ['a']);
    }
    expect(() => LibraryTransfer.encode(full, true), throwsFormatException);
  });
}
