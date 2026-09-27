import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/hub_client.dart';

void main() {
  const token = 'test-only-token-at-least-32-characters';
  test('network endpoints require HTTPS and no embedded secrets', () {
    for (final url in [
      'http://bagley:8765',
      'https://user:pass@hub',
      'https://hub/path',
      'https://hub?token=secret',
    ]) {
      expect(() => HubClient.validateEndpoint(url), throwsA(isA<HubError>()));
    }
    expect(HubClient.validateEndpoint('https://hub:8765').host, 'hub');
    expect(
      HubClient.validateEndpoint('http://127.0.0.1:8765').host,
      '127.0.0.1',
    );
  });
  test('commands authorize once and poll completion without resend', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HubClient('http://127.0.0.1:${server.port}', token);
    var writes = 0, polls = 0;
    server.listen((req) async {
      expect(req.headers.value('authorization'), 'Bearer $token');
      if (req.method == 'PATCH') {
        writes++;
        expect(req.headers.value('Idempotency-Key'), isNotEmpty);
        expect(jsonDecode(await utf8.decoder.bind(req).join()), {
          'power': false,
        });
        req.response.write('{"operation_id":"op_test"}');
      } else {
        polls++;
        req.response.write(
          jsonEncode({
            'operation_id': 'op_test',
            'status': polls == 1 ? 'queued' : 'succeeded',
            'confirmation': 'unconfirmed',
          }),
        );
      }
      await req.response.close();
    });
    try {
      expect(
        await client.command('desk', {'power': false}),
        contains('not physically confirmed'),
      );
      expect(writes, 1);
      expect(polls, 2);
    } finally {
      client.close();
      await server.close(force: true);
    }
  });
  test('redirect does not forward bearer credentials', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HubClient('http://127.0.0.1:${server.port}', token);
    var requests = 0;
    server.listen((req) async {
      requests++;
      req.response.statusCode = 302;
      req.response.headers.set(
        'location',
        'http://127.0.0.1:${server.port}/redirect',
      );
      await req.response.close();
    });
    try {
      await expectLater(client.connect(), throwsA(isA<HubError>()));
      expect(requests, 1);
    } finally {
      client.close();
      await server.close(force: true);
    }
  });
  test('missing operation reports uncertainty without replay', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HubClient('http://127.0.0.1:${server.port}', token);
    var requests = 0;
    server.listen((req) async {
      requests++;
      req.response.write('{}');
      await req.response.close();
    });
    try {
      await expectLater(
        client.command('desk', {'power': true}),
        throwsA(
          isA<HubError>().having(
            (e) => e.message,
            'message',
            contains('uncertain'),
          ),
        ),
      );
      expect(requests, 1);
    } finally {
      client.close();
      await server.close(force: true);
    }
  });
}
