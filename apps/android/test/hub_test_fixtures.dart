import 'dart:async';
import 'dart:convert';

import 'package:ks_light/hub_client.dart';

const testToken = 'test-only-library-token-at-least-32-characters';
const groups = [
  {
    'id': 'room',
    'name': 'Room',
    'members': ['desk', 'sofa'],
  },
];
const scenes = [
  {
    'id': 'evening',
    'name': 'Evening',
    'actions': [
      {'light': 'desk'},
      {'light': 'sofa'},
    ],
  },
];

class FakeHub extends HubClient {
  FakeHub() : super('http://127.0.0.1', testToken);
  final calls = <String>[];
  Completer<void>? gate;
  bool disconnected = false;
  @override
  Future<Map<String, dynamic>> connect() async => {'mode': 'simulation'};
  @override
  Future<List<Map<String, dynamic>>> lights() async => [
    {
      'id': 'desk',
      'name': 'Desk',
      'calibration': {
        'rgb_gains': [1, .3, .75],
      },
      'last_sent': null,
      'capabilities': {},
    },
    {'id': 'sofa', 'name': 'Sofa', 'last_sent': null, 'capabilities': {}},
  ];
  @override
  Future<Map<String, List<Map<String, dynamic>>>> library() async => {
    'groups': groups,
    'scenes': scenes,
  };
  @override
  Future<String> command(
    String id,
    Map<String, dynamic> body, {
    bool native = false,
    String targetKind = 'lights',
  }) async {
    calls.add('$targetKind/$id:${jsonEncode(body)}');
    if (gate != null) await gate!.future;
    lastMembers = [
      {'target_id': 'desk', 'status': 'succeeded', 'confirmation': 'simulated'},
      {'target_id': 'sofa', 'status': 'failed', 'confirmation': 'simulated'},
    ];
    return 'Simulated: 1 of 2 lights completed. Nothing was retried.';
  }

  @override
  void close() {
    disconnected = true;
    super.close();
  }
}
