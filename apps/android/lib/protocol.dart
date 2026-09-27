List<int> powerPacket(bool on) => [0x5b, on ? 0xf0 : 0x0f, 1, 0xb5];
List<int> colorPacket(List<int> rgb, String type, int brightness) {
  if (rgb.length != 3 || [...rgb, brightness].any((v) => v < 0 || v > 255)) {
    throw ArgumentError('Channel values must be bytes');
  }
  if (type == 'floor') return [0x5a, 0, 1, ...rgb, 0, brightness, 0, 0xa5];
  if (type != 'ceiling' || brightness != 255) {
    throw ArgumentError('Unsupported color mode or brightness');
  }
  return [0x7e, 7, 5, 3, ...rgb, 0, 0xef];
}

List<int> whitePacket(int brightness) {
  if (brightness < 0 || brightness > 255) {
    throw ArgumentError('Invalid brightness');
  }
  return [0x5a, 0, 2, 0, 0, 0, 0, brightness, 0, 0xa5];
}

// UI/storage brightness remains normalized to 0..255. KS03~ uses percent on wire.
int deviceBrightness(int value, String prefix) {
  if (value < 0 || value > 255) throw ArgumentError('Invalid brightness');
  return prefix == 'KS03~' ? (value * 100 / 255).round() : value;
}
