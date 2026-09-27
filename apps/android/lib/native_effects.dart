import 'package:flutter/material.dart';

import 'light_backend.dart';
import 'protocol.dart';
import 'native_preferences.dart';
import 'app_style.dart';

const nativeEffects = <int, String>{
  0x82: 'Seven-color fade',
  0x83: 'RGB fade',
  0x84: 'Red breathing',
  0x85: 'Green breathing',
  0x86: 'Blue breathing',
  0x87: 'Yellow breathing',
  0x88: 'Cyan breathing',
  0x89: 'Purple breathing',
  0x8a: 'White breathing',
};
List<int> nativeEffectPacket(int effect, int speed, int brightness) {
  if (!nativeEffects.containsKey(effect) ||
      speed < 0 ||
      speed > 100 ||
      brightness < 1 ||
      brightness > 100) {
    throw ArgumentError('Invalid native effect settings');
  }
  return [0x5c, 0, effect, speed, brightness, 0, 0xc5];
}

class ReportedLightState {
  ReportedLightState(List<int> packet) : bytes = List.unmodifiable(packet) {
    if (packet.length != 14 ||
        packet[0] != 0x5f ||
        packet[1] != 2 ||
        packet.last != 0xf5 ||
        ![0, 1].contains(packet[2]) ||
        ![1, 2].contains(packet[3]) ||
        ![0x0f, 0xf0].contains(packet[11]) ||
        ![0x0f, 0xf0].contains(packet[12]) ||
        packet.any((v) => v < 0 || v > 255)) {
      throw const FormatException('Unrecognized light-state reply');
    }
  }
  final List<int> bytes;
  bool get dynamicMode => bytes[2] == 1;
  bool get power => bytes[11] == 0xf0;
  int get effect => bytes[10];
  int get brightness => bytes[8];
  String get description => !power
      ? 'Light reports: Off'
      : dynamicMode
      ? 'Light reports: ${nativeEffects[effect] ?? 'effect $effect'}, brightness $brightness'
      : 'Light reports: static color, brightness $brightness';
}

class NativeEffectsScreen extends StatefulWidget {
  const NativeEffectsScreen({
    super.key,
    required this.light,
    required this.backend,
    required this.onChanged,
    this.customBuilder,
    this.store,
  });
  final Light light;
  final LightBackend backend;
  final VoidCallback onChanged;
  final WidgetBuilder? customBuilder;
  final NativePreferencesStore? store;
  @override
  State<NativeEffectsScreen> createState() => _NativeEffectsScreenState();
}

