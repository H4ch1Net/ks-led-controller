import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'hub_client.dart';

class HubLibraryScreen extends StatefulWidget {
  const HubLibraryScreen({
    super.key,
    required this.client,
    required this.lights,
  });
  final HubClient client;
  final List<Map<String, dynamic>> lights;
  @override
  State<HubLibraryScreen> createState() => _HubLibraryScreenState();
}

class _HubLibraryScreenState extends State<HubLibraryScreen> {
  Map<String, dynamic>? draft;
  String? revision;
  bool loading = true, saving = false, needsReload = false, editing = false;
  String message = 'Loading hub rooms and scenes…';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (saving) return;
    setState(() => loading = true);
    try {
      String? tag;
      final value = await widget.client.request(
        'GET',
        '/library',
        onRevision: (v) => tag = v,
      );
      if (value['version'] != 1 ||
          value['groups'] is! List ||
          value['scenes'] is! List ||
          tag == null ||
          !RegExp(r'^"[a-f0-9]{64}"$').hasMatch(tag!)) {
        throw const FormatException();
      }
      if (!mounted) return;
      for (final kind in ['groups', 'scenes']) {
        final entries = value[kind] as List;
        if (entries.length > 32) throw const FormatException();
        final ids = <String>{};
        for (final entry in entries) {
          if (entry is! Map<String, dynamic> ||
              entry['id'] is! String ||
              !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(entry['id']) ||
              !ids.add(entry['id']) ||
              entry['name'] is! String ||
              (entry['name'] as String).trim().isEmpty ||
              (entry['name'] as String).length > 80) {
            throw const FormatException();
          }
          final members = entry[kind == 'groups' ? 'members' : 'actions'];
          if (members is! List || members.isEmpty || members.length > 64) {
            throw const FormatException();
          }
          final targets = <String>{};
          for (final member in members) {
            if (kind == 'scenes' &&
                (member is! Map<String, dynamic> ||
                    member['body'] is! Map ||
                    !['state', 'native'].contains(member['type']))) {
              throw const FormatException();
            }
            final target = kind == 'groups' ? member : member['light'];
            if (target is! String ||
                !targets.add(target) ||
                !widget.lights.any((light) => light['id'] == target)) {
              throw const FormatException();
            }
          }
        }
      }
      setState(() {
        draft = value;
        revision = tag;
        needsReload = false;
        message = 'Edit your hub library, then save. Editing never changes the lights.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          needsReload = true;
          message = 'Could not load the hub library. Reload before editing.';
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Map<String, dynamic> snapshot(String id, bool on) {
    final light = widget.lights.firstWhere((light) => light['id'] == id);
    final state = light['last_sent'] as Map? ?? {};
    if (!on) {
      return {
        'light': id,
        'type': 'state',
        'body': {'power': false},
      };
    }
    if (state['native_effect'] != null) {
      return {
        'light': id,
        'type': 'native',
        'body': {
          'effect': state['native_effect'],
          'speed': state['speed'],
          'brightness': state['brightness'],
        },
      };
    }
    return {
      'light': id,
      'type': 'state',
      'body': {
        'power': true,
        if (state['rgb'] != null) 'rgb': state['rgb'],
        if (state['rgb'] != null) 'brightness': state['brightness'] ?? 100,
      },
    };
  }

  Future<void> edit(String kind, [Map<String, dynamic>? existing]) async {
    if (editing || saving || loading || needsReload) return;
    editing = true;
    final scene = kind == 'scenes';
    var name = existing?['name'] as String? ?? '';
    final oldActions = <String, Map<String, dynamic>>{
      for (final action in existing?['actions'] as List? ?? [])
        action['light'] as String: Map<String, dynamic>.from(action as Map),
    };
    final selected = <String>{
      if (scene)
        ...oldActions.keys
      else
        ...((existing?['members'] as List?) ?? []).cast<String>(),
    };
    final powers = {
      for (final entry in oldActions.entries)
        entry.key: (entry.value['body'] as Map)['power'] != false,
    };
    var recapture = false;
    String? error;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(scene ? 'Hub scene' : 'Hub group'),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: name,
                      maxLength: 80,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        errorText: error,
                      ),
                      onChanged: (value) => name = value.trim(),
                    ),
                    if (scene)
                      const Text(
                        'New entries use each light’s last hub color or effect. Without a saved setting, they only turn on.',
                      ),
                    if (scene && existing != null)
                      SwitchListTile(
                        title: const Text('Use latest hub settings'),
                        value: recapture,
                        onChanged: (value) => update(() => recapture = value),
                      ),
                    for (final light in widget.lights) ...[
                      CheckboxListTile(
                        title: Text(light['name']),
                        value: selected.contains(light['id']),
                        onChanged: (value) => update(() {
                          if (value!) {
                            selected.add(light['id']);
                          } else {
                            selected.remove(light['id']);
                          }
                        }),
                      ),
                      if (scene && selected.contains(light['id']))
                        SwitchListTile(
                          title: Text(
                            (powers[light['id']] ?? true)
                                ? 'Turn on'
                                : 'Turn off',
                          ),
                          value: powers[light['id']] ?? true,
                          onChanged: (value) =>
                              update(() => powers[light['id']] = value),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (name.isEmpty ||
                      selected.isEmpty ||
                      selected.length > 64) {
                    update(
                      () => error = 'Enter a name and choose 1–64 lights.',
                    );
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('Keep changes'),
              ),
            ],
          ),
        ),
      );
      if (accepted != true || !mounted) return;
      final entries = List<Map<String, dynamic>>.from(draft![kind] as List);
      if (existing == null && entries.length >= 32) {
        setState(
          () => message = 'The hub supports up to 32 groups and 32 scenes.',
        );
        return;
      }
      final id =
          existing?['id'] ??
          'app_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}';
      final definition = <String, dynamic>{
        'id': id,
        'name': name,
        if (!scene)
          'members': selected.toList()
        else
          'actions': [
            for (final target in selected)
              if (recapture ||
                  oldActions[target] == null ||
                  powers[target] == false ||
                  (oldActions[target]!['body'] as Map)['power'] == false)
                snapshot(target, powers[target] ?? true)
              else
                oldActions[target]!,
          ],
      };
      final index = entries.indexWhere((entry) => entry['id'] == id);
      if (index < 0) {
        entries.add(definition);
      } else {
        entries[index] = definition;
      }
      setState(() {
        draft![kind] = entries;
        message = 'Changes are in this preview. Save to update the hub.';
      });
    } finally {
      editing = false;
    }
  }

  Future<void> save() async {
    if (saving || loading || needsReload || draft == null || revision == null) {
      return;
    }
    if (utf8.encode(jsonEncode(draft)).length > 16384) {
      setState(
        () => message = 'This library exceeds the app’s 16 KiB save limit. Use the hub configuration file.',
      );
      return;
    }
    setState(() => saving = true);
    try {
      await widget.client.request(
        'PUT',
        '/library',
        body: draft,
        ifMatch: revision,
      );
      if (mounted) {
        setState(() => saving = false);
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          saving = false;
          needsReload = true;
          message =
              '${error is HubError ? error.message : 'Could not confirm the save.'} Reload before editing again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('Hub rooms & scenes')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(message),
          if (loading || saving) const LinearProgressIndicator(),
          if (draft != null && !loading && !saving && !needsReload) ...[
            for (final kind in ['groups', 'scenes']) ...[
              Text(
                kind == 'groups' ? 'Groups' : 'Scenes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final entry in draft![kind] as List)
                ListTile(
                  title: Text(entry['name']),
                  onTap: () =>
                      edit(kind, Map<String, dynamic>.from(entry as Map)),
                  trailing: IconButton(
                    tooltip: 'Remove from draft',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() {
                      (draft![kind] as List).remove(entry);
                      message =
                          'Removed from this preview. Save to update the hub.';
                    }),
                  ),
                ),
              TextButton(
                onPressed: () => edit(kind),
                child: Text(kind == 'groups' ? 'Add group' : 'Add scene'),
              ),
            ],
            FilledButton(
              onPressed: save,
              child: const Text('Save library to hub'),
            ),
          ],
          if (needsReload && !loading)
            TextButton(onPressed: load, child: const Text('Reload')),
        ],
      ),
    ),
  );
}
