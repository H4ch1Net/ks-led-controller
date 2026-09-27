import 'dart:async';

import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> awaitBluetoothReady(
  Stream<BleStatus> statuses, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  // Android permission grant and the plugin's status cache update independently.
  final status = await statuses
      .firstWhere((s) => s != BleStatus.unknown && s != BleStatus.unauthorized)
      .timeout(timeout, onTimeout: () => BleStatus.unauthorized);
  if (status != BleStatus.ready) {
    throw StateError('Bluetooth not ready: $status');
  }
}

class Light {
  const Light(this.id, this.name, this.profile);
  final String id;
  final String name;
  final Map<String, dynamic> profile;
}

abstract class LightBackend {
  Future<List<Light>> scan(List<Map<String, dynamic>> profiles);
  Future<void> send(Light light, List<List<int>> packets);
  Future<LightSession> openSession(Light light) async => LightSession(
    write: (packets) => send(light, packets),
    disconnect: () async {},
  );
}

/// One owner, one write at a time; closing is idempotent.
class LightSession {
  LightSession({
    required this.write,
    required this.disconnect,
    this.notifications,
    this.read,
  });
  final Stream<List<int>> Function()? notifications;
  final Future<List<int>> Function()? read;
  final Future<void> Function(List<List<int>>) write;
  final Future<void> Function() disconnect;
  bool _closed = false, _writing = false;
  Future<void> send(List<List<int>> packets) async {
    if (_closed || _writing) throw StateError('Session closed or busy');
    _writing = true;
    try {
      await write(packets);
    } finally {
      _writing = false;
    }
  }

  Future<List<int>> queryState() async {
    if (_closed || notifications == null) {
      throw StateError('State readback unavailable');
    }
    final reply = Completer<List<int>>();
    final result = reply.future.timeout(const Duration(seconds: 4));
    result.ignore();
    final sub = notifications!().listen(
      (data) {
        debugPrint(
          'KS notification: ${data.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}',
        );
        if (data.length >= 2 &&
            data[0] == 0x5f &&
            data[1] == 2 &&
            !reply.isCompleted) {
          reply.complete(List.of(data));
        }
      },
      onError: (Object e) {
        if (!reply.isCompleted) reply.completeError(e);
      },
    );
    try {
      // Allow notification subscription setup before requesting a reply.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await send([
        [0x5f, 1, 0, 0xf5],
      ]);
      if (read != null) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final data = await read!().timeout(const Duration(seconds: 3));
        if (!reply.isCompleted) reply.complete(data);
      }
      return await result;
    } finally {
      await sub.cancel();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await disconnect();
  }
}

class DemoBackend extends LightBackend {
  final List<List<int>> sent = [];
  @override
  Future<List<Light>> scan(List<Map<String, dynamic>> profiles) async =>
      profiles
          .where((p) => p['prefix'] == 'KS03~')
          .map((p) => Light('demo', 'Demo floor lamp', p))
          .toList();
  @override
  Future<void> send(Light light, List<List<int>> packets) async {
    sent.addAll(packets);
  }
}

class BluetoothBackend extends LightBackend {
  // Opening the saved catalog should not initialize Bluetooth.
  late final FlutterReactiveBle ble = FlutterReactiveBle();
  Uuid uuid(String short) =>
      Uuid.parse('0000$short-0000-1000-8000-00805f9b34fb');
  Future<void> permissions() async {
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    final required = sdk >= 31
        ? [Permission.bluetoothScan, Permission.bluetoothConnect]
        : [Permission.locationWhenInUse];
    final statuses = await required.request();
    if (statuses.values.any((s) => !s.isGranted)) {
      throw StateError('Grant Bluetooth access in app settings, then retry.');
    }
    await awaitBluetoothReady(ble.statusStream);
  }

