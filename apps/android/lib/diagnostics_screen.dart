import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    super.key,
    required this.demo,
    required this.savedLights,
  });
  final bool demo;
  final int savedLights;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Map<String, dynamic>? snapshot;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await const MethodChannel('dev.kslight/settings')
          .invokeMapMethod<String, dynamic>('diagnostics');
      if (mounted) setState(() => snapshot = value);
    } catch (_) {
      if (mounted) {
        setState(() {
          snapshot = null;
          error = 'Phone diagnostics are unavailable. Reopen the app and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String flag(String key, String yes, String no) => snapshot?[key] == true
      ? yes
      : snapshot?[key] == false
      ? no
      : 'Unknown';

  Map<String, String> get details => {
    'Control mode': widget.demo
        ? 'Demo — no real light commands'
        : 'Direct Bluetooth',
    'Saved lights': '${widget.savedLights}',
    'Android API': snapshot?['androidApi'] is int
        ? '${snapshot!['androidApi']}'
        : 'Unknown',
    'Bluetooth': snapshot?['bluetoothSupported'] == false
        ? 'Not supported'
        : flag('bluetoothEnabled', 'On', 'Off'),
    'Connect permission': flag('connectPermission', 'Allowed', 'Missing'),
    'Scan permission': flag('scanPermission', 'Allowed', 'Missing'),
    'Bluetooth session': flag('bluetoothBusy', 'In use by KS Light', 'Idle'),
    'Home-screen widgets': snapshot?['widgets'] is int
        ? '${snapshot!['widgets']}'
        : 'Unknown',
    'Quick controls': flag(
      'quickControlsConfigured',
      'Configured',
      'Choose a light first',
    ),
  };

  List<String> get advice => [
    if (widget.demo)
      'Turn off Demo mode on the main screen to control a real light.',
    if (snapshot?['bluetoothEnabled'] == false)
      'Turn on Bluetooth in Android Quick Settings, then refresh.',
    if (snapshot?['connectPermission'] == false ||
        snapshot?['scanPermission'] == false)
      'Allow Nearby devices (or Location on older Android) in Android Settings → Apps → KS Light → Permissions, then scan again.',
    if (snapshot?['bluetoothBusy'] == true) 'Stop the active software effect or wait for the current command before using a widget.',
    'For a hub-owned light, use Hub control and stop direct control in other apps. Only one controller should hold its Bluetooth connection.',
    'After uncertain delivery, inspect the light before choosing your next command. KS Light does not automatically replay it.',
    'Sent means the command completed. The lamp does not provide reliable physical state readback.',
  ];

  Future<void> copy() async {
    final text = [
      'KS Light diagnostics',
      ...details.entries.map((e) => '${e.key}: ${e.value}'),
      'State evidence: last sent only; physical state not verified.',
    ].join('\n');
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Diagnostics copied')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not copy diagnostics')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Connection help'),
      actions: [
        IconButton(
          tooltip: 'Refresh diagnostics',
          onPressed: loading ? null : refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(error!),
          ),
        for (final item in details.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.key),
            subtitle: Text(item.value),
          ),
        const Divider(),
        for (final tip in advice)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(tip),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: loading ? null : copy,
          icon: const Icon(Icons.copy),
          label: const Text('Copy diagnostics'),
        ),
        const Text(
          'The report contains no device addresses, names, Wi-Fi details or credentials.',
        ),
      ],
    ),
  );
}