class _NativeEffectsScreenState extends State<NativeEffectsScreen>
    with WidgetsBindingObserver {
  LightSession? session;
  bool busy = false,
      ready = false,
      canSave = true,
      active = false,
      foreground = true;
  late final store = widget.store ?? NativePreferencesStore();
  NativeLibrary library = NativeLibrary();
  NativeChoice get choice => NativeChoice(
    effect: effect,
    speed: speed.round(),
    brightness: brightness.round(),
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadPreferences();
  }

  Future<void> loadPreferences() async {
    try {
      final saved = await store.load(widget.light.id);
      if (!mounted) return;
      setState(() {
        library = saved;
        effect = saved.last.effect;
        speed = saved.last.speed.toDouble();
        brightness = saved.last.brightness.toDouble();
        ready = true;
        status = 'Saved choices loaded. Tap Apply to send them to the light.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          ready = true;
          canSave = false;
          status = 'Saved effects could not be loaded. Controls are available; saving is disabled to protect your presets.';
        });
      }
    }
  }

  Future<void> saveLibrary(NativeLibrary next) async {
    await store.save(widget.light.id, next);
    library = next;
  }

  void releaseChange() {
    if (active && foreground && ready && !busy) execute('apply');
  }

  Future<void> closing = Future<void>.value();
  Future<void> closeSession() {
    final old = session;
    session = null;
    if (old != null) {
      closing = closing.then((_) => old.close()).catchError((Object _) {});
    }
    return closing;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      if (mounted && active) {
        setState(
          () => status = 'The on-light effect continues. Tap Apply when you return to enable live adjustments.',
        );
      }
      active = false;
      if (!busy) closeSession();
    }
  }

  Future<void> savePreset() async {
    var draftName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save effect preset'),
        content: TextField(
          onChanged: (value) => draftName = value,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Preset name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = draftName.trim();
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    if (library.presets.length >= 20 && !library.presets.containsKey(name)) {
      setState(() => status = 'Up to 20 presets per light. Remove one first.');
      return;
    }
    await updatePresets({...library.presets, name: choice});
  }

  Future<void> updatePresets(Map<String, NativeChoice> presets) async {
    setState(() => busy = true);
    try {
      await saveLibrary(NativeLibrary(last: library.last, presets: presets));
      if (mounted) setState(() => status = 'Presets saved on this phone.');
    } catch (_) {
      if (mounted) {
        setState(
          () => status = 'Could not save presets. Your previous saved presets are unchanged.',
        );
      }
    } finally {
      if (!mounted || !foreground) await closeSession();
      if (mounted) setState(() => busy = false);
    }
  }

  int effect = 0x89;
  double speed = 35, brightness = 50;
  String status =
      'Choose a built-in effect. The light creates the animation itself.';
  Future<void> execute(String action) async {
    if (busy || !ready || !foreground) return;
    final requested = choice;
    setState(() {
      busy = true;
      status = 'Connecting…';
    });
    try {
      await closing;
      if (!mounted || !foreground) return;
      session ??= await widget.backend.openSession(widget.light);
      if (!mounted || !foreground) return;
      if (action != 'read') {
        widget.onChanged();
        await session!.send(
          action == 'off'
              ? [powerPacket(false)]
              : [
                  powerPacket(true),
                  nativeEffectPacket(
                    requested.effect,
                    requested.speed,
                    requested.brightness,
                  ),
                ],
        );
      }
      if (action != 'read') {
        active = action == 'apply' && foreground;
        var saved = canSave;
        if (action == 'apply' && canSave) {
          try {
            await saveLibrary(
              NativeLibrary(last: requested, presets: library.presets),
            );
          } catch (_) {
            saved = false;
          }
        }
        if (mounted) {
          setState(
            () => status = action == 'off'
                ? 'Off command sent.'
                : '${nativeEffects[requested.effect]} sent • ${saved ? 'settings saved' : 'settings could not be saved'}',
          );
        }
        return;
      }
      try {
        final raw = await session!.queryState();
        debugPrint(
          'KS state reply: ${raw.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}',
        );
        final reported = ReportedLightState(raw);
        if (mounted) setState(() => status = reported.description);
      } catch (e) {
        if (mounted) {
          setState(
            () => status = action == 'read'
                ? 'This light did not return a recognized state. Controls still work.'
                : 'Command sent. State unconfirmed: $e',
          );
        }
      }
    } catch (e) {
      active = false;
      await closeSession();
      if (mounted) setState(() => status = 'Connection failed: $e');
    } finally {
      if (!mounted || !foreground) await closeSession();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    closeSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Effects')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: busy || !ready ? null : () => execute('apply'),
                child: const Text('Apply effect'),
              ),
              OutlinedButton(
                onPressed: busy || !ready ? null : () => execute('off'),
                child: const Text('Turn off'),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.light.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (!status.startsWith('Choose') &&
                !status.startsWith('Saved choices loaded'))
              StatusNotice(status, busy: busy),
            const SizedBox(height: 20),
            const StatePill(
              'Runs on your light',
              icon: Icons.auto_awesome_outlined,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in nativeEffects.entries)
                    SizedBox(
                      width: MediaQuery.textScalerOf(context).scale(1) > 1.8
                          ? constraints.maxWidth
                          : MediaQuery.textScalerOf(context).scale(1) > 1.2
                          ? (constraints.maxWidth - 8) / 2
                          : (constraints.maxWidth - 16) / 3,
                      child: Semantics(
                        selected: effect == e.key,
                        child: Material(
                          color: effect == e.key
                              ? const Color(0xff34432a)
                              : panel,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: busy || !ready
                                ? null
                                : () {
                                    setState(() => effect = e.key);
                                    releaseChange();
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 14,
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: e.key < 0x84
                                            ? [
                                                const Color(0xffffbe85),
                                                const Color(0xffbba1ff),
                                              ]
                                            : [
                                                Colors.white,
                                                <int, Color>{
                                                  0x84: Colors.redAccent,
                                                  0x85: Colors.greenAccent,
                                                  0x86: Colors.blueAccent,
                                                  0x87: Colors.yellow,
                                                  0x88: Colors.cyanAccent,
                                                  0x89: Colors.purpleAccent,
                                                  0x8a: Colors.white,
                                                }[e.key]!,
                                              ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height:
                                        36 *
                                        MediaQuery.textScalerOf(context)
                                            .scale(1),
                                    child: Center(
                                      child: Text(
                                        e.value,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Icon(
                                      Icons.check,
                                      size: 14,
                                      color: effect == e.key
                                          ? accent
                                          : Colors.transparent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Speed: ${speed.round()}%'),
            Slider(
              key: const Key('native-speed'),
              value: speed,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: busy || !ready
                  ? null
                  : (v) => setState(() => speed = v),
              onChangeEnd: (_) => releaseChange(),
            ),
            Text('Brightness: ${brightness.round()}%'),
            Slider(
              value: brightness,
              min: 1,
              max: 100,
              divisions: 99,
              onChanged: busy || !ready
                  ? null
                  : (v) => setState(() => brightness = v),
              onChangeEnd: (_) => releaseChange(),
            ),
            const Text('Once active, adjustments apply on release.'),
            if (library.presets.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in library.presets.entries)
                    InputChip(
                      label: Text(entry.key),
                      onPressed: busy || !ready
                          ? null
                          : () {
                              setState(() {
                                effect = entry.value.effect;
                                speed = entry.value.speed.toDouble();
                                brightness = entry.value.brightness.toDouble();
                              });
                              releaseChange();
                            },
                      onDeleted: busy || !canSave
                          ? null
                          : () => updatePresets(
                              {...library.presets}..remove(entry.key),
                            ),
                    ),
                ],
              ),
            TextButton(
              onPressed: busy || !ready || !canSave ? null : savePreset,
              child: const Text('Save preset'),
            ),
            ExpansionTile(
              title: const Text('Advanced'),
              children: [
                TextButton(
                  onPressed: busy || !ready ? null : () => execute('read'),
                  child: const Text('Read light state'),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Built-in effects keep running when the app closes. Color balance applies to static colors only.',
                  ),
                ),
              ],
            ),
            if (widget.customBuilder != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        active = false;
                        await closeSession();
                        if (!context.mounted) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: widget.customBuilder!,
                          ),
                        );
                        if (mounted) {
                          setState(
                            () => status =
                                'Choose an effect to run on the light.',
                          );
                        }
                      },
                child: const Text('Custom effects from phone'),
              ),
            const SizedBox(height: 12),
            const Text('Apply a static color to return to steady light.'),
          ],
        ),
      ),
    ),
  );
}
