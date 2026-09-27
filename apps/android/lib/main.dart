import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'light_backend.dart';
import 'protocol.dart';
import 'settings.dart';
import 'calibration_dialog.dart';
import 'color_picker.dart';
import 'home_library.dart';
import 'library_screen.dart';
import 'effects_screen.dart';
import 'native_effects.dart';
import 'hub_screen.dart';
import 'diagnostics_screen.dart';

void main() => runApp(const KsLightApp());

class KsLightApp extends StatelessWidget {
  const KsLightApp({super.key, this.backend, this.settingsStore});
  final SettingsStore? settingsStore;
  final LightBackend? backend;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'KS Light',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff8da6ff),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: LightScreen(testBackend: backend, settingsStore: settingsStore),
  );
}

class LightScreen extends StatefulWidget {
  const LightScreen({super.key, this.testBackend, this.settingsStore});
  final SettingsStore? settingsStore;
  final LightBackend? testBackend;
  @override
  State<LightScreen> createState() => _LightScreenState();
}

class _LightScreenState extends State<LightScreen> {
  late LightBackend backend;
  bool demo = true, busy = false;
  String message = 'Demo mode. No real lights will be changed.';
  List<Light> lights = [];
  Light? selected;
  String? defaultLightId;
  int deviceLoadGeneration = 0;
  List<int> rgb = [255, 147, 41];
  int brightness = 255;
  bool colorPending = true, colorValid = true;
  final Map<String, List<int>> remembered = {};
  final Map<String, bool> powerStates = {};
  Map<String, LightSettings> settings = {};
  bool settingsReady = false;
  late final SettingsStore store;
  LightSettings config(Light light) =>
      settings[light.id] ?? const LightSettings();
  String displayName(Light light) =>
      config(light).name.isEmpty ? light.name : config(light).name;
  @override
  void initState() {
    super.initState();
    backend = widget.testBackend ?? DemoBackend();
    store = widget.settingsStore ?? SettingsStore();
    loadSettings();
  }

  Future<void> configureShortcuts() async {
    final light = selected;
    if (demo || light == null || light.profile['prefix'] != 'KS03~') return;
    await perform(() async {
      if (backend is BluetoothBackend) {
        await (backend as BluetoothBackend).permissions();
      }
      const channel = MethodChannel('dev.kslight/settings');
      await channel.invokeMethod<void>('configureShortcuts', {
        'id': light.id,
        'name': displayName(light),
      });
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Quick controls ready'),
          content: Text(
            'New widgets and the tile can control ${displayName(light)} directly over Bluetooth. Existing widgets keep their own device; tap a widget name to change it. The tile toggles last-sent power, not verified lamp state. Stop active effects before using shortcuts. On Android 11+, you can also choose KS Light in the system Device controls panel and add this light.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'widget'),
              child: const Text('Add widget'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'tile'),
              child: const Text('Add quick tile'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'deviceControl'),
              child: const Text('Add device control'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (action != null) {
        final supported = await channel.invokeMethod<bool>(
          action == 'widget'
              ? 'pinWidget'
              : action == 'tile'
              ? 'addTile'
              : 'addDeviceControl',
        );
        if (mounted) {
          setState(
            () => message = supported == true
                ? 'Finish adding the shortcut in Android.'
                : 'Add KS Light through Android’s widget or Quick Settings editor.',
          );
        }
      }
    });
  }

  Future<void> loadSettings() async {
    try {
      final loaded = await store.load();
      if (mounted) {
        setState(() {
          settings = loaded;
          settingsReady = true;
        });
        await loadDevices(startup: true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Saved names and color balance could not be loaded. Restart to retry.',
        );
      }
    }
  }

  Future<void> loadDevices({bool startup = false}) async {
    final generation = ++deviceLoadGeneration;
    try {
      final profiles = (jsonDecode(
        await rootBundle.loadString('assets/profiles.json'),
      ) as List).cast<Map<String, dynamic>>();
      final libraryStore = HomeLibraryStore();
      var mode = demo;
      var library = await libraryStore.load(mode);
      if (startup && widget.testBackend == null) {
        final real = await libraryStore.load(false);
        if (real.defaultLightId != null) {
          mode = false;
          library = real;
        }
      }
      if (!mounted || generation != deviceLoadGeneration) return;
      final saved = library.lights.keys
          .map((id) => library.resolve(id, profiles))
          .toList();
      setState(() {
        if (mode != demo) {
          demo = mode;
          backend = mode ? DemoBackend() : BluetoothBackend();
        }
        lights = saved;
        defaultLightId = library.defaultLightId;
      });
      if (defaultLightId != null) {
        select(saved.firstWhere((light) => light.id == defaultLightId));
        setState(() => message = 'Default light ready. No command sent.');
      }
    } catch (_) {
      if (mounted && generation == deviceLoadGeneration) {
        setState(
          () => message = 'Saved devices could not be loaded. Scan to retry.',
        );
      }
    }
  }

  Future<void> setDefaultDevice(Light light) => perform(() async {
    final libraryStore = HomeLibraryStore();
    final library = await libraryStore.load(demo);
    library.remember([light]);
    library.defaultLightId = library.defaultLightId == light.id
        ? null
        : light.id;
    await libraryStore.save(demo, library);
    if (mounted) {
      setState(() {
        defaultLightId = library.defaultLightId;
        message = defaultLightId == null
            ? 'Default cleared.'
            : '${displayName(light)} is your default light.';
      });
    }
  });

  Future<void> removeDevice(Light light) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${displayName(light)}?'),
        content: const Text(
          'Remove this saved device and its room/group/scene memberships. Empty rooms, groups and scenes are removed too. Its default and quick controls are cleared. Color balance is kept for re-adding later. This does not turn the light off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await perform(() async {
      final libraryStore = HomeLibraryStore();
      final library = await libraryStore.load(demo);
      library.forget(light.id);
      await libraryStore.save(demo, library);
      if (!mounted) return;
      setState(() {
        lights.removeWhere((item) => item.id == light.id);
        if (selected?.id == light.id) selected = null;
        defaultLightId = library.defaultLightId;
        remembered.remove(light.id);
        powerStates.remove(light.id);
        message = 'Device removed. Use Add devices to find it again.';
      });
    });
  }

