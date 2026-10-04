import 'dart:convert';

import 'package:flutter/material.dart';

import 'settings.dart';
import 'app_style.dart';

class SavedColor {
  SavedColor(List<int> rgb, this.brightness) : rgb = List.unmodifiable(rgb) {
    if (rgb.length != 3 ||
        rgb.any((v) => v < 0 || v > 255) ||
        brightness < 0 ||
        brightness > 255) {
      throw const FormatException('Invalid saved color');
    }
  }
  final List<int> rgb;
  final int brightness;
  Map<String, dynamic> toJson() => {'rgb': rgb, 'brightness': brightness};
  factory SavedColor.fromJson(Map<String, dynamic> json) => SavedColor(
    List<int>.from(json['rgb'] as List),
    json['brightness'] as int,
  );
}

class AppPreferences extends ChangeNotifier {
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void changed() {
    if (!_disposed) notifyListeners();
  }

  AppAppearance appearance = AppAppearance.lime;
  Map<String, SavedColor> colors = {};
  bool ready = false, saving = false;
  String? error;
  Future<void> load() async {
    try {
      final raw = await SettingsStore.channel.invokeMethod<String>(
        'loadAppPreferences',
      );
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['version'] != 1) {
          throw const FormatException('Unknown preferences');
        }
        final theme = AppAppearance.values.byName(json['appearance'] as String);
        final saved = (json['colors'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, SavedColor.fromJson(v as Map<String, dynamic>)),
        );
        validate(saved);
        appearance = theme;
        colors = Map.unmodifiable(saved);
      }
      ready = true;
      error = null;
    } catch (_) {
      error =
          'Saved colors and appearance could not be loaded. Restart to retry.';
    }
    changed();
  }

  static void validate(Map<String, SavedColor> colors) {
    if (colors.length > 30 ||
        colors.keys.any((n) => n.trim().isEmpty || n.length > 40)) {
      throw const FormatException('Invalid saved colors');
    }
  }

  Future<bool> save({
    AppAppearance? theme,
    Map<String, SavedColor>? presets,
  }) async {
    if (!ready || saving) return false;
    saving = true;
    changed();
    try {
      final next = presets ?? colors;
      validate(next);
      final nextTheme = theme ?? appearance;
      await SettingsStore.channel.invokeMethod<void>(
        'saveAppPreferences',
        jsonEncode({
          'version': 1,
          'appearance': nextTheme.name,
          'colors': next.map((k, v) => MapEntry(k, v.toJson())),
        }),
      );
      colors = Map.unmodifiable(next);
      appearance = nextTheme;
      error = null;
      return true;
    } catch (_) {
      error = 'Could not save. Your previous choices are unchanged.';
      return false;
    } finally {
      saving = false;
      changed();
    }
  }
}

class PreferencesScope extends InheritedNotifier<AppPreferences> {
  const PreferencesScope({
    super.key,
    required AppPreferences preferences,
    required super.child,
  }) : super(notifier: preferences);
  static AppPreferences? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PreferencesScope>()?.notifier;
}

class AppearancePicker extends StatelessWidget {
  const AppearancePicker({super.key});
  @override
  Widget build(BuildContext context) {
    final prefs = PreferencesScope.maybeOf(context)!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading('Appearance'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final theme in AppAppearance.values)
                ChoiceChip(
                  avatar: CircleAvatar(
                    backgroundColor: theme.accent,
                    radius: 9,
                  ),
                  label: Text(theme.label),
                  selected: prefs.appearance == theme,
                  onSelected: !prefs.ready || prefs.saving
                      ? null
                      : (_) => prefs.save(theme: theme),
                ),
            ],
          ),
          if (prefs.error != null) StatusNotice(prefs.error!),
        ],
      ),
    );
  }
}

class SavedColors extends StatelessWidget {
  const SavedColors({
    super.key,
    required this.rgb,
    required this.brightness,
    required this.onSelected,
    this.enabled = true,
  });
  final List<int> rgb;
  final int brightness;
  final bool enabled;
  final ValueChanged<SavedColor> onSelected;
  Future<void> add(BuildContext context, AppPreferences prefs) async {
    final snapshot = SavedColor(rgb, brightness);
    var name = '';
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Save color'),
          content: TextField(
            autofocus: true,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Evening glow',
              errorText: error,
            ),
            onChanged: (v) => name = v.trim(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.isEmpty || prefs.colors.containsKey(name)) {
                  update(
                    () => error = name.isEmpty
                        ? 'Enter a name'
                        : 'Choose a different name',
                  );
                } else {
                  Navigator.pop(context, name);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    final saved = await prefs.save(
      presets: {...prefs.colors, result: snapshot},
    );
    if (saved && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Color saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = PreferencesScope.maybeOf(context);
    if (prefs == null) return const SizedBox.shrink();
    final available = enabled && prefs.ready && !prefs.saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Saved colors',
          icon: Icons.bookmark_outline,
          trailing: TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Save current'),
            onPressed: available && prefs.colors.length < 30
                ? () => add(context, prefs)
                : null,
          ),
        ),
        if (prefs.error != null) StatusNotice(prefs.error!),
        if (prefs.colors.isEmpty)
          const Text('Save a color and brightness to use on any light.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in prefs.colors.entries)
              InputChip(
                avatar: CircleAvatar(
                  radius: 11,
                  backgroundColor: Color.fromARGB(
                    255,
                    entry.value.rgb[0],
                    entry.value.rgb[1],
                    entry.value.rgb[2],
                  ),
                ),
                label: Text(entry.key),
                onPressed: available ? () => onSelected(entry.value) : null,
                deleteButtonTooltipMessage: 'Delete ${entry.key}',
                onDeleted: available
                    ? () => prefs.save(
                        presets: {...prefs.colors}..remove(entry.key),
                      )
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}
