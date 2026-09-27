import 'package:flutter/material.dart';

import 'app_style.dart';

import 'color_picker.dart';
import 'hub_client.dart';
import 'hub_group_controls.dart';
import 'settings.dart';
import 'hub_calibration_screen.dart';
import 'hub_library_screen.dart';

class HubScreen extends StatefulWidget {
  const HubScreen({super.key, this.clientFactory});
  final HubClient Function(String, String)? clientFactory;
  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  final address = TextEditingController();
  final token = TextEditingController();
  HubClient? client;
  List<Map<String, dynamic>> lights = [];
  List<Map<String, dynamic>> groups = [], scenes = [], memberResults = [];
  String? selected;
  String status = '';
  String mode = '';
  bool busy = false, validColor = true, previewingGroup = false;
  bool rememberHub = false;
  List<int> rgb = [255, 147, 41];
  double brightness = 50;
  Map<String, dynamic>? get light {
    for (final item in lights) {
      if (item['id'] == selected) return item;
    }
    return null;
  }

  @override
  void dispose() {
    client?.close();
    address.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => status = error is HubError
              ? error.message
              : 'Could not read the hub response.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    final catalog = await client!.lights();
    final library = await client!.library();
    if (!mounted) return;
    setState(() {
      lights = catalog;
      groups = library['groups']!;
      scenes = library['scenes']!;
      if (!lights.any((item) => item['id'] == selected)) {
        selected = lights.isEmpty ? null : lights.first['id'];
      }
    });
  }

  Future<void> connect() => run(() async {
    final candidate = (widget.clientFactory ?? HubClient.new)(
      address.text,
      token.text.trim(),
    );
    try {
      final health = await candidate.connect();
      final catalog = await candidate.lights();
      final library = await candidate.library();
      if (!mounted) {
        candidate.close();
        return;
      }
      client?.close();
      setState(() {
        client = candidate;
        lights = catalog;
        groups = library['groups']!;
        scenes = library['scenes']!;
        memberResults = [];
        selected = lights.isEmpty ? null : lights.first['id'];
        mode = health['mode'] == 'simulation'
            ? 'Simulation — no physical writes'
            : 'Live hub — controls real lights';
        status =
            'Connected. MQTT: ${(health['mqtt'] as Map?)?['state'] ?? 'unknown'}. Choose a light, group or scene.';
      });
      if (rememberHub) {
        try {
          await SettingsStore.channel.invokeMethod('saveHubPairing', {
            'address': address.text.trim(),
            'token': token.text.trim(),
          });
        } catch (_) {
          if (mounted) {
            setState(
              () => status =
                  '$status Pairing could not be saved; this connection is temporary.',
            );
          }
        }
      }
      token.clear();
    } catch (_) {
      candidate.close();
      rethrow;
    }
  });

  Future<void> loadPairing() => run(() async {
    try {
      final saved = await SettingsStore.channel.invokeMapMethod<String, String>(
        'loadHubPairing',
      );
      if (!mounted) return;
      setState(() {
        if (saved == null) {
          status = 'No saved hub.';
        } else {
          address.text = saved['address']!;
          token.text = saved['token']!;
          rememberHub = true;
          status = 'Saved hub loaded.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => status = 'Saved pairing is unavailable. Forget it and enter your hub details again.',
        );
      }
    }
  });

  Future<void> forgetPairing() => run(() async {
    try {
      await SettingsStore.channel.invokeMethod('forgetHubPairing');
      if (!mounted) return;
      setState(() {
        rememberHub = false;
        token.clear();
        status = 'Saved pairing removed from this phone. Revoke its token on the hub if needed.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => status = 'Could not remove saved pairing. Try again.');
      }
    }
  });

  Future<void> send(Map<String, dynamic> body, {bool native = false}) =>
      sendTo('lights', selected!, body, native: native);

  Future<void> controlGroup(Map<String, dynamic> group) async {
    if (busy) return;
    // The new route blocks interaction; retain the gate without rebuilding
    // controls underneath its navigation transition.
    busy = true;
    previewingGroup = true;
    final command = await Navigator.of(context).push<HubGroupCommand>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Group controls')),
          body: HubGroupControls(group: group, lights: lights),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      busy = false;
      previewingGroup = false;
    });
    if (command != null) {
      await sendTo('groups', group['id'], command.body, native: command.native);
    }
  }

