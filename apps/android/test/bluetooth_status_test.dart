import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:ks_light/light_backend.dart';

void main() {
  test('waits past stale unauthorized status after permission grant', () async {
    await awaitBluetoothReady(
      Stream.fromIterable([
        BleStatus.unknown,
        BleStatus.unauthorized,
        BleStatus.ready,
      ]),
    );
  });
  test('powered off remains an actionable error', () async {
    await expectLater(
      awaitBluetoothReady(Stream.value(BleStatus.poweredOff)),
      throwsStateError,
    );
  });
  test('unauthorized status has a bounded wait', () async {
    final controller = StreamController<BleStatus>();
    final result = awaitBluetoothReady(
      controller.stream,
      timeout: const Duration(milliseconds: 10),
    );
    controller.add(BleStatus.unauthorized);
    await expectLater(result, throwsStateError);
    await controller.close();
  });
}
