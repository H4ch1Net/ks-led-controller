import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/protocol.dart';

void main() {
  final fixtures = jsonDecode(
    File('../../protocol/golden_packets.json').readAsStringSync(),
  ) as List;
  for (final row in fixtures) {
    test(row['name'] as String, () {
      final args = row['args'] as List;
      final List<int> packet;
      switch (row['encoder']) {
        case 'power':
          packet = powerPacket(args[0] as bool);
        case 'color':
          packet = colorPacket(
            args.take(3).cast<int>().toList(),
            args.length > 3 ? args[3] as String : 'ceiling',
            args.length > 4 ? args[4] as int : 255,
          );
        case 'white_brightness':
          packet = whitePacket(args[0] as int);
        default:
          throw StateError('Unknown fixture');
      }
      expect(
        packet
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join()
            .toUpperCase(),
        row['hex'],
      );
    });
  }
  test('rejects invalid and unsupported settings', () {
    expect(() => colorPacket([256, 0, 0], 'floor', 255), throwsArgumentError);
    expect(() => colorPacket([255, 0, 0], 'ceiling', 50), throwsArgumentError);
  });
  test('profile asset matches the Python source', () {
    expect(
      jsonDecode(File('assets/profiles.json').readAsStringSync()),
      jsonDecode(File('../../ks_light/profiles.json').readAsStringSync()),
    );
  });
}