  Future<void> editCalibration() async {
    if (busy || light == null) return;
    busy = true;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HubCalibrationScreen(
          client: client!,
          id: selected!,
          name: light!['name'],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (changed == true) {
      await run(() async {
        await refresh();
        if (mounted) {
          setState(() => status = 'Color balance saved.');
        }
      });
    }
  }

  Future<void> editHubLibrary() async {
    if (busy) return;
    busy = true;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HubLibraryScreen(client: client!, lights: lights),
      ),
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (changed == true) {
      await run(() async {
        await refresh();
        if (mounted) {
          setState(() => status = 'Rooms & scenes saved.');
        }
      });
    }
  }

  Future<void> sendTo(
    String kind,
    String id,
    Map<String, dynamic> body, {
    bool native = false,
  }) => run(() async {
    setState(() {
      memberResults = [];
      status = 'Sending…';
    });
    final result = await client!.command(
      id,
      body,
      native: native,
      targetKind: kind,
    );
    if (!mounted) return;
    setState(() {
      status = result;
      memberResults = client!.lastMembers;
    });
    try {
      await refresh();
    } catch (_) {
      if (mounted) setState(() => status = '$result. State refresh failed.');
    }
  });

  @override
  Widget build(BuildContext context) {
    final state = light?['last_sent'] as Map? ?? {};
    final caps = light?['capabilities'] as Map? ?? {};
    final gains = (light?['calibration'] as Map?)?['rgb_gains'] as List?;
    return Scaffold(
      appBar: AppBar(title: const Text('Hub control')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy && !previewingGroup) const LinearProgressIndicator(),
              StatusNotice(status, key: const Key('hub-status'), busy: busy),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (client == null) ...[
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Icon(
                Icons.hub_outlined,
                size: 44,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Connect your home',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'One hub. All your lights.',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: address,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Hub address',
                hintText: 'https://your-hub:8443',
                prefixIcon: Icon(Icons.link),
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: token,
              enabled: !busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Access token',
                prefixIcon: Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ? null : connect,
              child: const Text('Connect to hub'),
            ),
            CheckboxListTile(
              title: const Text('Remember this hub'),
              subtitle: const Text('Saved securely on this phone.'),
              value: rememberHub,
              onChanged: busy
                  ? null
                  : (value) => setState(() => rememberHub = value!),
            ),
            TextButton(
              onPressed: busy ? null : loadPairing,
              child: const Text('Load saved hub'),
            ),
            TextButton(
              onPressed: busy ? null : forgetPairing,
              child: const Text('Forget saved hub'),
            ),
          ] else ...[
            StatePill(
              mode.startsWith('Simulation') ? 'Demo hub' : 'Connected hub',
              icon: Icons.hub_outlined,
            ),
            Row(
              children: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final health = await client!.connect();
                          await refresh();
                          if (mounted) {
                            setState(() {
                              mode = health['mode'] == 'simulation'
                                  ? 'Simulation — no physical writes'
                                  : 'Live hub — controls real lights';
                              status =
                                  'Refreshed. MQTT: ${(health['mqtt'] as Map?)?['state'] ?? 'unknown'}.';
                            });
                          }
                        }),
                  child: const Text('Refresh'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          client!.close();
                          setState(() {
                            client = null;
                            lights = [];
                            groups = [];
                            scenes = [];
                            memberResults = [];
                            selected = null;
                            status =
                                'Disconnected. Lights keep their last setting.';
                          });
                        },
                  child: const Text('Disconnect'),
                ),
              ],
            ),
            if (client!.canEditLibrary)
              TextButton(
                onPressed: busy ? null : editHubLibrary,
                child: const Text('Edit rooms & scenes'),
              ),
            if (memberResults.isNotEmpty)
              ExpansionTile(
                key: ValueKey(memberResults),
                initiallyExpanded: memberResults.any(
                  (member) => member['status'] != 'succeeded',
                ),
                title: const Text('Last group or scene result'),
                children: memberResults.map((member) {
                  final target = lights.where(
                    (l) => l['id'] == member['target_id'],
                  );
                  final name = target.isEmpty
                      ? member['target_id']
                      : target.first['name'];
                  final outcome = member['status'] == 'succeeded'
                      ? (member['confirmation'] == 'simulated'
                            ? 'Simulated'
                            : 'Sent, unconfirmed')
                      : member['status'] == 'cancelled'
                      ? 'Cancelled'
                      : 'Failed or uncertain';
                  return ListTile(
                    title: Text(name),
                    subtitle: Text(outcome),
                    leading: Icon(
                      member['status'] == 'succeeded'
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                    ),
                  );
                }).toList(),
              ),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Hub groups',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ...groups.map(
                (group) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group['name'],
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text('${(group['members'] as List).length} lights'),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              key: Key('hub-group-${group['id']}-on'),
                              onPressed: busy
                                  ? null
                                  : () => sendTo('groups', group['id'], {
                                      'power': true,
                                    }),
                              child: const Text('All on'),
                            ),
                            OutlinedButton(
                              key: Key('hub-group-${group['id']}-off'),
                              onPressed: busy
                                  ? null
                                  : () => sendTo('groups', group['id'], {
                                      'power': false,
                                    }),
                              child: const Text('All off'),
                            ),
                            TextButton(
                              key: Key('hub-group-${group['id']}-controls'),
                              onPressed: busy
                                  ? null
                                  : () => controlGroup(group),
                              child: const Text('Color & effects'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (scenes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Hub scenes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ...scenes.map(
                (scene) => Card(
                  child: ListTile(
                    title: Text(scene['name']),
                    subtitle: Text(
                      '${(scene['actions'] as List).length} lights',
                    ),
                    trailing: FilledButton.tonal(
                      key: Key('hub-scene-${scene['id']}'),
                      onPressed: busy
                          ? null
                          : () => sendTo('scenes', scene['id'], {}),
                      child: const Text('Apply'),
                    ),
                  ),
                ),
              ),
            ],
            if (lights.isEmpty)
              const Text('No lights are configured on this hub.'),
            if (light != null) ...[
              DropdownButton<String>(
                isExpanded: true,
                value: selected,
                items: lights
                    .map(
                      (l) => DropdownMenuItem<String>(
                        value: l['id'],
                        child: Text(l['name']),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        selected = value;
                        status = 'Light selected. Nothing sent.';
                      }),
              ),
              Text(
                'Last sent: ${state['power'] == null
                    ? 'Unknown'
                    : state['power'] == true
                    ? 'On'
                    : 'Off'}${state['brightness'] == null ? '' : ' • ${state['brightness']}%'}${state['native_effect'] == 137 ? ' • Purple breathing' : ''}',
              ),
              if (gains != null)
                Text(
                  'Hub color balance: R${((gains[0] as num) * 100).round()}%  G${((gains[1] as num) * 100).round()}%  B${((gains[2] as num) * 100).round()}%',
                ),
              if (client!.canEditCalibration && caps['rgb'] == true)
                TextButton(
                  onPressed: busy ? null : editCalibration,
                  child: const Text('Edit hub color balance'),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => send({'power': true}),
                      child: const Text('On'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => send({'power': false}),
                      child: const Text('Off'),
                    ),
                  ),
                ],
              ),
              if (caps['brightness'] == true) ...[
                Text('Brightness: ${brightness.round()}%'),
                Slider(
                  value: brightness,
                  min: 1,
                  max: 100,
                  divisions: 99,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => brightness = v),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => send({
                          'power': true,
                          'brightness': brightness.round(),
                        }),
                  child: const Text('Apply brightness'),
                ),
              ],
              if (caps['rgb'] == true) ...[
                LightColorPicker(
                  rgb: rgb,
                  enabled: !busy,
                  onChanged: (v) => setState(() => rgb = v),
                  onValidityChanged: (v) => setState(() => validColor = v),
                ),
                FilledButton(
                  onPressed: busy || !validColor
                      ? null
                      : () => send({
                          'power': true,
                          'rgb': rgb,
                          'brightness': caps['brightness'] == true
                              ? brightness.round()
                              : 100,
                        }),
                  child: const Text('Apply color'),
                ),
              ],
              if (caps['native_effects'] == true)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => send({
                          'effect': 137,
                          'speed': 35,
                          'brightness': brightness.round(),
                        }, native: true),
                  child: const Text('Start Purple breathing'),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
