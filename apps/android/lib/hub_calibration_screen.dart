import 'dart:convert';

import 'package:flutter/material.dart';

import 'hub_client.dart';
import 'settings.dart';

Map<String, List<double>> parseHubPresets(dynamic value) {
  if (value is! Map || value.length > 20) {
    throw const FormatException('Use up to 20 named presets.');
  }
  final result = <String, List<double>>{};
  for (final entry in value.entries) {
    if (entry.key is! String ||
        (entry.key as String).trim().isEmpty ||
        (entry.key as String).length > 40) {
      throw const FormatException('Preset names must be 1–40 characters.');
    }
    result[entry.key as String] = LightSettings.parseGains(entry.value);
  }
  return result;
}

Map<String, dynamic> parseHubCalibration(String text) {
  if (utf8.encode(text).length > 16384) {
    throw const FormatException('Calibration import is too large.');
  }
  final data = jsonDecode(text);
  if (data is! Map<String, dynamic> ||
      data.keys.any((key) => !['rgb_gains', 'presets'].contains(key))) {
    throw const FormatException(
      'Use a calibration object with rgb_gains and optional presets.',
    );
  }
  return {
    'rgb_gains': LightSettings.parseGains(data['rgb_gains']),
    'presets': parseHubPresets(data['presets'] ?? {}),
  };
}

class HubCalibrationScreen extends StatefulWidget {
  const HubCalibrationScreen({
    super.key,
    required this.client,
    required this.id,
    required this.name,
  });
  final HubClient client;
  final String id, name;
  @override
  State<HubCalibrationScreen> createState() => _HubCalibrationScreenState();
}

class _HubCalibrationScreenState extends State<HubCalibrationScreen> {
  List<double> gains = [1, 1, 1];
  Map<String, List<double>> presets = {}, builtIn = {};
  final presetName = TextEditingController();
  String? revision;
  String message = 'Loading hub color balance…';
  bool loading = true, saving = false, needsReload = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    presetName.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (saving) return;
    setState(() => loading = true);
    try {
      String? tag;
      final data = await widget.client.request(
        'GET',
        '/lights/${widget.id}/calibration',
        onRevision: (value) => tag = value,
      );
      final parsed = parseHubCalibration(jsonEncode(data['calibration']));
      final options = parseHubPresets(data['built_in_presets']);
      if (tag == null || !RegExp(r'^"[a-f0-9]{64}"$').hasMatch(tag!)) {
        throw const FormatException();
      }
      if (!mounted) return;
      setState(() {
        gains = parsed['rgb_gains'];
        presets = parsed['presets'];
        builtIn = options;
        revision = tag;
        needsReload = false;
        message = 'Changes stay here until you save. Saving does not change the lamp.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          needsReload = true;
          message = 'Could not load color balance. Check your hub and reload.';
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (saving || loading || needsReload || revision == null) return;
    setState(() => saving = true);
    try {
      await widget.client.request(
        'PUT',
        '/lights/${widget.id}/calibration',
        body: {'rgb_gains': gains, 'presets': presets},
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

  Future<void> importBalance() async {
    var text = '';
    String? error;
    final parsed = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Import color balance'),
          content: SingleChildScrollView(
            child: TextField(
              maxLines: 6,
              maxLength: 16384,
              decoration: InputDecoration(
                labelText: 'Calibration JSON',
                errorText: error,
                errorMaxLines: 4,
              ),
              onChanged: (value) => text = value,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(context, parseHubCalibration(text));
                } catch (_) {
                  update(
                    () => error = 'Use rgb_gains with three values from 0 to 1 and optional named presets.',
                  );
                }
              },
              child: const Text('Preview import'),
            ),
          ],
        ),
      ),
    );
    if (parsed != null && mounted) {
      setState(() {
        gains = parsed['rgb_gains'];
        presets = parsed['presets'];
        message = 'Imported into this preview. Save to replace the hub color balance and custom presets.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(title: Text('Color balance • ${widget.name}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(message),
          if (loading || saving) const LinearProgressIndicator(),
          if (!loading && !saving && !needsReload) ...[
            for (var index = 0; index < 3; index++) ...[
              Text(
                '${['Red', 'Green', 'Blue'][index]}: ${(gains[index] * 100).round()}%',
              ),
              Slider(
                key: Key('hub-gain-$index'),
                value: gains[index],
                divisions: 100,
                onChanged: (value) => setState(() => gains[index] = value),
              ),
            ],
            const Text('Presets'),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in builtIn.entries)
                  ActionChip(
                    label: Text(entry.key),
                    onPressed: () =>
                        setState(() => gains = List.of(entry.value)),
                  ),
              ],
            ),
            for (final entry in presets.entries)
              ListTile(
                title: Text(entry.key),
                onTap: () => setState(() => gains = List.of(entry.value)),
                trailing: IconButton(
                  tooltip: 'Remove preset',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => presets.remove(entry.key)),
                ),
              ),
            TextField(
              controller: presetName,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Custom preset name',
              ),
            ),
            TextButton(
              onPressed: () {
                final name = presetName.text.trim();
                if (name.isEmpty ||
                    (presets.length >= 20 && !presets.containsKey(name))) {
                  setState(
                    () => message =
                        'Enter a name; up to 20 custom presets can be saved.',
                  );
                  return;
                }
                setState(() {
                  presets[name] = List.of(gains);
                  message = 'Preset added to this preview. Save to keep it on the hub.';
                });
              },
              child: const Text('Keep current balance as preset'),
            ),
            TextButton(
              onPressed: importBalance,
              child: const Text('Import calibration JSON'),
            ),
            FilledButton(onPressed: save, child: const Text('Save to hub')),
          ],
          if (needsReload && !loading)
            TextButton(onPressed: load, child: const Text('Reload')),
        ],
      ),
    ),
  );
}
