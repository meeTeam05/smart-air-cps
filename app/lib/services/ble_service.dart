import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_config.dart';
import 'ble_models.dart';

/// Singleton that owns the full BLE lifecycle for Smart Air provisioning + test mode.
///
/// Usage (provisioning):
/// ```dart
/// final service = BleService();
/// await service.ensurePermissions();
/// service.scan().listen(...);
/// await service.connect(mac);
/// await service.sendCredentials(ssid, pass);
/// final json = await service.notifyStream.timeout(...).firstWhere(...);
/// await service.disconnect();
/// ```
class BleService {
  BleService._();
  static final instance = BleService._();

  // Allow constructing non-singleton instances for screens that manage lifecycle
  factory BleService() => instance;

  static const MethodChannel _settingsChannel = MethodChannel(
    'mt_home/settings',
  );

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _notifySub;

  // ── Permission ─────────────────────────────────────────────────────────────

  Future<int> _androidSdkInt() async {
    if (!Platform.isAndroid) return 0;
    final sdk = await _settingsChannel.invokeMethod<int>('getAndroidSdkInt');
    return sdk ?? 0;
  }

  List<Permission> _requiredBlePermissions(int androidSdkInt) {
    if (Platform.isAndroid && androidSdkInt < 31) {
      return [Permission.locationWhenInUse];
    }
    return [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ];
  }

  bool _permissionGranted(PermissionStatus status) {
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  }

  /// Returns the first blocker that must be fixed before BLE scanning.
  Future<BlePreflightStatus> checkPreflight() async {
    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      return BlePreflightStatus.unsupported;
    }

    final androidSdkInt = await _androidSdkInt();
    final permissions = _requiredBlePermissions(androidSdkInt);
    final statuses = await permissions.request();
    final permissionStatuses = statuses.values;
    if (permissionStatuses.any((status) => status.isPermanentlyDenied)) {
      return BlePreflightStatus.permissionPermanentlyDenied;
    }
    if (permissionStatuses.any((status) => !_permissionGranted(status))) {
      return BlePreflightStatus.permissionDenied;
    }

    final state = await adapterState;
    if (state != BluetoothAdapterState.on) {
      return BlePreflightStatus.bluetoothOff;
    }

    if (Platform.isAndroid && androidSdkInt > 0 && androidSdkInt < 31) {
      final locationStatus = await Permission.locationWhenInUse.serviceStatus;
      if (locationStatus != ServiceStatus.enabled) {
        return BlePreflightStatus.locationOff;
      }
    }

