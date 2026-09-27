import 'package:flutter/material.dart';

import 'settings.dart';

class CalibrationDialog extends StatefulWidget {
  const CalibrationDialog({super.key, required this.settings});
  final LightSettings settings;
  @override
  State<CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<CalibrationDialog> {
  late List<double> gains = List.of(widget.settings.gains);
  late Map<String, List<double>> presets = {
    for (final entry in widget.settings.presets.entries)
      entry.key: List.of(entry.value),
  };
  String? selected;
  String presetName = '';
  String? error;

  void addPreset() {
    final name = presetName.trim();
    setState(() {
      if (name.isEmpty) {
        error = 'Enter a preset name.';
        return;
      }
      if (presets.keys.any((key) => key.toLowerCase() == name.toLowerCase())) {
        error = 'That name exists. Choose a different name.';
        return;
      }
      if (presets.length >= 20) {
        error = 'Maximum 20 presets per light. Remove one first.';
        return;
      }
      presets[name] = List.of(gains);
      selected = 'saved:$name';
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Color balance'),
    content: SizedBox(
      width: 380,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Adjust the balance, save, then apply a color.'),
            const SizedBox(height: 12),
            DropdownButton<String>(
              isExpanded: true,
              value: selected,
              hint: const Text('Choose a calibration preset'),
              items: [
                for (final name in LightSettings.builtInPresets.keys)
                  DropdownMenuItem(value: 'built:$name', child: Text(name)),
                for (final name in presets.keys)
                  DropdownMenuItem(
                    value: 'saved:$name',
                    child: Text(
                      'Saved: $name',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                selected = value;
                gains = List.of(
                  value!.startsWith('built:')
                      ? LightSettings.builtInPresets[value.substring(6)]!
                      : presets[value.substring(6)]!,
                );
              }),
            ),
            for (var i = 0; i < 3; i++) ...[
              Text(
                '${['Red', 'Green', 'Blue'][i]} balance: ${(gains[i] * 100).round()}%',
              ),
              Slider(
                key: ValueKey('balance-$i'),
                value: gains[i],
                min: 0,
                max: 1,
                divisions: 100,
                semanticFormatterCallback: (v) =>
                    '${['Red', 'Green', 'Blue'][i]} balance ${(v * 100).round()} percent',
                onChanged: (value) => setState(() {
                  gains[i] = value;
                  selected = null;
                }),
              ),
            ],
            TextButton(
              onPressed: () => setState(() {
                gains = [1, 1, 1];
                selected = 'built:Neutral';
              }),
              child: const Text('Reset balance'),
            ),
            TextFormField(
              maxLength: 40,
              onChanged: (value) => presetName = value,
              decoration: InputDecoration(
                labelText: 'Preset name',
                errorText: error,
              ),
            ),
            TextButton.icon(
              onPressed: addPreset,
              icon: const Icon(Icons.add),
              label: const Text('Add preset'),
            ),
            if (selected?.startsWith('saved:') ?? false)
              TextButton.icon(
                onPressed: () => setState(() {
                  presets.remove(selected!.substring(6));
                  selected = null;
                }),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove selected preset'),
              ),
            const Text('Presets are saved for this light.'),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          LightSettings(
            name: widget.settings.name,
            order: widget.settings.order,
            gains: List.of(gains),
            presets: presets,
            lastColor: widget.settings.lastColor,
            lastBrightness: widget.settings.lastBrightness,
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}
