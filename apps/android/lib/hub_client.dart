import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class HubError implements Exception {
  HubError(this.message);
  final String message;
  @override
  String toString() => message;
}

class HubClient {
  HubClient(String endpoint, this.token) : base = validateEndpoint(endpoint);
  final Uri base;
  final String token;
  final Set<HttpClient> _active = {};
  bool _closed = false;
  bool hasGroups = false,
      hasScenes = false,
      canEditCalibration = false,
      canEditLibrary = false;
  List<Map<String, dynamic>> lastMembers = [];

  static Uri validateEndpoint(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        !(uri.scheme == 'https' ||
            (uri.scheme == 'http' &&
                ['127.0.0.1', 'localhost', '::1'].contains(uri.host)))) {
      throw HubError(
        'Use an HTTPS hub address, or localhost for a USB connection.',
      );
    }
    return uri;
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? key,
    String? ifMatch,
    void Function(String?)? onRevision,
  }) async {
    if (token.length < 32 ||
        token.contains(RegExp(r'\s')) ||
        token.codeUnits.any((c) => c > 127)) {
      throw HubError('Enter a valid hub access token.');
    }
    if (_closed) throw HubError('Hub connection is closed.');
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    _active.add(http);
    try {
      return await (() async {
        final req = await http.openUrl(method, base.resolve('/api/v1$path'));
        req.followRedirects = false;
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        if (key != null) req.headers.set('Idempotency-Key', key);
        if (ifMatch != null) req.headers.set('If-Match', ifMatch);
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(body));
        }
        final response = await req.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 262144) {
            throw HubError('Hub response is too large.');
          }
        }
        if (response.statusCode == 401) {
          throw HubError('Hub access token was rejected.');
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HubError(
            'Hub rejected the request (${response.statusCode}). Refresh before trying again.',
          );
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        onRevision?.call(response.headers.value(HttpHeaders.etagHeader));
        return decoded;
      })().timeout(const Duration(seconds: 8));
    } on HubError {
      rethrow;
    } on TimeoutException {
      throw HubError('Hub connection timed out.');
    } on HandshakeException {
      throw HubError('The hub certificate could not be verified.');
    } on FormatException {
      throw HubError('The hub returned an invalid response.');
    } on IOException {
      throw HubError(
        'Could not reach the hub. Check its address and connection.',
      );
    } finally {
      _active.remove(http);
      http.close(force: true);
    }
  }

  Future<Map<String, dynamic>> connect() async {
    final capabilities = await request('GET', '/capabilities');
    if (capabilities['api_version'] != 1) {
      throw HubError('Unsupported hub API version.');
    }
    hasGroups = capabilities['groups'] == true;
    canEditCalibration = capabilities['calibration_edit'] == true;
    canEditLibrary = capabilities['library_edit'] == true;
    hasScenes = capabilities['scenes'] == true;
    return request('GET', '/health');
  }

  Future<List<Map<String, dynamic>>> lights() async {
    final data = await request('GET', '/lights');
    final values = data['lights'];
    if (values is! List || values.length > 64) {
      throw HubError('Invalid hub light catalog.');
    }
    return values.map((item) {
      if (item is! Map<String, dynamic> ||
          item['id'] is! String ||
          item['name'] is! String ||
          (item['last_sent'] != null && item['last_sent'] is! Map) ||
          item['capabilities'] is! Map ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(item['id'])) {
        throw HubError('Invalid hub light catalog.');
      }
      if (item['calibration'] != null) {
        final calibration = item['calibration'];
        final gains = calibration is Map ? calibration['rgb_gains'] : null;
        if (gains is! List ||
            gains.length != 3 ||
            gains.any((g) => g is! num || !g.isFinite || g < 0 || g > 1)) {
          throw HubError('Invalid hub color balance.');
        }
      }
      return item;
    }).toList();
  }

  Future<Map<String, List<Map<String, dynamic>>>> library() async {
    final result = <String, List<Map<String, dynamic>>>{
      'groups': [],
      'scenes': [],
    };
    for (final kind in ['groups', 'scenes']) {
      if (kind == 'groups' ? !hasGroups : !hasScenes) continue;
      final data = await request('GET', '/$kind');
      final items = data[kind];
      if (items is! List || items.length > 32) {
        throw HubError('Invalid hub library.');
      }
      final seen = <String>{};
      for (final item in items) {
        if (item is! Map<String, dynamic> ||
            item['id'] is! String ||
            !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(item['id']) ||
            !seen.add(item['id']) ||
            item['name'] is! String ||
            (item['name'] as String).trim().isEmpty ||
            (item['name'] as String).length > 80) {
          throw HubError('Invalid hub library.');
        }
        final members = kind == 'groups' ? item['members'] : item['actions'];
        if (members is! List || members.isEmpty || members.length > 64) {
          throw HubError('Invalid hub library.');
        }
        final targets = <String>{};
        for (final member in members) {
          final id = kind == 'groups'
              ? member
              : member is Map
              ? member['light']
              : null;
          if (id is! String ||
              !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(id) ||
              !targets.add(id)) {
            throw HubError('Invalid hub library.');
          }
        }
        result[kind]!.add(item);
      }
    }
    return result;
  }

  Future<String> command(
    String id,
    Map<String, dynamic> body, {
    bool native = false,
    String targetKind = 'lights',
  }) async {
    if (!['lights', 'groups', 'scenes'].contains(targetKind)) {
      throw HubError('Invalid target type.');
    }
    lastMembers = [];
    final key = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    String? operation;
    try {
      final accepted = await request(
        native || targetKind == 'scenes' ? 'POST' : 'PATCH',
        '/$targetKind/${Uri.encodeComponent(id)}/${targetKind == 'scenes'
            ? 'apply'
            : native
            ? 'effects/native'
            : 'state'}',
        body: body,
        key: key,
      );
      operation = accepted['operation_id'] as String?;
      if (operation == null ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(operation)) {
        throw HubError('Invalid operation ID.');
      }
      final deadline = DateTime.now().add(
        Duration(seconds: targetKind == 'lights' ? 25 : 90),
      );
      while (DateTime.now().isBefore(deadline)) {
        final result = await request(
          'GET',
          '/operations/${Uri.encodeComponent(operation)}',
        );
        if (result['operation_id'] != operation) {
          throw HubError('Mismatched operation response.');
        }
        final status = result['status'];
        if (['succeeded', 'failed', 'cancelled'].contains(status)) {
          if (!['simulated', 'unconfirmed'].contains(result['confirmation'])) {
            throw HubError('Unknown confirmation.');
          }
          if (targetKind != 'lights') {
            final members = result['members'];
            if (members is! List || members.isEmpty || members.length > 64) {
              throw HubError('Invalid member results.');
            }
            final targets = <String>{};
            final parsed = <Map<String, dynamic>>[];
            for (final member in members) {
              if (member is! Map<String, dynamic> ||
                  member['target_id'] is! String ||
                  !RegExp(r'^[a-zA-Z0-9_-]{1,64}$')
                      .hasMatch(member['target_id']) ||
                  !targets.add(member['target_id']) ||
                  member['confirmation'] != result['confirmation'] ||
                  ![
                    'succeeded',
                    'failed',
                    'cancelled',
                  ].contains(member['status'])) {
                throw HubError('Invalid member result.');
              }
              parsed.add(member);
            }
            final sent = parsed.where((m) => m['status'] == 'succeeded').length;
            if ((status == 'succeeded') != (sent == parsed.length)) {
              throw HubError('Inconsistent member results.');
            }
            lastMembers = parsed;
            final label = result['confirmation'] == 'simulated'
                ? 'Simulated'
                : 'Sent, not physically confirmed';
            return '$label: $sent of ${parsed.length} lights completed.${sent == parsed.length ? '' : ' Check the results below; nothing was retried.'}';
          }
          if (status == 'succeeded') {
            return result['confirmation'] == 'simulated'
                ? 'Simulated'
                : 'Sent — not physically confirmed';
          }
          return 'Command $status. Refresh to check last-sent state.';
        }
        if (!['queued', 'running'].contains(status)) {
          throw HubError('Unknown operation status.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      throw HubError('Completion timed out.');
    } catch (_) {
      throw HubError(
        'Delivery is uncertain. Do not automatically repeat the command.${operation == null ? '' : ' Operation: $operation'} Refresh or check the hub.',
      );
    }
  }

  void close() {
    _closed = true;
    for (final http in _active.toList()) {
      http.close(force: true);
    }
    _active.clear();
  }
}