  Future<void> editSettings({bool calibration = false}) async {
    final light = selected!;
    final previous = config(light);
    var name = previous.name;
    final result = await showDialog<LightSettings>(
      context: context,
      builder: (context) => calibration
          ? CalibrationDialog(settings: previous)
          : AlertDialog(
              title: const Text('Rename light'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: name,
                      onChanged: (value) => name = value,
                      maxLength: 40,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        hintText: light.name,
                      ),
                    ),
                    const Text(
                      'Leave blank to use the Bluetooth name. Saved on this phone.',
                    ),
                  ],
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
                      name: name.trim(),
                      order: previous.order,
                      gains: previous.gains,
                      presets: previous.presets,
                      lastColor: previous.lastColor,
                      lastBrightness: previous.lastBrightness,
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
    );
    if (result == null || !mounted) return;
    await perform(() async {
      final next = {...settings, light.id: result};
      await store.save(next);
      if (mounted) {
        setState(() {
          settings = next;
          if (calibration) colorPending = true;
          message = calibration
              ? 'Color balance saved. Apply color to test it.'
              : 'Light name saved on this phone.';
        });
      }
    });
  }

  void failedTarget(String id) {
    if (mounted) {
      setState(() {
        powerStates.remove(id);
        if (selected?.id == id) colorPending = true;
      });
    }
  }

  Future<void> deliveredState(Light light, SceneState state) async {
    if (!mounted) return;
    setState(() {
      powerStates[light.id] = state.power;
      if (state.power && state.rgb != null) {
        remembered[light.id] = [...state.rgb!, state.brightness];
        settings = {
          ...settings,
          light.id: config(light).withColor(state.rgb!, state.brightness),
        };
        if (selected?.id == light.id) {
          rgb = List.of(state.rgb!);
          brightness = state.brightness;
          colorPending = false;
          colorValid = true;
        }
      }
    });
    if (state.power && state.rgb != null) await store.save(settings);
  }

  Future<void> openLibrary() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LibraryScreen(
          demo: demo,
          discovered: lights,
          backend: backend,
          settings: settings,
          powers: Map.of(powerStates),
          onFailed: failedTarget,
          onDelivered: deliveredState,
        ),
      ),
    );
  }

  Future<void> openEffects() async {
    final target = selected!;
    Widget custom(BuildContext context) => EffectsScreen(
      showNativeShortcut: false,
      lights: [target],
      backend: backend,
      settings: settings,
      demo: demo,
      previous: effectSnapshots([target], settings, powerStates),
      onDelivered: deliveredState,
      onFailed: failedTarget,
    );
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => !demo && target.profile['prefix'] == 'KS03~'
            ? NativeEffectsScreen(
                light: target,
                backend: backend,
                onChanged: () => failedTarget(target.id),
                customBuilder: custom,
              )
            : custom(context),
      ),
    );
  }

  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = 'Working…';
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => message = 'Could not complete: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> scan() => perform(() async {
    final raw =
        jsonDecode(await rootBundle.loadString('assets/profiles.json')) as List;
    deviceLoadGeneration++;
    final result = await backend.scan(raw.cast<Map<String, dynamic>>());
    if (!mounted) return;
    setState(() {
      lights = {
        ...{for (final light in lights) light.id: light},
        ...{for (final light in result) light.id: light},
      }.values.toList();
      selected = null;
      message = result.isEmpty
          ? 'No KS lights found. Move closer and scan again.'
          : 'Devices saved. Choose a light to control.';
    });
    try {
      final libraryStore = HomeLibraryStore();
      final library = await libraryStore.load(demo);
      library.remember(result);
      await libraryStore.save(demo, library);
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Scan complete, but saved rooms/scenes could not be updated.',
        );
      }
    }
  });
  Future<void> send(bool? power) => perform(() async {
    final light = selected!;
    final packets = power == null
        ? [
            powerPacket(true),
            colorPacket(
              config(light).apply(rgb),
              light.profile['color_type'] as String,
              deviceBrightness(brightness, light.profile['prefix'] as String),
            ),
          ]
        : [powerPacket(power)];
    try {
      await backend.send(light, packets);
    } catch (_) {
      // A partial transaction may have reached the light before the failure.
      if (mounted) {
        setState(() {
          powerStates.remove(light.id);
          colorPending = true;
        });
      }
      rethrow;
    }
    if (!mounted) return;
    setState(() {
      powerStates[light.id] = power ?? true;
      if (power == null) {
        remembered[light.id] = [...rgb, brightness];
        colorPending = false;
      }
      message = demo
          ? 'Demo command applied. No Bluetooth writes.'
          : 'Command sent. Physical light state is unconfirmed.';
    });
    if (power == null) {
      final next = {
        ...settings,
        light.id: config(light).withColor(rgb, brightness),
      };
      try {
        await store.save(next);
        if (mounted) setState(() => settings = next);
      } catch (_) {
        if (mounted) {
          setState(
            () => message =
                'Color sent, but could not remember it for next time.',
          );
        }
      }
    }
  });
  void select(Light light) => setState(() {
    selected = light;
    final saved = config(light);
    final previous =
        remembered[light.id] ??
        [
          ...(saved.lastColor ?? [255, 147, 41]),
          saved.lastBrightness,
        ];
    colorPending = true;
    colorValid = true;
    rgb = previous.take(3).toList();
    brightness = previous[3];
    message = 'Choose a color, then tap Apply.';
  });
  @override
  Widget build(BuildContext context) {
    final colorType = selected?.profile['color_type'];
    return Scaffold(
      appBar: AppBar(
        title: const Text('KS Light • Prototype'),
        actions: [
          IconButton(
            tooltip: 'Connection help',
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    DiagnosticsScreen(demo: demo, savedLights: lights.length),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Hub control',
            icon: const Icon(Icons.hub_outlined),
            onPressed: busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const HubScreen()),
                  ),
          ),
          IconButton(
            tooltip: 'Rooms & scenes',
            icon: const Icon(Icons.dashboard_customize_outlined),
            onPressed: busy || !settingsReady ? null : openLibrary,
          ),
        ],
      ),
      bottomNavigationBar: colorType == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color.fromARGB(255, rgb[0], rgb[1], rgb[2]),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${colorHex(rgb)} • ${colorPending ? 'Not applied' : 'Color sent'}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: busy || !settingsReady || !colorValid
                            ? null
                            : () => send(null),
                        icon: const Icon(Icons.check),
                        label: Text(
                          busy ? 'Sending…' : 'Apply color & turn on',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (selected == null) ...[
              SwitchListTile(
                title: const Text('Demo mode'),
                subtitle: Text(
                  demo
                      ? 'Virtual light • no Bluetooth'
                      : 'Nearby Bluetooth lights',
                ),
                value: demo,
                onChanged: busy || widget.testBackend != null
                    ? null
                    : (value) {
                        setState(() {
                          demo = value;
                          backend = value ? DemoBackend() : BluetoothBackend();
                          lights = [];
                          selected = null;
                          remembered.clear();
                          powerStates.clear();
                          message = value
                              ? 'Demo mode enabled.'
                              : 'Scan to request Bluetooth access.';
                          defaultLightId = null;
                        });
                        loadDevices();
                      },
              ),
              FilledButton.icon(
                onPressed: busy ? null : scan,
                icon: const Icon(Icons.search),
                label: Text(
                  busy
                      ? 'Working…'
                      : lights.isEmpty
                      ? 'Scan for lights'
                      : 'Add devices',
                ),
              ),
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(message)),
              if (lights.isNotEmpty)
                const Text('Saved devices • tap a star to choose your default'),
              for (final light in lights)
                ListTile(
                  leading: const Icon(Icons.lightbulb_outline),
                  title: Text(displayName(light)),
                  subtitle: Text(light.id),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: defaultLightId == light.id
                            ? 'Clear default device'
                            : 'Set as default device',
                        icon: Icon(
                          defaultLightId == light.id
                              ? Icons.star
                              : Icons.star_border,
                        ),
                        onPressed: busy ? null : () => setDefaultDevice(light),
                      ),
                      IconButton(
                        tooltip: 'Remove device',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: busy ? null : () => removeDevice(light),
                      ),
                    ],
                  ),
                  selected: selected?.id == light.id,
                  onTap: busy ? null : () => select(light),
                ),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => setState(() => selected = null),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(
                    demo ? 'Change light • Demo mode' : 'Change light',
                  ),
                ),
              ),
            if (selected != null) ...[
              Semantics(liveRegion: true, child: Text(message)),
              TextButton.icon(
                onPressed: busy ? null : () => setDefaultDevice(selected!),
                icon: Icon(
                  defaultLightId == selected!.id
                      ? Icons.star
                      : Icons.star_border,
                ),
                label: Text(
                  defaultLightId == selected!.id
                      ? 'Default device • tap to clear'
                      : 'Set as default device',
                ),
              ),
              Text(
                displayName(selected!),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: busy || !settingsReady
                        ? null
                        : () => editSettings(),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Rename'),
                  ),
                  if (colorType != null)
                    TextButton.icon(
                      onPressed: busy || !settingsReady
                          ? null
                          : () => editSettings(calibration: true),
                      icon: const Icon(Icons.tune),
                      label: const Text('Color balance'),
                    ),
                ],
              ),
              if (colorType != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: busy || !settingsReady ? null : openEffects,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Effects'),
                  ),
                ),
              Text(
                powerStates[selected!.id] == null
                    ? 'Power: unknown'
                    : 'Last sent: ${powerStates[selected!.id]! ? 'On' : 'Off'}',
              ),
              const Text('Changes from another controller are not tracked.'),
              if (!demo && selected!.profile['prefix'] == 'KS03~')
                TextButton.icon(
                  onPressed: busy ? null : configureShortcuts,
                  icon: const Icon(Icons.widgets_outlined),
                  label: const Text('Widget & Quick Settings'),
                ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('On'),
                    icon: Icon(Icons.power_settings_new),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Off'),
                    icon: Icon(Icons.power_off),
                  ),
                ],
                emptySelectionAllowed: true,
                selected: {
                  if (powerStates[selected!.id] != null)
                    powerStates[selected!.id]!,
                },
                onSelectionChanged: busy
                    ? null
                    : (values) => send(
                        values.isEmpty
                            ? powerStates[selected!.id]!
                            : values.single,
                      ),
              ),
              if (!settingsReady)
                const Text(
                  'Saved settings unavailable. Color controls require saved settings to load; restart to retry.',
                ),
              if (colorType != null) ...[
                const SizedBox(height: 16),
                LightColorPicker(
                  key: ValueKey(selected!.id),
                  rgb: rgb,
                  enabled: !busy,
                  onValidityChanged: (valid) =>
                      setState(() => colorValid = valid),
                  onChanged: (value) => setState(() {
                    rgb = value;
                    colorPending = true;
                  }),
                ),
                Text(
                  'Active balance: R${(config(selected!).gains[0] * 100).round()}%  G${(config(selected!).gains[1] * 100).round()}%  B${(config(selected!).gains[2] * 100).round()}%',
                ),
                const Text(
                  'Screen colors are an approximate reference for the light.',
                ),
                if (colorType == 'floor') ...[
                  Text('Brightness: ${(brightness * 100 / 255).round()}%'),
                  Slider(
                    value: brightness.toDouble(),
                    min: 0,
                    max: 255,
                    divisions: 255,
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            brightness = v.round();
                            colorPending = true;
                          }),
                  ),
                ],
              ] else
                const Text('This profile has inherited power commands only.'),
              const SizedBox(height: 12),
              const Text(
                'Prototype: foreground control only. No schedules, effects, or device readback yet.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
