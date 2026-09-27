import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ks_light/hub_client.dart';
import 'package:ks_light/hub_library_screen.dart';

class LibraryHub extends HubClient {
  LibraryHub() : super('http://127.0.0.1', 'x' * 32);
  Map<String, dynamic>? saved;
  final requests = <String>[];
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? key,
    String? ifMatch,
    void Function(String?)? onRevision,
  }) async {
    requests.add('$method $path');
    if (method == 'PUT') {
      expect(ifMatch, '"${'b' * 64}"');
      saved = body;
    }
    onRevision?.call('"${'b' * 64}"');
    return {'version': 1, 'groups': [], 'scenes': []};
  }
}

void main() {
  testWidgets(
    'scene draft captures a native effect and persists only on explicit library save',
    (tester) async {
      final hub = LibraryHub();
      await tester.pumpWidget(
        MaterialApp(
          home: HubLibraryScreen(
            client: hub,
            lights: const [
              {
                'id': 'desk',
                'name': 'Desk',
                'last_sent': {
                  'native_effect': 137,
                  'speed': 35,
                  'brightness': 40,
                },
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add scene'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Evening');
      await tester.tap(find.text('Desk'));
      await tester.tap(find.text('Keep changes'));
      await tester.pumpAndSettle();
      expect(hub.requests, ['GET /library']);
      await tester.tap(find.text('Save library to hub'));
      await tester.pumpAndSettle();
      expect(hub.requests, ['GET /library', 'PUT /library']);
      final scene = (hub.saved!['scenes'] as List).single as Map;
      expect(scene['name'], 'Evening');
      expect(scene['actions'], [
        {
          'light': 'desk',
          'type': 'native',
          'body': {'effect': 137, 'speed': 35, 'brightness': 40},
        },
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}
