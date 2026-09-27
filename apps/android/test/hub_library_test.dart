import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/hub_client.dart';

import 'hub_test_fixtures.dart';

void main() {
  test(
    'hub light calibration is validated without requiring it on older hubs',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HubClient('http://127.0.0.1:${server.port}', testToken);
      dynamic calibration;
      server.listen((req) async {
        req.response.write(
          jsonEncode({
            'lights': [
              {
                'id': 'desk',
                'name': 'Desk',
                'last_sent': null,
                'capabilities': {},
                'calibration': ?calibration,
              },
            ],
          }),
        );
        await req.response.close();
      });
      try {
        expect((await client.lights()).length, 1);
        calibration = {
          'rgb_gains': [1, .3, .75],
        };
        expect((await client.lights()).first['calibration'], calibration);
        for (final invalid in [
          [],
          {
            'rgb_gains': [1, true, 1],
          },
          {
            'rgb_gains': [1, 2, 1],
          },
        ]) {
          calibration = invalid;
          await expectLater(client.lights(), throwsA(isA<HubError>()));
        }
      } finally {
        client.close();
        await server.close(force: true);
      }
    },
  );

  test(
    'library feature discovery preserves compatibility with older hubs',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HubClient('http://127.0.0.1:${server.port}', testToken);
      final paths = <String>[];
      var supported = false;
      server.listen((req) async {
        paths.add(req.uri.path);
        final body = switch (req.uri.path) {
          '/api/v1/capabilities' => {
            'api_version': 1,
            'groups': supported,
            'scenes': supported,
          },
          '/api/v1/health' => {'mode': 'simulation'},
          '/api/v1/groups' => {'groups': groups},
          '/api/v1/scenes' => {'scenes': scenes},
          _ => {},
        };
        req.response.write(jsonEncode(body));
        await req.response.close();
      });
      try {
        await client.connect();
        expect(await client.library(), {'groups': [], 'scenes': []});
        expect(paths.length, 2);
        supported = true;
        await client.connect();
        expect(await client.library(), {'groups': groups, 'scenes': scenes});
        expect(paths.where((p) => p.endsWith('/groups')).length, 1);
      } finally {
        client.close();
        await server.close(force: true);
      }
    },
  );

  test('duplicate catalog targets are rejected', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HubClient('http://127.0.0.1:${server.port}', testToken)
      ..hasGroups = true;
    server.listen((req) async {
      req.response.write(
        jsonEncode({
          'groups': [
            {
              'id': 'room',
              'name': 'Room',
              'members': ['desk', 'desk'],
            },
          ],
        }),
      );
      await req.response.close();
    });
    try {
      await expectLater(client.library(), throwsA(isA<HubError>()));
    } finally {
      client.close();
      await server.close(force: true);
    }
  });

  test('scene submits once and exposes partial member delivery', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HubClient('http://127.0.0.1:${server.port}', testToken);
    var writes = 0;
    server.listen((req) async {
      expect(req.headers.value('authorization'), 'Bearer $testToken');
      if (req.method == 'POST') {
        writes++;
        expect(req.uri.path, '/api/v1/scenes/evening/apply');
        expect(jsonDecode(await utf8.decoder.bind(req).join()), {});
        req.response.write('{"operation_id":"op_scene"}');
      } else {
        req.response.write(
          jsonEncode({
            'operation_id': 'op_scene',
            'status': 'failed',
            'confirmation': 'unconfirmed',
            'members': [
              {
                'target_id': 'desk',
                'status': 'succeeded',
                'confirmation': 'unconfirmed',
              },
              {
                'target_id': 'sofa',
                'status': 'failed',
                'confirmation': 'unconfirmed',
              },
            ],
          }),
        );
      }
      await req.response.close();
    });
    try {
      expect(
        await client.command('evening', {}, targetKind: 'scenes'),
        contains('1 of 2'),
      );
      expect(client.lastMembers.last['status'], 'failed');
      expect(writes, 1);
    } finally {
      client.close();
      await server.close(force: true);
    }
  });

  test('mismatched operation is uncertain and never resubmitted', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HubClient('http://127.0.0.1:${server.port}', testToken);
    var writes = 0;
    server.listen((req) async {
      if (req.method == 'PATCH') {
        writes++;
        req.response.write('{"operation_id":"op_group"}');
      } else {
        req.response.write(
          '{"operation_id":"other","status":"succeeded","confirmation":"simulated"}',
        );
      }
      await req.response.close();
    });
    try {
      await expectLater(
        client.command('room', {'power': false}, targetKind: 'groups'),
        throwsA(
          isA<HubError>().having(
            (e) => e.message,
            'message',
            contains('uncertain'),
          ),
        ),
      );
      expect(writes, 1);
      expect(client.lastMembers, isEmpty);
    } finally {
      client.close();
      await server.close(force: true);
    }
  });
}
