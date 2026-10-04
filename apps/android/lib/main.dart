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
import 'app_style.dart';
import 'app_preferences.dart';

void main() => runApp(const KsLightApp());

class KsLightApp extends StatefulWidget {
  const KsLightApp({super.key, this.backend, this.settingsStore});
  final SettingsStore? settingsStore;
  final LightBackend? backend;
  @override
  State<KsLightApp> createState() => _KsLightAppState();
}

class _KsLightAppState extends State<KsLightApp> {
  final preferences = AppPreferences();
  @override
  void initState() {
    super.initState();
    preferences.load();
  }

  @override
  void dispose() {
    preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PreferencesScope(
    preferences: preferences,
    child: AnimatedBuilder(
      animation: preferences,
      builder: (context, _) => MaterialApp(
        title: 'KS Light',
        debugShowCheckedModeBanner: false,
        theme: lightAppTheme(preferences.appearance),
        home: LightScreen(
          testBackend: widget.backend,
          settingsStore: widget.settingsStore,
        ),
      ),
    ),
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
    demo = widget.testBackend != null;
    backend = widget.testBackend ?? BluetoothBackend();
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
            'Add a shortcut for ${displayName(light)}. Stop active effects before using it.',
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
                    const Text('Leave blank to use the original name.'),
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
      initialColor: List.of(rgb),
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
  void changeMode(bool value) {
    setState(() {
      demo = value;
      backend = value ? DemoBackend() : BluetoothBackend();
      lights = [];
      selected = null;
      remembered.clear();
      powerStates.clear();
      message = '';
      defaultLightId = null;
    });
    loadDevices();
  }

  void appSettings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Settings',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
            ),
            const AppearancePicker(),
            SwitchListTile(
              title: const Text('Demo mode'),
              subtitle: const Text('Explore without changing real lights'),
              value: demo,
              onChanged: busy || widget.testBackend != null
                  ? null
                  : (value) {
                      Navigator.pop(sheetContext);
                      changeMode(value);
                    },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Connection help'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => DiagnosticsScreen(
                      demo: demo,
                      savedLights: lights.length,
                    ),
                  ),
                );
              },
            ),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Status reflects the last command sent. Changes from other controllers may not appear.',
                style: TextStyle(color: textMuted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget lightOptions() => PopupMenuButton<String>(
    tooltip: 'Light settings',
    enabled: !busy && settingsReady,
    onSelected: (action) {
      switch (action) {
        case 'rename':
          editSettings();
        case 'balance':
          editSettings(calibration: true);
        case 'default':
          setDefaultDevice(selected!);
        case 'shortcuts':
          configureShortcuts();
        case 'remove':
          removeDevice(selected!);
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'rename', child: Text('Rename')),
      if (selected?.profile['color_type'] != null)
        const PopupMenuItem(value: 'balance', child: Text('Color balance')),
      PopupMenuItem(
        value: 'default',
        child: Text(
          defaultLightId == selected?.id
              ? 'Clear default device'
              : 'Set as default device',
        ),
      ),
      if (!demo && selected?.profile['prefix'] == 'KS03~')
        const PopupMenuItem(
          value: 'shortcuts',
          child: Text('Widget & Quick Settings'),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'remove', child: Text('Remove device')),
    ],
  );

  /// Lens for a saved light: its last-sent color, dark when off or unknown.
  Widget lightLens(Light light, double size, {List<int>? color, int? level}) {
    final saved = config(light);
    final rgb = color ?? saved.lastColor;
    final power = powerStates[light.id];
    final floor = light.profile['color_type'] == 'floor';
    return Lens(
      size: size,
      color: rgb == null
          ? textFaint
          : Color.fromARGB(255, rgb[0], rgb[1], rgb[2]),
      lit: power == true && rgb != null,
      standby: power == null && rgb != null,
      level: floor ? (level ?? saved.lastBrightness) / 255 : 1,
    );
  }

  Widget deviceCard(Light light) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: busy ? null : () => select(light),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            lightLens(light, 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName(light),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    defaultLightId == light.id
                        ? 'Default light'
                        : 'Bluetooth light',
                    style: const TextStyle(color: textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: defaultLightId == light.id
                  ? 'Clear default device'
                  : 'Set as default device',
              icon: Icon(
                defaultLightId == light.id
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
              ),
              color: defaultLightId == light.id
                  ? Theme.of(context).colorScheme.primary
                  : null,
              onPressed: busy ? null : () => setDefaultDevice(light),
            ),
            const Icon(Icons.chevron_right, size: 20, color: textFaint),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colorType = selected?.profile['color_type'];
    final preview = Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
    final power = selected == null ? null : powerStates[selected!.id];
    final showMessage =
        busy ||
        [
          'could not',
          'failed',
          'unavailable',
          'no ks lights',
          'offline',
        ].any(message.toLowerCase().contains);
    return PopScope(
      canPop: selected == null && !busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !busy && selected != null) {
          setState(() => selected = null);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: selected == null
              ? null
              : IconButton(
                  tooltip: 'Change light',
                  onPressed: busy
                      ? null
                      : () => setState(() => selected = null),
                  icon: const Icon(Icons.arrow_back),
                ),
          title: Text(
            selected == null ? 'KS Light' : displayName(selected!),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (selected != null) lightOptions(),
            IconButton(
              tooltip: 'Settings',
              onPressed: busy ? null : appSettings,
              icon: const Icon(Icons.tune_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (colorType != null)
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('apply-color'),
                      onPressed: busy || !settingsReady || !colorValid
                          ? null
                          : () => send(null),
                      icon: Icon(busy ? Icons.hourglass_top : Icons.check),
                      label: Text(
                        busy
                            ? 'Sending…'
                            : colorPending
                            ? 'Apply color'
                            : 'Apply again',
                      ),
                    ),
                  ),
                ),
              ),
            const Divider(height: 1),
            NavigationBar(
              selectedIndex: 0,
              onDestinationSelected: busy
                  ? null
                  : (index) {
                      if (index == 0) {
                        setState(() => selected = null);
                      }
                      if (index == 1 && settingsReady) openLibrary();
                      if (index == 2) {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const HubScreen(),
                          ),
                        );
                      }
                    },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.lightbulb_outline),
                  selectedIcon: Icon(Icons.lightbulb),
                  label: 'Lights',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  label: 'Scenes',
                ),
                NavigationDestination(
                  icon: Icon(Icons.hub_outlined),
                  label: 'Hub',
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showMessage)
                  StatusNotice(busy ? 'Working…' : message, busy: busy),
                if (selected == null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Your lights',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      StatePill(
                        demo ? 'Demo mode' : 'Bluetooth',
                        icon: demo ? Icons.science_outlined : Icons.bluetooth,
                        tone: demo ? PillTone.warn : PillTone.ok,
                      ),
                      Text(
                        '${lights.length} saved',
                        style: const TextStyle(color: textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (lights.isEmpty)
                    const EmptyPanel(
                      icon: Icons.lightbulb_outline,
                      title: 'Add your first light',
                      subtitle: 'Scan for nearby lights to get started.',
                    ),
                  for (final light in lights) deviceCard(light),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: busy ? null : scan,
                    icon: const Icon(Icons.add),
                    label: Text(
                      busy
                          ? 'Scanning…'
                          : lights.isEmpty
                          ? 'Scan for lights'
                          : 'Add devices',
                    ),
                  ),
                ] else ...[
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      StatePill(
                        demo ? 'Demo mode' : 'Bluetooth',
                        icon: demo ? Icons.science_outlined : Icons.bluetooth,
                        tone: demo ? PillTone.warn : PillTone.ok,
                      ),
                      if (defaultLightId == selected!.id)
                        const StatePill('Default', icon: Icons.star_rounded),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Power panel: the lens previews the chosen light; a soft pool of
                  // that color falls on the panel only while the light is on.
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      border: Border.all(color: hairline),
                      gradient: power == true && colorType != null
                          ? RadialGradient(
                              center: const Alignment(-1.1, -1.3),
                              radius: 1.25,
                              colors: [
                                Color.lerp(
                                  Theme.of(context)
                                      .colorScheme
                                      .surfaceContainer,
                                  preview,
                                  colorType == 'floor'
                                      ? .1 + .16 * brightness / 255
                                      : .22,
                                )!,
                                Theme.of(context).colorScheme.surfaceContainer,
                              ],
                            )
                          : null,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            lightLens(
                              selected!,
                              56,
                              color: colorType == null ? null : rgb,
                              level: brightness,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Power',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Led(
                                        color: power == true
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                            : power == false
                                            ? textFaint
                                            : warnColor,
                                        glow: power != false,
                                        size: 6,
                                      ),
                                      const SizedBox(width: 7),
                                      Flexible(
                                        child: Text(
                                          power == null
                                              ? 'Power: unknown'
                                              : 'Last sent: ${power ? 'On' : 'Off'}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: textMuted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (colorType != null)
                              IconButton(
                                tooltip: 'Effects',
                                onPressed: busy || !settingsReady
                                    ? null
                                    : openEffects,
                                icon: const Icon(Icons.auto_awesome_outlined),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<bool>(
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
                            selected: {?power},
                            onSelectionChanged: busy
                                ? null
                                : (values) => send(
                                    values.isEmpty ? power! : values.single,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!settingsReady)
                    const StatusNotice(
                      'Saved settings unavailable. Restart to retry.',
                    ),
                  if (colorType == 'floor') ...[
                    SectionHeading(
                      'Brightness',
                      icon: Icons.light_mode_outlined,
                      trailing: Text(
                        '${(brightness * 100 / 255).round()}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Slider(
                      value: brightness.toDouble(),
                      min: 0,
                      max: 255,
                      divisions: 255,
                      label: '${(brightness * 100 / 255).round()}%',
                      semanticFormatterCallback: (v) =>
                          'Brightness ${(v * 100 / 255).round()} percent',
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              brightness = v.round();
                              colorPending = true;
                            }),
                    ),
                  ],
                  if (colorType != null) ...[
                    SavedColors(
                      rgb: rgb,
                      brightness: brightness,
                      enabled: !busy && colorValid,
                      onSelected: (saved) => setState(() {
                        rgb = List.of(saved.rgb);
                        // Saved colors are shared; ceiling profiles only accept full brightness.
                        brightness = colorType == 'floor'
                            ? saved.brightness
                            : 255;
                        colorPending = true;
                        colorValid = true;
                      }),
                    ),
                    SectionHeading(
                      'Color',
                      icon: Icons.palette_outlined,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Led(color: colorPending ? warnColor : null, size: 6),
                          const SizedBox(width: 6),
                          Text(
                            colorPending ? 'Preview' : 'Sent',
                            style: const TextStyle(
                              fontSize: 12,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