  @override
  Future<List<Light>> scan(List<Map<String, dynamic>> profiles) async {
    await permissions();
    final found = <String, Light>{};
    final done = Completer<void>();
    final subscription = ble
        .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
        .listen(
          (device) {
            for (final profile in profiles) {
              if (device.name.startsWith(profile['prefix'] as String)) {
                found[device.id] = Light(device.id, device.name, profile);
                break;
              }
            }
          },
          onError: (Object error) {
            if (!done.isCompleted) done.completeError(error);
          },
        );
    final timer = Timer(const Duration(seconds: 8), () {
      if (!done.isCompleted) done.complete();
    });
    try {
      await done.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
    return found.values.toList();
  }

  @override
  Future<void> send(Light light, List<List<int>> packets) async {
    final session = await openSession(light);
    try {
      await session.send(packets);
    } finally {
      await session.close();
    }
  }

  @override
  Future<LightSession> openSession(Light light) async {
    const channel = MethodChannel('dev.kslight/settings');
    final owner = await channel.invokeMethod<String>('acquireBluetooth');
    try {
      final session = await _openUnlocked(light);
      return LightSession(
        notifications: session.notifications,
        read: session.read,
        write: (packets) async {
          await session.send(packets);
          for (final packet in packets) {
            if (packet.length == 4 && packet[0] == 0x5b) {
              await channel.invokeMethod<void>('shortcutPower', {
                'id': light.id,
                'on': packet[1] == 0xf0,
              });
            }
          }
        },
        disconnect: () async {
          try {
            await session.close();
          } finally {
            await channel.invokeMethod<void>('releaseBluetooth', owner);
          }
        },
      );
    } catch (_) {
      await channel.invokeMethod<void>('releaseBluetooth', owner);
      rethrow;
    }
  }

  Future<LightSession> _openUnlocked(Light light) async {
    await permissions();
    final connected = Completer<void>();
    Object? connectionError;
    final subscription = ble
        .connectToDevice(
          id: light.id,
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
          (update) {
            if (update.connectionState == DeviceConnectionState.connected &&
                !connected.isCompleted) {
              connected.complete();
            } else if (update.connectionState ==
                DeviceConnectionState.disconnected) {
              connectionError = StateError('Light disconnected');
              if (!connected.isCompleted) {
                connected.completeError(connectionError!);
              }
            }
          },
          onError: (Object error) {
            connectionError = error;
            if (!connected.isCompleted) connected.completeError(error);
          },
        );
    try {
      await connected.future.timeout(const Duration(seconds: 12));
      await ble
          .discoverAllServices(light.id)
          .timeout(const Duration(seconds: 8));
      final services = await ble
          .getDiscoveredServices(light.id)
          .timeout(const Duration(seconds: 5));
      final serviceId = uuid(light.profile['service'] as String);
      final characteristicId = uuid(light.profile['write'] as String);
      final found = services.where((s) => s.id == serviceId).toList();
      if (found.length != 1) {
        throw StateError('Configured service missing or ambiguous');
      }
      final chars = found.single.characteristics
          .where((c) => c.id == characteristicId)
          .toList();
      if (chars.length != 1) {
        throw StateError('Configured characteristic missing or ambiguous');
      }
      if (!chars.single.isWritableWithoutResponse &&
          !chars.single.isWritableWithResponse) {
        throw StateError('Characteristic is not writable');
      }
      return LightSession(
        notifications: light.profile['prefix'] == 'KS03~'
            ? () => ble.subscribeToCharacteristic(
                QualifiedCharacteristic(
                  deviceId: light.id,
                  serviceId: serviceId,
                  characteristicId: uuid('AFD2'),
                ),
              )
            : null,
        read: light.profile['prefix'] == 'KS03~'
            ? () => ble.readCharacteristic(
                QualifiedCharacteristic(
                  deviceId: light.id,
                  serviceId: serviceId,
                  characteristicId: uuid('AFD3'),
                ),
              )
            : null,
        write: (packets) async {
          for (var i = 0; i < packets.length; i++) {
            if (connectionError != null) throw connectionError!;
            await chars.single
                .write(
                  packets[i],
                  withResponse: !chars.single.isWritableWithoutResponse,
                )
                .timeout(const Duration(seconds: 5));
            // Allow power-on to settle before the initial color command.
            if (i + 1 < packets.length) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
          }
          if (connectionError != null) throw connectionError!;
        },
        disconnect: () async {
          // A no-response write completing is not physical delivery confirmation.
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await subscription.cancel();
        },
      );
    } catch (_) {
      await subscription.cancel();
      rethrow;
    }
  }
}
