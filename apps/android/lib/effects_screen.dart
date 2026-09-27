import 'package:flutter/material.dart';

import 'effects.dart';
import 'native_effects.dart';
import 'home_library.dart';
import 'light_backend.dart';
import 'settings.dart';

class EffectsScreen extends StatefulWidget {
  const EffectsScreen({
    super.key,
    required this.lights,
    required this.backend,
    required this.settings,
    required this.previous,
    required this.demo,
    required this.onDelivered,
    required this.onFailed,
    this.showNativeShortcut = true,
  });
  final bool showNativeShortcut;
  final List<Light> lights;
  final LightBackend backend;
  final Map<String, LightSettings> settings;
  final Map<String, SceneState> previous;
  final bool demo;
  final Future<void> Function(Light, SceneState) onDelivered;
  final void Function(String) onFailed;
  @override
  State<EffectsScreen> createState() => _EffectsScreenState();
}

class _EffectsScreenState extends State<EffectsScreen>
    with WidgetsBindingObserver {
  late final runner = EffectRunner(backend: widget.backend);
  late final Map<String, SceneState> previous = Map.of(widget.previous);
  EffectKind kind = EffectKind.breathing;
  String palette = 'Aurora';
  double seconds = 30, intensity = 0.7;
  bool busy = false, stopping = false, restore = false;
  String message =
      'Choose an effect, then Start. Effects turn the selected lights on.';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    runner.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && busy) {
      runner.stop();
      if (mounted) setState(() => stopping = true);
    }
  }

  Future<void> start() async {
    setState(() {
      busy = true;
      stopping = false;
      message = 'Starting…';
    });
    final statusClock = Stopwatch()..start();
    var lastStatusMs = -1000;
    try {
      await runner.start(
        lights: widget.lights,
        spec: EffectSpec(
          kind: kind,
          palette: effectPalettes[palette]!,
          period: Duration(seconds: seconds.round()),
          intensity: intensity,
        ),
        settings: widget.settings,
        previous: previous,
        onUpdate: () {
          if (mounted &&
              (!runner.running ||
                  statusClock.elapsedMilliseconds - lastStatusMs >= 1000)) {
            lastStatusMs = statusClock.elapsedMilliseconds;
            setState(
              () => message = stopping
                  ? 'Finishing the current transaction…'
                  : '${runner.writes} color updates sent • physical output unconfirmed',
            );
          }
        },
      );
      for (final light in widget.lights) {
        final state = runner.lastStates[light.id];
        if (runner.errors.containsKey(light.id)) {
          previous.remove(light.id);
          widget.onFailed(light.id);
        } else if (state != null) {
          previous[light.id] = state;
          try {
            await widget.onDelivered(light, state);
          } catch (_) {
            runner.errors[light.id] =
                'Delivered, but last color could not be saved';
          }
        }
      }
      if (mounted) {
        setState(
          () => message = runner.errors.isEmpty
              ? 'Effect stopped. No further updates are queued.'
              : 'Effect stopped with ${runner.errors.length} light error(s).',
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = 'Could not run effect: $e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          stopping = false;
        });
      }
    }
  }

  String name(Light light) {
    final alias = widget.settings[light.id]?.name;
    return alias != null && alias.isNotEmpty ? alias : light.name;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.demo ? 'Effects • Demo' : 'Effects'),
        leading: BackButton(
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: stopping
                ? null
                : busy
                ? () {
                    setState(() => stopping = true);
                    runner.stop(restore: restore);
                  }
                : start,
            icon: Icon(busy ? Icons.stop : Icons.play_arrow),
            label: Text(
              stopping
                  ? 'Stopping…'
                  : busy
                  ? 'Stop effect'
                  : 'Start effect',
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.lights.map(name).join(', '),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (widget.showNativeShortcut &&
                !widget.demo &&
                widget.lights.length == 1 &&
                widget.lights.single.profile['prefix'] == 'KS03~')
              FilledButton.tonal(
                onPressed: busy
                    ? null
                    : () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => NativeEffectsScreen(
                              light: widget.lights.single,
                              backend: widget.backend,
                              onChanged: () {
                                previous.remove(widget.lights.single.id);
                                widget.onFailed(widget.lights.single.id);
                              },
                            ),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                child: const Text('On-light effects'),
              ),
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(message)),
            const SizedBox(height: 12),
            DropdownButtonFormField<EffectKind>(
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Effect'),
              items: [
                for (final entry in effectNames.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: busy ? null : (v) => setState(() => kind = v!),
            ),
            if ([
              EffectKind.breathing,
              EffectKind.drift,
              EffectKind.wave,
            ].contains(kind))
              DropdownButtonFormField<String>(
                initialValue: palette,
                decoration: const InputDecoration(labelText: 'Palette'),
                items: [
                  for (final name in effectPalettes.keys)
                    DropdownMenuItem(value: name, child: Text(name)),
                ],
                onChanged: busy ? null : (v) => setState(() => palette = v!),
              ),
            const SizedBox(height: 16),
            Text(
              kind == EffectKind.sunset
                  ? 'Duration: ${seconds.round()} seconds'
                  : 'Cycle: ${seconds.round()} seconds',
            ),
            Slider(
              value: seconds,
              min: 10,
              max: 120,
              divisions: 22,
              label: '${seconds.round()} s',
              onChanged: busy ? null : (v) => setState(() => seconds = v),
            ),
            Text('Intensity: ${(intensity * 100).round()}%'),
            Slider(
              value: intensity,
              min: 0.05,
              max: 1,
              divisions: 19,
              label: '${(intensity * 100).round()}%',
              onChanged: busy ? null : (v) => setState(() => intensity = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Restore previous settings when I stop'),
              subtitle: Text(
                '${previous.length}/${widget.lights.length} lights have known pre-effect settings. Others keep the final effect color.',
              ),
              value: restore,
              onChanged: busy ? null : (v) => setState(() => restore = v),
            ),
            const Text(
              'Foreground preview: about 6 color updates per second, with connections kept open for up to 4 lights. Larger groups update more slowly. Keep this screen open. Leaving the app stops new updates after the current transaction; it does not restore or switch the light off.',
            ),
            if (kind == EffectKind.sunset)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Sunset runs once and holds its final dim red.'),
              ),
            if (kind == EffectKind.wave)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Wave follows the saved member order. Group updates are sequential, not synchronized.',
                ),
              ),
            for (final entry in runner.errors.entries)
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(
                  name(widget.lights.firstWhere((l) => l.id == entry.key)),
                ),
                subtitle: Text(entry.value),
              ),
            if (runner.restoreSkipped.isNotEmpty)
              Text(
                'Restore skipped for ${runner.restoreSkipped.length} light(s) with unknown prior state.',
              ),
          ],
        ),
      ),
    ),
  );
}

Map<String, SceneState> effectSnapshots(
  List<Light> lights,
  Map<String, LightSettings> settings,
  Map<String, bool> powers,
) => {
  for (final light in lights)
    if (powers[light.id] == false)
      light.id: const SceneState(power: false)
    else if (powers[light.id] == true && settings[light.id]?.lastColor != null)
      light.id: SceneState(
        power: true,
        rgb: List.of(settings[light.id]!.lastColor!),
        brightness: settings[light.id]!.lastBrightness,
      ),
};
