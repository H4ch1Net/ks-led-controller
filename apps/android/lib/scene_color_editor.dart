import 'package:flutter/material.dart';

import 'color_picker.dart';
import 'home_library.dart';
import 'light_backend.dart';

/// Edits a detached scene value. This screen has no transport or persistence.
class SceneColorEditor extends StatefulWidget {
  const SceneColorEditor({
    super.key,
    required this.light,
    required this.initial,
  });
  final Light light;
  final SceneState initial;
  @override
  State<SceneColorEditor> createState() => _SceneColorEditorState();
}

class _SceneColorEditorState extends State<SceneColorEditor> {
  late List<int> rgb = List.of(widget.initial.rgb ?? [255, 147, 41]);
  late double brightness = widget.initial.brightness.toDouble();
  bool valid = true, submitted = false;
  bool get dimmable => widget.light.profile['color_type'] == 'floor';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Scene color • ${widget.light.name}')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Preview only · lights stay unchanged'),
            LightColorPicker(
              rgb: rgb,
              onChanged: (value) => setState(() => rgb = value),
              onValidityChanged: (value) => setState(() => valid = value),
            ),
            if (dimmable) ...[
              Text('Brightness: ${(brightness * 100 / 255).round()}%'),
              Slider(
                key: const Key('scene-color-brightness'),
                value: brightness,
                min: 0,
                max: 255,
                divisions: 255,
                onChanged: (value) => setState(() => brightness = value),
              ),
            ] else
              const Text('This light supports color at full brightness.'),
            FilledButton(
              key: const Key('scene-color-use'),
              onPressed: !valid
                  ? null
                  : () {
                      if (submitted) return;
                      submitted = true;
                      Navigator.pop(
                        context,
                        SceneState(
                          power: widget.initial.power,
                          rgb: List.of(rgb),
                          brightness: dimmable ? brightness.round() : 255,
                        ),
                      );
                    },
              child: const Text('Use in scene'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
}
