import 'package:flutter/material.dart';

import 'color_picker.dart';

class HubGroupCommand {
  const HubGroupCommand(this.body, {this.native = false});
  final Map<String, dynamic> body;
  final bool native;
}

/// Preview only: the caller submits the returned command after the sheet closes.
class HubGroupControls extends StatefulWidget {
  const HubGroupControls({
    super.key,
    required this.group,
    required this.lights,
  });
  final Map<String, dynamic> group;
  final List<Map<String, dynamic>> lights;

  @override
  State<HubGroupControls> createState() => _HubGroupControlsState();
}

class _HubGroupControlsState extends State<HubGroupControls> {
  List<int> rgb = [255, 147, 41];
  double brightness = 50;
  bool validColor = true, submitted = false;

  bool supports(String capability) {
    final members = widget.group['members'] as List;
    return members.isNotEmpty &&
        members.every((id) {
          final matches = widget.lights.where((light) => light['id'] == id);
          return matches.length == 1 &&
              (matches.single['capabilities'] as Map?)?[capability] == true;
        });
  }

  void apply(Map<String, dynamic> body, {bool native = false}) {
    if (submitted) return;
    submitted = true;
    Navigator.pop(context, HubGroupCommand(body, native: native));
  }

  @override
  Widget build(BuildContext context) {
    final color = supports('rgb');
    final dim = supports('brightness');
    final effects = supports('native_effects');
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.group['name'],
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('${(widget.group['members'] as List).length} lights'),
            const Text('Preview · applies to the whole group'),
            const SizedBox(height: 16),
            if (dim) ...[
              Text('Brightness: ${brightness.round()}%'),
              Slider(
                key: const Key('hub-group-brightness'),
                value: brightness,
                min: 1,
                max: 100,
                divisions: 99,
                onChanged: (value) => setState(() => brightness = value),
              ),
              OutlinedButton(
                key: const Key('hub-group-apply-brightness'),
                onPressed: () =>
                    apply({'power': true, 'brightness': brightness.round()}),
                child: const Text('Apply brightness'),
              ),
              const Text('Keeps each light’s saved color or effect.'),
            ],
            if (color) ...[
              LightColorPicker(
                rgb: rgb,
                onChanged: (value) => setState(() => rgb = value),
                onValidityChanged: (value) =>
                    setState(() => validColor = value),
              ),
              FilledButton(
                key: const Key('hub-group-apply-color'),
                onPressed: validColor
                    ? () => apply({
                        'power': true,
                        'rgb': List<int>.of(rgb),
                        'brightness': dim ? brightness.round() : 100,
                      })
                    : null,
                child: const Text('Apply color'),
              ),
            ],
            if (effects)
              OutlinedButton(
                key: const Key('hub-group-apply-effect'),
                onPressed: () => apply({
                  'effect': 137,
                  'speed': 35,
                  'brightness': dim ? brightness.round() : 100,
                }, native: true),
                child: const Text('Purple breathing'),
              ),
            if (!color || !dim || !effects)
              const Text('Showing controls shared by all lights.'),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
