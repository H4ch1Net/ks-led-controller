import 'dart:io';

import 'package:ks_light/hub_client.dart';

// Local simulator contract check. The token travels through a temporary file.
Future<void> main(List<String> args) async {
  if (args.length != 2) throw ArgumentError('Expected hub URL and token file');
  final client = HubClient(
    args[0],
    (await File(args[1]).readAsString()).trim(),
  );
  void check(bool condition) {
    if (!condition) throw StateError('Hub library contract mismatch');
  }

  try {
    final health = await client.connect();
    check(health['mode'] == 'simulation');
    final library = await client.library();
    check(library['groups']!.first['id'] == 'room');
    check(library['scenes']!.first['id'] == 'evening');
    check(
      (await client.command('room', {
        'power': false,
      }, targetKind: 'groups')).contains('2 of 2'),
    );
    check(
      (await client.command(
        'evening',
        {},
        targetKind: 'scenes',
      )).contains('2 of 2'),
    );
    final lights = await client.lights();
    final desk =
        lights.firstWhere((l) => l['id'] == 'desk')['last_sent'] as Map;
    final sofa =
        lights.firstWhere((l) => l['id'] == 'sofa')['last_sent'] as Map;
    check(
      desk['brightness'] == 35 && desk['rgb'].toString() == '[255, 190, 120]',
    );
    check(sofa['native_effect'] == 137 && sofa['brightness'] == 25);
    check(
      client.lastMembers.length == 2 &&
          client.lastMembers.every((m) => m['status'] == 'succeeded'),
    );
    check(
      (await client.command('room', {
        'power': true,
        'brightness': 60,
      }, targetKind: 'groups')).contains('2 of 2'),
    );
    final dimmed = await client.lights();
    check(
      (dimmed.firstWhere((l) => l['id'] == 'desk')['last_sent'] as Map)['rgb']
              .toString() ==
          '[255, 190, 120]',
    );
    check(
      (dimmed.firstWhere((l) => l['id'] == 'sofa')['last_sent']
              as Map)['native_effect'] ==
          137,
    );
    check(
      (await client.command('room', {
        'power': true,
        'rgb': [100, 200, 80],
        'brightness': 67,
      }, targetKind: 'groups')).contains('2 of 2'),
    );
    check(
      (await client.command(
        'room',
        {'effect': 137, 'speed': 35, 'brightness': 35},
        targetKind: 'groups',
        native: true,
      )).contains('2 of 2'),
    );
    stdout.writeln(
      'PASS: Android Dart client -> Python API, group power/color/brightness/native effects, calibrated color and mixed scene, simulator only.',
    );
  } finally {
    client.close();
  }
}
