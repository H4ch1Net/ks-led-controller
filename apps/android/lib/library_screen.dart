import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'color_picker.dart';
import 'home_library.dart';
import 'library_transfer.dart';
import 'light_backend.dart';
import 'settings.dart';
import 'scene_color_editor.dart';
import 'effects_screen.dart';
import 'app_style.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.demo,
    required this.discovered,
    required this.backend,
    required this.settings,
    this.powers = const {},
    required this.onDelivered,
    required this.onFailed,
  });
  final Map<String, bool> powers;
  final bool demo;
  final List<Light> discovered;
  final LightBackend backend;
  final Map<String, LightSettings> settings;
  final Future<void> Function(Light, SceneState) onDelivered;
  final void Function(String) onFailed;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final store = HomeLibraryStore();
  late final Map<String, bool> activePowers = Map.of(widget.powers);
  late final Map<String, LightSettings> activeSettings = Map.of(
    widget.settings,
  );
  HomeLibrary? library;
  List<Map<String, dynamic>> profiles = [];
  bool busy = true, running = false, stopRequested = false, editing = false;
  String message = 'Loading saved lights…';
  List<TargetResult> results = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  String name(String id) {
    final alias = activeSettings[id]?.name;
    return alias != null && alias.isNotEmpty
        ? alias
        : library?.lights[id]?['name'] ?? id;
  }

  bool currentMatch(String id, String? prefix) =>
      library?.lights[id]?['prefix'] == prefix &&
      library!.lights.containsKey(id);

  Future<void> load() async {
    try {
      final loaded = await store.load(widget.demo);
      profiles = (jsonDecode(
        await rootBundle.loadString('assets/profiles.json'),
      ) as List).cast<Map<String, dynamic>>();
      if (widget.discovered.isNotEmpty) {
        loaded.remember(widget.discovered);
        await store.save(widget.demo, loaded);
      }
      if (mounted) {
        setState(() {
          library = loaded;
          message = 'Saved lights can be tried even when absent from the latest scan.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => message =
              'Could not load library: $error. Existing data was kept.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          running = false;
        });
      }
    }
  }

  Future<void> save(HomeLibrary next) async {
    setState(() => busy = true);
    try {
      await store.save(widget.demo, next);
      if (mounted) {
        setState(() {
          library = next;
          message = 'Saved on this phone.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => message = 'Could not save: $error');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          running = false;
        });
      }
    }
  }

  Future<void> copyBackup({bool file = false}) async {
    if (busy || library == null) return;
    setState(() => busy = true);
    try {
      final text = LibraryTransfer.encode(library!, widget.demo);
      final exported = file
          ? await SettingsStore.channel.invokeMethod<bool>(
              'exportLibraryFile',
              text,
            )
          : null;
      if (!file) await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        setState(
          () => message = file
              ? exported == true
                    ? 'Rooms and scenes exported.'
                    : 'Export cancelled.'
              : 'Rooms and scenes copied. Paste the text into a file to keep a backup.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => message = error is FormatException
              ? error.message
              : 'Could not export the backup. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importBackup({bool file = false}) async {
    if (busy || library == null) return;
    setState(() {
      busy = true;
      editing = true;
    });
    try {
      var text = '';
      if (file) {
        final loaded = await SettingsStore.channel.invokeMethod<String>(
          'importLibraryFile',
        );
        if (loaded == null || !mounted) return;
        text = loaded;
      }
      String? error;
      HomeLibrary? backup;
      var matchingRevision = 0;
      final mapping = <String, String>{};
      final preview = await showDialog<LibraryImport>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Import rooms & scenes'),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Open or paste a backup. Scan your target lights first, then match devices if needed. Existing rooms and scenes will be kept.',
                    ),
                    TextFormField(
                      key: const Key('library-import-text'),
                      initialValue: text,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          LibraryTransfer.maxBytes,
                        ),
                      ],
                      maxLines: 6,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Backup text',
                        errorText: error,
                        errorMaxLines: 4,
                      ),
                      onChanged: (value) => update(() {
                        text = value;
                        backup = null;
                        mapping.clear();
                      }),
                    ),
                    TextButton(
                      onPressed: () {
                        try {
                          final parsed = LibraryTransfer.read(
                            text,
                            widget.demo,
                          );
                          update(() {
                            backup = parsed;
                            matchingRevision++;
                            mapping.clear();
                            error = null;
                          });
                        } catch (failure) {
                          update(
                            () => error = 'Open or paste a valid backup before matching devices.',
                          );
                        }
                      },
                      child: const Text('Match backup devices'),
                    ),
                    if (backup != null) ...[
                      const Text(
                        'Choose a saved light of the same model for each backup device. Each target can be used once.',
                      ),
                      for (final entry in backup!.lights.entries)
                        DropdownButtonFormField<String>(
                          key: ValueKey('match-$matchingRevision-${entry.key}'),
                          isExpanded: true,
                          initialValue:
                              mapping[entry.key] ??
                              (currentMatch(entry.key, entry.value['prefix'])
                                  ? entry.key
                                  : null),
                          decoration: InputDecoration(
                            labelText: entry.value['name'] ?? entry.key,
                          ),
                          items: [
                            for (final target in library!.lights.entries)
                              if (target.value['prefix'] ==
                                  entry.value['prefix'])
                                DropdownMenuItem(
                                  value: target.key,
                                  child: Text(
                                    '${name(target.key)} (${target.key})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                          ],
                          onChanged: (value) => mapping[entry.key] = value!,
                        ),
                    ],
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
                onPressed: () {
                  try {
                    final result = LibraryTransfer.preview(
                      text,
                      library!,
                      widget.demo,
                      profiles,
                      mapping: mapping,
                    );
                    Navigator.pop(context, result);
                  } catch (failure) {
                    update(
                      () => error = failure is FormatException
                          ? failure.message
                          : 'The backup contains unsupported light settings.',
                    );
                  }
                },
                child: const Text('Review'),
              ),
            ],
          ),
        ),
      );
      if (preview == null || !mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review import'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add ${preview.collections.length} collections and ${preview.scenes.length} scenes.',
                  ),
                  const Text(
                    'Matching names get a numbered copy. Your default light, device names and color balance stay as they are.',
                  ),
                  for (final name in preview.collections)
                    Text('Collection: $name'),
                  for (final name in preview.scenes) Text('Scene: $name'),
                  for (final entry in preview.deviceMatches.entries)
                    Text('${entry.key} → ${entry.value}'),
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (accepted == true && mounted) {
        setState(() => editing = false);
        await save(preview.library);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => message = 'Could not import the file. Use a UTF-8 KS Light backup up to 256 KiB.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          editing = false;
        });
      }
    }
  }

  Future<void> create(bool scene, {String? existingName}) async {
    if (busy) return;
    setState(() {
      busy = true;
      editing = true;
    });
    try {
      await editDefinition(scene, existingName);
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          editing = false;
        });
      }
    }
  }

  Future<void> editDefinition(bool scene, String? existingName) async {
    final current = library!;
    final previousScene = !scene || existingName == null
        ? null
        : current.scenes[existingName];
    final previousCollection = scene || existingName == null
        ? null
        : current.collections[existingName];
    var title = existingName ?? '';
    var kind = previousCollection?.kind ?? 'room';
    final selected = <String>{
      ...?previousScene?.keys,
      ...?previousCollection?.members,
    };
    final powers = <String, bool>{
      for (final entry
          in previousScene?.entries ?? <MapEntry<String, SceneState>>[])
        entry.key: entry.value.power,
    };
    var updateColors = false;
    final customColors = <String, SceneState>{};
    final colorLights = <String, Light>{};
    for (final id in current.lights.keys) {
      try {
        final light = current.resolve(id, profiles);
        if (['floor', 'ceiling'].contains(light.profile['color_type'])) {
          colorLights[id] = light;
        }
      } on StateError {
        // A missing profile must not prevent editing other scene members.
      }
    }
    SceneState snapshot(String id) {
      final previous =
          customColors[id] ?? (updateColors ? null : previousScene?[id]);
      final rgb = previous != null
          ? previous.rgb
          : activeSettings[id]?.lastColor;
      return SceneState(
        power: powers[id] ?? true,
        rgb: rgb == null ? null : List.of(rgb),
        brightness:
            previous?.brightness ?? activeSettings[id]?.lastBrightness ?? 255,
      );
    }

    String? error;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            existingName != null
                ? (scene ? 'Edit scene' : 'Edit room or group')
                : scene
                ? 'Save a scene'
                : 'New room or group',
          ),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: title,
                    maxLength: 40,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      errorText: error,
                    ),
                    onChanged: (v) => title = v.trim(),
                  ),
                  if (!scene)
                    DropdownButton<String>(
                      value: kind,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'room', child: Text('Room')),
                        DropdownMenuItem(value: 'group', child: Text('Group')),
                      ],
                      onChanged: (v) => update(() => kind = v!),
                    ),
                  Text(
                    scene
                        ? existingName != null
                              ? 'Edit members, power and scene colors. Editing does not change the lights.'
                              : 'Choose lights, then optionally customize their scene colors. Otherwise their last applied settings are used.'
                        : 'Choose up to 32 saved lights. A light can belong to more than one collection.',
                  ),
                  if (scene && existingName != null)
                    SwitchListTile(
                      title: const Text('Use latest applied colors'),
                      subtitle: const Text(
                        'Off keeps saved colors. Custom scene edits are kept either way. New members use their latest applied settings.',
                      ),
                      value: updateColors,
                      onChanged: (value) => update(() => updateColors = value),
                    ),
                  for (final id in current.lights.keys) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(name(id)),
                      subtitle: scene
                          ? Text(
                              snapshot(id).rgb == null
                                  ? 'On only • no color saved'
                                  : '${colorHex(snapshot(id).rgb!)} • ${(snapshot(id).brightness * 100 / 255).round()}%',
                            )
                          : null,
                      value: selected.contains(id),
                      onChanged: (checked) => update(() {
                        if (checked!) {
                          selected.add(id);
                        } else {
                          selected.remove(id);
                        }
                      }),
                    ),
                    if (scene && selected.contains(id))
                      SwitchListTile(
                        title: Text(
                          (powers[id] ?? true) ? 'Turn on' : 'Turn off',
                        ),
                        value: powers[id] ?? true,
                        onChanged: (v) => update(() => powers[id] = v),
                      ),
                    if (scene &&
                        selected.contains(id) &&
                        colorLights.containsKey(id))
                      TextButton(
                        key: Key('scene-color-$id'),
                        onPressed: () async {
                          final light = colorLights[id]!;
                          final result = await Navigator.of(context)
                              .push<SceneState>(
                                MaterialPageRoute(
                                  builder: (_) => SceneColorEditor(
                                    light: Light(id, name(id), light.profile),
                                    initial: snapshot(id),
                                  ),
                                ),
                              );
                          if (result != null && context.mounted) {
                            update(() => customColors[id] = result);
                          }
                        },
                        child: Text(
                          customColors.containsKey(id)
                              ? 'Edit custom scene color'
                              : 'Set scene color',
                        ),
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
                try {
                  validName(title);
                  if (selected.isEmpty || selected.length > 32) {
                    throw const FormatException('Choose 1-32 lights');
                  }
                  final names = scene
                      ? current.scenes.keys
                      : current.collections.keys;
                  if (names.any(
                    (n) =>
                        n != existingName &&
                        n.toLowerCase() == title.toLowerCase(),
                  )) {
                    throw const FormatException('That name already exists');
                  }
                  Navigator.pop(context, true);
                } catch (e) {
                  update(() => error = e.toString());
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => editing = false);
    final next = current.copy();
    if (scene) {
      if (existingName != null) next.scenes.remove(existingName);
      next.scenes[title] = {for (final id in selected) id: snapshot(id)};
    } else {
      if (existingName != null) next.collections.remove(existingName);
      next.collections[title] = LightCollection(kind, selected.toList());
    }
    await save(next);
  }

  Future<void> run(Map<String, SceneState> targets) async {
    if (busy) return;
    setState(() {
      busy = true;
      running = true;
      stopRequested = false;
      results = [];
    });
    try {
      final delivered = await runLightBatch(
        library: library!,
        profiles: profiles,
        targets: targets,
        shouldStop: () => stopRequested,
        settings: activeSettings,
        backend: widget.backend,
        onDelivered: (light, state) async {
          activePowers[light.id] = state.power;
          if (state.power && state.rgb != null) {
            activeSettings[light.id] =
                (activeSettings[light.id] ?? const LightSettings()).withColor(
                  state.rgb!,
                  state.brightness,
                );
          }
          await widget.onDelivered(light, state);
        },
        onProgress: (id) {
          if (mounted) setState(() => message = 'Sending to ${name(id)}…');
        },
      );
      for (final result in delivered.where(
        (r) => !r.delivered && !r.cancelled,
      )) {
        activePowers.remove(result.id);
        widget.onFailed(result.id);
      }
      if (mounted) {
        setState(() {
          results = delivered;
          final success = results.where((r) => r.delivered).length;
          message =
              '$success/${results.length} commands delivered. Physical state is unconfirmed.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = 'Could not run: $e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          running = false;
        });
      }
    }
  }

  Future<void> effects(List<String> members) async {
    try {
      final lights = members
          .map((id) => library!.resolve(id, profiles))
          .toList();
      if (lights.any(
        (l) => !['floor', 'ceiling'].contains(l.profile['color_type']),
      )) {
        throw StateError('Every member must support RGB for a group effect.');
      }
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => EffectsScreen(
            lights: lights,
            backend: widget.backend,
            settings: activeSettings,
            demo: widget.demo,
            previous: effectSnapshots(lights, activeSettings, activePowers),
            onFailed: (id) {
              activePowers.remove(id);
              widget.onFailed(id);
            },
            onDelivered: (light, state) async {
              activePowers[light.id] = state.power;
              if (state.power && state.rgb != null) {
                activeSettings[light.id] =
                    (activeSettings[light.id] ?? const LightSettings())
                        .withColor(state.rgb!, state.brightness);
              }
              await widget.onDelivered(light, state);
            },
          ),
        ),
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => message = 'Could not open effects: $e');
    }
  }

  Future<void> remove(String title, bool scene) async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$title"?'),
        content: Text(
          scene
              ? 'This scene will be removed from this phone. Lights are not changed.'
              : 'This room or group will be removed from this phone. Lights are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy) return;
    final next = library!.copy();
    if (scene) {
      next.scenes.remove(title);
    } else {
      next.collections.remove(title);
    }
    await save(next);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Rooms & scenes'),
        leading: BackButton(
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Library backup',
            enabled: !busy && library != null,
            onSelected: (action) {
              if (action == 'copy') {
                copyBackup();
              } else if (action == 'export-file') {
                copyBackup(file: true);
              } else {
                importBackup(file: action == 'import-file');
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'export-file',
                enabled:
                    library != null &&
                    (library!.collections.isNotEmpty ||
                        library!.scenes.isNotEmpty),
                child: const Text('Export backup file'),
              ),
              PopupMenuItem(
                value: 'import-file',
                enabled: library != null && library!.lights.isNotEmpty,
                child: const Text('Open backup file'),
              ),
              PopupMenuItem(
                value: 'copy',
                enabled:
                    library != null &&
                    (library!.collections.isNotEmpty ||
                        library!.scenes.isNotEmpty),
                child: const Text('Copy rooms & scenes'),
              ),
              PopupMenuItem(
                value: 'import',
                enabled: library != null && library!.lights.isNotEmpty,
                child: const Text('Import rooms & scenes'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (busy && !editing) const LinearProgressIndicator(),
            if (message.toLowerCase().contains('could not') ||
                message.toLowerCase().contains('failed'))
              StatusNotice(message),
            if (running)
              TextButton(
                onPressed: stopRequested
                    ? null
                    : () => setState(() => stopRequested = true),
                child: Text(
                  stopRequested ? 'Stopping…' : 'Stop after current light',
                ),
              ),
            if (results.isNotEmpty)
              Card(
                child: ExpansionTile(
                  title: Text(
                    '${results.where((r) => r.delivered).length}/${results.length} commands sent',
                  ),
                  initiallyExpanded: results.any(
                    (r) => !r.delivered || r.persistenceWarning != null,
                  ),
                  children: [
                    for (final result in results)
                      ListTile(
                        leading: Icon(
                          result.delivered
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                        ),
                        title: Text(name(result.id)),
                        subtitle: Text(
                          result.error ??
                              result.persistenceWarning ??
                              'Sent • unconfirmed',
                        ),
                      ),
                  ],
                ),
              ),
            if (library != null) ...[
              const SizedBox(height: 12),
              Text(
                'Set the mood',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: StatePill(
                  '${library!.lights.length} ${library!.lights.length == 1 ? 'light' : 'lights'}${widget.demo ? ' · Demo' : ''}',
                  icon: Icons.lightbulb_outline,
                ),
              ),
              SectionHeading(
                'Rooms',
                trailing: IconButton(
                  tooltip: 'New room / group',
                  icon: const Icon(Icons.add),
                  onPressed: busy || library!.lights.isEmpty
                      ? null
                      : () => create(false),
                ),
              ),
              if (library!.collections.isEmpty)
                const EmptyPanel(
                  icon: Icons.meeting_room_outlined,
                  title: 'No rooms yet',
                  subtitle: 'Group your lights by room or routine.',
                ),
              for (final entry in library!.collections.entries)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.meeting_room_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            PopupMenuButton<String>(
                              key: Key('edit-collection-${entry.key}'),
                              tooltip: 'Room options',
                              enabled: !busy,
                              onSelected: (action) => action == 'edit'
                                  ? create(false, existingName: entry.key)
                                  : remove(entry.key, false),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: const Text('Edit collection'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete collection'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Text(
                          '${entry.value.members.length} ${entry.value.members.length == 1 ? 'light' : 'lights'}',
                          style: const TextStyle(color: textMuted),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final power in [true, false])
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => run({
                                        for (final id in entry.value.members)
                                          id: SceneState(power: power),
                                      }),
                                child: Text(power ? 'All on' : 'All off'),
                              ),
                            IconButton.filledTonal(
                              tooltip: 'Effects',
                              onPressed: busy
                                  ? null
                                  : () => effects(entry.value.members),
                              icon: const Icon(Icons.auto_awesome_outlined),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              SectionHeading(
                'Scenes',
                trailing: IconButton(
                  tooltip: 'Save scene',
                  icon: const Icon(Icons.add),
                  onPressed: busy || library!.lights.isEmpty
                      ? null
                      : () => create(true),
                ),
              ),
              if (library!.scenes.isEmpty)
                const EmptyPanel(
                  icon: Icons.auto_awesome_outlined,
                  title: 'Create your first scene',
                  subtitle: 'Save your lights’ colors as a scene.',
                ),
              for (final entry in library!.scenes.entries)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.key,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            PopupMenuButton<String>(
                              key: Key('edit-scene-${entry.key}'),
                              tooltip: 'Scene options',
                              enabled: !busy,
                              onSelected: (action) => action == 'edit'
                                  ? create(true, existingName: entry.key)
                                  : remove(entry.key, true),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: const Text('Edit scene'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete scene'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SceneStrip([
                          for (final target in entry.value.entries)
                            StripSegment(
                              // Name and state, so color is never the only signal.
                              '${name(target.key)}: ${!target.value.power
                                  ? 'off'
                                  : target.value.rgb == null
                                  ? 'on'
                                  : '#${target.value.rgb!.map((v) => v.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}'}',
                              off: !target.value.power,
                              color: target.value.rgb == null
                                  ? null
                                  : Color.fromARGB(
                                      255,
                                      target.value.rgb![0],
                                      target.value.rgb![1],
                                      target.value.rgb![2],
                                    ),
                            ),
                        ]),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${entry.value.length} ${entry.value.length == 1 ? 'light' : 'lights'}',
                                style: const TextStyle(color: textMuted),
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: busy ? null : () => run(entry.value),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Activate'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}
