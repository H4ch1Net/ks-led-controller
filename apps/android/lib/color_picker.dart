import 'package:flutter/material.dart';

String colorHex(List<int> rgb) =>
    '#${rgb.map((v) => v.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
List<int>? parseColorHex(String text) {
  final value = text.trim().replaceFirst(RegExp(r'^#'), '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) return null;
  return [
    for (var i = 0; i < 6; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ];
}

class LightColorPicker extends StatefulWidget {
  const LightColorPicker({
    super.key,
    required this.rgb,
    required this.onChanged,
    this.enabled = true,
    this.onValidityChanged,
  });
  final List<int> rgb;
  final ValueChanged<List<int>> onChanged;
  final bool enabled;
  final ValueChanged<bool>? onValidityChanged;
  @override
  State<LightColorPicker> createState() => _LightColorPickerState();
}

class _LightColorPickerState extends State<LightColorPicker> {
  late HSVColor hsv;
  late final TextEditingController hex;
  String? error;
  @override
  void initState() {
    super.initState();
    hsv = HSVColor.fromColor(
      Color.fromARGB(255, widget.rgb[0], widget.rgb[1], widget.rgb[2]),
    );
    hex = TextEditingController(text: colorHex(widget.rgb));
  }

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LightColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (colorHex(oldWidget.rgb) != colorHex(widget.rgb)) {
      final next = HSVColor.fromColor(
        Color.fromARGB(255, widget.rgb[0], widget.rgb[1], widget.rgb[2]),
      );
      hsv = next.saturation == 0 ? next.withHue(hsv.hue) : next;
      hex.text = colorHex(widget.rgb);
      error = null;
    }
  }

  void choose(HSVColor next) {
    final argb = next.toColor().toARGB32();
    setState(() {
      hsv = next;
      error = null;
    });
    widget.onValidityChanged?.call(true);
    widget.onChanged([(argb >> 16) & 255, (argb >> 8) & 255, argb & 255]);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          const height = 156.0;
          final width = constraints.maxWidth;
          void pick(Offset point) => choose(
            hsv
                .withSaturation((point.dx / width).clamp(0, 1))
                .withValue((1 - point.dy / height).clamp(0, 1)),
          );
          return Semantics(
            label: 'Color shade area. Exact RGB controls available in Fine adjustments.',
            child: GestureDetector(
              key: const ValueKey('shade-area'),
              behavior: HitTestBehavior.opaque,
              onTapDown: widget.enabled ? (d) => pick(d.localPosition) : null,
              onVerticalDragStart: widget.enabled
                  ? (d) => pick(d.localPosition)
                  : null,
              onVerticalDragUpdate: widget.enabled
                  ? (d) => pick(d.localPosition)
                  : null,
              onHorizontalDragStart: widget.enabled
                  ? (d) => pick(d.localPosition)
                  : null,
              onHorizontalDragUpdate: widget.enabled
                  ? (d) => pick(d.localPosition)
                  : null,
              child: SizedBox(
                height: height,
                width: width,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white,
                                HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (hsv.saturation * width - 9).clamp(0, width - 18),
                        top: ((1 - hsv.value) * height - 9).clamp(
                          0,
                          height - 18,
                        ),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(color: Colors.black54, blurRadius: 2),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 10),
      DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [
              Colors.red,
              Colors.yellow,
              Colors.green,
              Colors.cyan,
              Colors.blue,
              Color(0xffff00ff),
              Colors.red,
            ],
          ),
        ),
        child: Slider(
          key: const ValueKey('hue'),
          value: hsv.hue,
          min: 0,
          max: 360,
          activeColor: Colors.transparent,
          inactiveColor: Colors.transparent,
          thumbColor: Colors.white,
          semanticFormatterCallback: (v) => 'Hue ${v.round()} degrees',
          onChanged: widget.enabled ? (v) => choose(hsv.withHue(v)) : null,
        ),
      ),
      const SizedBox(height: 12),
      const SizedBox(height: 8),
      Wrap(
        spacing: 4,
        children: [
          for (final entry in {
            'Red': [255, 0, 0],
            'Orange': [255, 100, 0],
            'Green': [0, 255, 0],
            'Blue': [0, 0, 255],
            'Purple': [160, 0, 255],
            'Pink': [239, 66, 255],
            'White': [255, 255, 255],
          }.entries)
            Tooltip(
              message: entry.key,
              child: Semantics(
                label: entry.key,
                button: true,
                selected: colorHex(widget.rgb) == colorHex(entry.value),
                child: InkResponse(
                  onTap: widget.enabled
                      ? () {
                          widget.onValidityChanged?.call(true);
                          hex.text = colorHex(entry.value);
                          setState(() => error = null);
                          widget.onChanged(List.of(entry.value));
                        }
                      : null,
                  radius: 24,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromARGB(
                            255,
                            entry.value[0],
                            entry.value[1],
                            entry.value[2],
                          ),
                          border: Border.all(
                            color: colorHex(widget.rgb) == colorHex(entry.value)
                                ? Colors.white
                                : Colors.white24,
                            width: colorHex(widget.rgb) == colorHex(entry.value)
                                ? 3
                                : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Fine adjustments', style: TextStyle(fontSize: 14)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              colorHex(widget.rgb),
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more, size: 20),
          ],
        ),
        children: [
          TextField(
            key: const ValueKey('hex-color'),
            controller: hex,
            enabled: widget.enabled,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Hex color',
              hintText: '#EF42FF',
              errorText: error,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) {
              final parsed = parseColorHex(value);
              setState(
                () => error = parsed == null
                    ? 'Use six hex digits, such as #EF42FF.'
                    : null,
              );
              widget.onValidityChanged?.call(parsed != null);
              if (parsed != null) widget.onChanged(parsed);
            },
          ),

          for (var i = 0; i < 3; i++) ...[
            Text('${['Red', 'Green', 'Blue'][i]}: ${widget.rgb[i]}'),
            Slider(
              value: widget.rgb[i].toDouble(),
              min: 0,
              max: 255,
              divisions: 255,
              semanticFormatterCallback: (v) =>
                  '${['Red', 'Green', 'Blue'][i]} ${v.round()}',
              onChanged: widget.enabled
                  ? (v) {
                      final rgb = List<int>.of(widget.rgb);
                      rgb[i] = v.round();
                      widget.onChanged(rgb);
                    }
                  : null,
            ),
          ],
        ],
      ),
    ],
  );
}