    return BlePreflightStatus.ready;
  }

  /// Returns true if all BLE scan preflight checks pass.
  Future<bool> ensurePermissions() async {
    return await checkPreflight() == BlePreflightStatus.ready;
  }

  Future<void> openBluetoothSettings() async {
    await _settingsChannel.invokeMethod<void>('openBluetoothSettings');
  }

  Future<void> openLocationSettings() async {
    await _settingsChannel.invokeMethod<void>('openLocationSettings');
  }

  Future<void> openPermissionSettings() async {
    await openAppSettings();
  }

  // ── Adapter state ──────────────────────────────────────────────────────────

  /// Single current adapter state snapshot.
  Future<BluetoothAdapterState> get adapterState async =>
      FlutterBluePlus.adapterState.first;

  // ── Scan ───────────────────────────────────────────────────────────────────

  /// Scans for nearby Smart Air BLE devices.
  ///
  /// Emits [BleDeviceInfo] for each result that matches [SmartAirGatt.deviceNamePrefix].
  /// The stream completes after [timeout] (default 10 s) or when [stopScan] is called.
  Stream<BleDeviceInfo> scan({Duration timeout = const Duration(seconds: 12)}) {
    final controller = StreamController<BleDeviceInfo>.broadcast();

    FlutterBluePlus.startScan(
      timeout: timeout,
      androidScanMode: AndroidScanMode.lowLatency,
    );

    final sub = FlutterBluePlus.onScanResults.listen(
      (results) {
        for (final r in results) {
          // Prefer advName (from BLE advertisement/scan-response packet).
          // platformName is the Android cache — empty for unseen devices.
          final advName = r.advertisementData.advName.trim();
          final platformName = r.device.platformName.trim();
          final name = advName.isNotEmpty
              ? advName
              : platformName.isNotEmpty
                  ? platformName
                  : 'Unknown (${r.device.remoteId.str.substring(r.device.remoteId.str.length - 5)})';

          if (!BleConfig.matchesProvisioningName(name)) continue;

          controller.add(BleDeviceInfo(
            remoteId: r.device.remoteId.str,
            name: name,
            rssi: r.rssi,
          ));
        }
      },
      onError: controller.addError,
    );

    // Guard: only close the controller after the scan has actually started.
    // FlutterBluePlus.isScanning is a ValueStream that emits its current value
    // (false) immediately on listen(). Without this guard, the controller would
    // close before startScan() marks isScanning = true, dropping all results.
    bool scanStarted = false;
    StreamSubscription<bool>? isScanSub;
    isScanSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (scanning) scanStarted = true;
      if (!scanning && scanStarted && !controller.isClosed) {
        sub.cancel();
        isScanSub?.cancel();
        controller.close();
      }
    });

    return controller.stream;
  }

  /// Stop an in-progress scan early.
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  // ── Provisioning ───────────────────────────────────────────────────────────

  final _notifyController = StreamController<String>.broadcast();

  /// Stream of JSON strings received on the notify characteristic (0xFF03).
  Stream<String> get notifyStream => _notifyController.stream;

  /// Connect to a device by MAC address for provisioning.
  Future<void> connect(String mac) async {
    await disconnect();
    _device = BluetoothDevice.fromId(mac);
    try {
      await _device!.connect(timeout: const Duration(seconds: 10), mtu: null);
      // Request larger MTU so notify payloads (JSON ~70 bytes) arrive in one packet.
      // Default BLE MTU payload is 20 bytes which fragments our JSON.
      await _device!.requestMtu(256);
    } catch (e) {
      _device = null;
      throw BleException('Connection failed: $e');
    }
  }

  /// Write SSID and password to provisioning characteristics, wait for device
  /// to connect WiFi, then return its reported device id and local IP.
  ///
  /// Keeps BLE connected until the notify arrives (device sends it after
  /// WiFi connect, up to [timeout]). Throws [BleException] on failure or timeout.
  Future<BleProvisioningResult> sendCredentials(
    String ssid,
    String password, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_device == null) throw const BleException('Not connected');

    final services = await _device!.discoverServices();
    final svc = services.firstWhere(
      (s) => s.uuid.str128.toLowerCase() == SmartAirGatt.serviceUuid,
      orElse: () => throw const BleException('Provisioning service not found'),
    );

    BluetoothCharacteristic? ssidChar;
    BluetoothCharacteristic? passChar;
    BluetoothCharacteristic? notifyChar;

    for (final c in svc.characteristics) {
      final uuid = c.uuid.str128.toLowerCase();
      if (uuid == SmartAirGatt.provSsidCharUuid) ssidChar = c;
      if (uuid == SmartAirGatt.provPassCharUuid) passChar = c;
      if (uuid == SmartAirGatt.provNotifyCharUuid) notifyChar = c;
    }

    if (ssidChar == null || passChar == null || notifyChar == null) {
      throw const BleException('Provisioning characteristics not found');
    }

    // Subscribe notify before writing credentials so we don't miss the response
    await notifyChar.setNotifyValue(true);
    await _notifySub?.cancel();
    final buffer = StringBuffer();
    _notifySub = notifyChar.onValueReceived.listen((data) {
      buffer.write(utf8.decode(data));
      // Emit to stream only when we have a complete JSON object
      final s = buffer.toString();
      if (s.contains('{') && s.contains('}')) {
        if (!_notifyController.isClosed) {
          _notifyController.add(s);
        }
        buffer.clear();
      }
    });

    await ssidChar.write(utf8.encode(ssid), withoutResponse: false);
    await passChar.write(utf8.encode(password), withoutResponse: false);

    // Wait for the notify — device sends it after WiFi connect attempt
    final String jsonStr;
    try {
      jsonStr = await notifyStream
          .timeout(timeout, onTimeout: (sink) => sink.close())
          .first;
    } catch (_) {
      throw BleException(
          'Timed out waiting for device response (${timeout.inSeconds}s)');
    }

    final Map<String, dynamic> result;
    try {
      result = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      throw BleException('Invalid response from device: $jsonStr');
    }

    if (result['status'] != 'ok') {
      throw const BleException(
          'Device failed to connect to WiFi — check password');
    }

    final deviceId = result['device_id'] as String?;
    if (deviceId == null || deviceId.isEmpty) {
      throw const BleException('Device did not report its ID');
    }

    final ip = result['ip'] as String?;
    if (ip == null || ip.trim().isEmpty) {
      throw const BleException('Device did not report its local IP');
    }

    return BleProvisioningResult(
      deviceId: deviceId.trim().toLowerCase(),
      ip: ip.trim(),
    );
  }

  // ── Connect + read ─────────────────────────────────────────────────────────

  /// Connects to a device and reads one [SensorSnapshot].
  ///
  /// Throws a [BleException] on connection or read failure.
  Future<SensorSnapshot?> connectAndRead(BleDeviceInfo info) async {
    await disconnect(); // clean up any previous connection

    _device = BluetoothDevice.fromId(info.remoteId);

    try {
      // mtu: null — skip automatic requestMtu(512) which causes
      // PlatformException(requestMtu, device is disconnected) on some Android
      // versions when the peripheral doesn't respond to MTU exchange in time.
      await _device!.connect(timeout: const Duration(seconds: 10), mtu: null);
    } catch (e) {
      throw BleException('Connection failed: $e');
    }

    try {
      final services = await _device!.discoverServices();
      final svc = services.firstWhere(
        (s) => s.uuid.str128.toLowerCase() == SmartAirGatt.serviceUuid,
        orElse: () => throw const BleException(
          'Smart Air GATT service not found.\n'
          'Check UUID: ${SmartAirGatt.serviceUuid}',
        ),
      );

      double? temp;
      double? hum;

      for (final char in svc.characteristics) {
        final uuid = char.uuid.str128.toLowerCase();

        if (uuid == SmartAirGatt.tempCharUuid) {
          final raw = await char.read();
          final snap = SensorSnapshot.fromBytes(raw);
          temp = snap?.temperature;
        }

        if (uuid == SmartAirGatt.humCharUuid) {
          final raw = await char.read();
          final snap = SensorSnapshot.fromBytes(raw);
          hum = snap?.humidity;
        }
      }

      if (temp == null || hum == null) return null;

      return SensorSnapshot(
        temperature: temp,
        humidity: hum,
        ts: DateTime.now(),
      );
    } catch (e) {
      if (e is BleException) rethrow;
      throw BleException('Read failed: $e');
    }
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────

  /// Disconnects from the current device (no-op if not connected).
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {
        // Ignore disconnect errors — device may already be gone
      }
      _device = null;
    }
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await stopScan();
    await disconnect();
  }
}

// ── Exception ─────────────────────────────────────────────────────────────────

class BleException implements Exception {
  final String message;
  const BleException(this.message);

  @override
  String toString() => 'BleException: $message';
}
