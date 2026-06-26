import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/app_exception.dart';
import '../models/command.dart';
import '../models/device.dart';
import '../models/ota.dart';
import '../models/telemetry.dart';

final deviceServiceProvider = Provider<DeviceService>((ref) {
  return DeviceService(ref.read(dioProvider));
});

class DeviceService {
  DeviceService(this._dio);
  final Dio _dio;

  String _normalizeDeviceId(String value) => value.trim().toLowerCase();
  Map<String, dynamic> _bodyAsMap(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const ApiException(0, 'Unexpected server response');
  }

  List<Map<String, dynamic>> _bodyAsMapList(Object? data) {
    if (data is! List) {
      throw const ApiException(0, 'Unexpected server response');
    }
    return data.map((item) {
      if (item is Map) return Map<String, dynamic>.from(item);
      throw const ApiException(0, 'Unexpected server response');
    }).toList();
  }

  String _commandIdFromBody(Object? data) {
    final body = _bodyAsMap(data);
    final commandId = body['command_id'] as String?;
    if (commandId == null || commandId.isEmpty) {
      throw const ApiException(0, 'Unexpected server response');
    }
    return commandId;
  }

  String _requiredStringField(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value is String && value.isNotEmpty) return value;
    throw const ApiException(0, 'Unexpected server response');
  }

  bool _requiredBoolField(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value is bool) return value;
    throw const ApiException(0, 'Unexpected server response');
  }

  String _normalizeProvisioningHost(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('${ApiConfig.localProvisioningScheme}://') ||
        trimmed.startsWith('https://')) {
      return Uri.parse(trimmed).host;
    }
    return trimmed;
  }

  String _stringError(Map<String, dynamic>? body, String fallback) {
    return body?['error'] as String? ?? fallback;
  }

  Future<void> _waitForProvisioningApiReady(
    Dio localDio,
    String expectedDeviceId,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    DioException? lastError;

    while (DateTime.now().isBefore(deadline)) {
      try {
        final res = await localDio.get(ApiConfig.localInfoPath);
        final data = res.data;
        if (data is Map<String, dynamic>) {
          final actualDeviceId = _normalizeDeviceId(
            data['device_id'] as String? ?? '',
          );
          if (actualDeviceId == expectedDeviceId) {
            return;
          }
          if (actualDeviceId.isNotEmpty) {
            throw const ApiException(
              0,
              'Provisioning endpoint responded with a different device ID',
            );
          }
        }
      } on DioException catch (e) {
        lastError = e;
      }

      await Future.delayed(const Duration(milliseconds: 250));
    }

    if (lastError?.error is AppException) {
      throw lastError!.error as AppException;
    }
    throw const NetworkException(
      'Device provisioning API did not become ready in time',
    );
  }

  Future<ProvisionedDevice> provisionDevice({
    required String deviceId,
    required String name,
    required String homeId,
    String? roomId,
  }) async {
    try {
      final normalizedDeviceId = _normalizeDeviceId(deviceId);
      final res = await _dio.post('/devices', data: {
        'device_id': normalizedDeviceId,
        'name': name,
        'home_id': homeId,
        if (roomId != null) 'room_id': roomId,
      });
      final data = _bodyAsMap(res.data);
      final secretKey = data['secret_key'] as String?;
      if (secretKey == null || secretKey.isEmpty) {
        throw const ApiException(0, 'Provisioning response missing secret_key');
      }
      return ProvisionedDevice(
        device: Device.fromJson(data),
        secretKey: secretKey,
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Device> registerDevice({
    required String deviceId,
    required String name,
    required String homeId,
    String? roomId,
  }) async {
    final result = await provisionDevice(
      deviceId: deviceId,
      name: name,
      homeId: homeId,
      roomId: roomId,
    );
    return result.device;
  }

  Future<void> configureProvisionedDevice({
    required String host,
    required String deviceId,
    required String secretKey,
    String? brokerUri,
  }) async {
    final normalizedDeviceId = _normalizeDeviceId(deviceId);
    final normalizedHost = _normalizeProvisioningHost(host);
    final localDio = Dio(
      BaseOptions(
        baseUrl: '${ApiConfig.localProvisioningScheme}://$normalizedHost',
        connectTimeout: const Duration(seconds: 2),
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 2),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    await _waitForProvisioningApiReady(localDio, normalizedDeviceId);

    try {
      await localDio.post(ApiConfig.localConfigPath, data: {
        'device_id': normalizedDeviceId,
        'secret_key': secretKey,
        if (brokerUri != null && brokerUri.trim().isNotEmpty)
          'broker_uri': brokerUri.trim(),
      });
    } on DioException catch (e) {
      final body = e.response?.data is Map<String, dynamic>
          ? e.response?.data as Map<String, dynamic>
          : null;
      throw ApiException(
        e.response?.statusCode ?? 0,
        _stringError(body, 'Failed to send MQTT credentials to device'),
      );
    }
  }

  /// Returns true when the device has announced itself online via MQTT.
  /// Poll this after BLE credential write to confirm WiFi connect succeeded.
  Future<bool> checkAnnounce(String mac) async {
    try {
      final normalizedDeviceId = _normalizeDeviceId(mac);
      final res = await _dio.get('/devices/announce/$normalizedDeviceId');
      return _bodyAsMap(res.data)['announced'] == true;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<List<Device>> getDevices() async {
    try {
      final res = await _dio.get('/devices');
      return _bodyAsMapList(res.data).map(Device.fromJson).toList();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Device> updateDevice(String id, {String? name, String? roomId}) async {
    try {
      final normalizedDeviceId = _normalizeDeviceId(id);
      final res = await _dio.put('/devices/$normalizedDeviceId', data: {
        if (name != null) 'name': name,
        if (roomId != null) 'room_id': roomId,
      });
      return Device.fromJson(_bodyAsMap(res.data));
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<void> deleteDevice(String id) async {
    try {
      final normalizedDeviceId = _normalizeDeviceId(id);
      await _dio.delete('/devices/$normalizedDeviceId');
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<DeviceShadow> getShadow(String deviceId) async {
    try {
      final normalizedDeviceId = _normalizeDeviceId(deviceId);
      final res = await _dio.get('/devices/$normalizedDeviceId/shadow');
      return DeviceShadow.fromJson(_bodyAsMap(res.data));
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<DeviceOtaCatalog> getOtaCatalog(String deviceId) async {
    try {
      final normalizedDeviceId = _normalizeDeviceId(deviceId);
      final res = await _dio.get('/devices/$normalizedDeviceId/ota/versions');
      final body = _bodyAsMap(res.data);
      final versions = body['versions'];
      if (versions is! List) {
        throw const ApiException(0, 'Unexpected server response');
      }

      final parsedVersions = versions.map((item) {
        final versionBody = _bodyAsMap(item);
        return OtaVersionInfo(
          version: _requiredStringField(versionBody, 'version'),
          filename: _requiredStringField(versionBody, 'filename'),
          url: _requiredStringField(versionBody, 'url'),
        );
      }).toList();

      final currentVersion = body['current_version'];
      if (currentVersion != null && currentVersion is! String) {
        throw const ApiException(0, 'Unexpected server response');
      }

      return DeviceOtaCatalog(
        deviceId: _requiredStringField(body, 'device_id'),
        currentVersion: currentVersion as String?,
        deviceOnline: _requiredBoolField(body, 'device_online'),
        versions: parsedVersions,
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<void> startOtaUpdate(String deviceId, String version) async {
    try {
      final normalizedDeviceId = _normalizeDeviceId(deviceId);
      await _dio.post(
        '/devices/$normalizedDeviceId/ota',
        data: {'version': version},
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Updates the desired state of the device shadow.
  ///
  /// IMPORTANT: This is only for the declarative shadow keys the firmware
  /// currently supports (`mode`, `relay_1`, `relay_2`, `relay_3`).
  /// DO NOT use this for relay/mode command toggles;
  /// use [setRelay] or [setMode] instead for real-time control.
  Future<void> setDesired(String deviceId, Map<String, dynamic> desired) async {
    try {
      final normalizedDeviceId = _normalizeDeviceId(deviceId);
      await _dio.put('/devices/$normalizedDeviceId/shadow/desired',
          data: desired);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<String> sendCommand(
      String deviceId, Map<String, dynamic> payload) async {
    try {
      final normalizedDeviceId = _normalizeDeviceId(deviceId);
      final res = await _dio.post('/devices/$normalizedDeviceId/command',
          data: {'payload': payload});
      return _commandIdFromBody(res.data);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Sends a typed relay command for channel 1..3 and returns the command id.
  Future<String> setRelay(String deviceId, int channel, bool state) async {
    if (channel < 1 || channel > 3) {
      throw ArgumentError.value(channel, 'channel', 'must be between 1 and 3');
    }

    try {
      final normalizedDeviceId = _normalizeDeviceId(deviceId);
      final res = await _dio.post(
        '/devices/$normalizedDeviceId/relay/$channel',
        data: {'state': state},
      );
      return _commandIdFromBody(res.data);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  /// Sends a typed device mode command ('on' or 'off') and returns the command id.
  Future<String> setMode(String deviceId, String mode) async {
    if (mode != 'on' && mode != 'off') {
      throw ArgumentError.value(mode, 'mode', 'must be either on or off');
    }

    try {
      final normalizedDeviceId = _normalizeDeviceId(deviceId);
      final res = await _dio.post(
        '/devices/$normalizedDeviceId/mode',
        data: {'mode': mode},
      );
      return _commandIdFromBody(res.data);
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<void> setAutoMode(String deviceId, bool autoMode) async {
    try {
      final normalizedDeviceId = _normalizeDeviceId(deviceId);
      await _dio.put(
        '/devices/$normalizedDeviceId/auto_mode',
        data: {'auto_mode': autoMode},
      );
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<List<Command>> getCommands(String deviceId,
      {int limit = 50, int offset = 0}) async {
    try {
      final normalizedDeviceId = _normalizeDeviceId(deviceId);
      final res = await _dio.get('/devices/$normalizedDeviceId/commands',
          queryParameters: {'limit': limit, 'offset': offset});
      return _bodyAsMapList(res.data).map(Command.fromJson).toList();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  Future<Command> waitForCommandCompletion(
    String deviceId,
    String commandId, {
    Duration timeout = const Duration(minutes: 3),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final commands = await getCommands(deviceId, limit: 100);
      for (final command in commands) {
        if (command.id != commandId) continue;
        if (command.status == 'done' ||
            command.status == 'error' ||
            command.status == 'timeout') {
          return command;
        }
        break;
      }
      await Future.delayed(pollInterval);
    }
    throw TimeoutException(
      'Command did not finish within ${timeout.inMinutes} minute(s)',
    );
  }

  Future<List<TelemetryPoint>> getTelemetry(
    String deviceId, {
    DateTime? from,
    DateTime? to,
    String? agg,
    int limit = 1000,
  }) async {
    try {
      final now = DateTime.now();
      final normalizedDeviceId = _normalizeDeviceId(deviceId);
      final res = await _dio
          .get('/devices/$normalizedDeviceId/telemetry', queryParameters: {
        'from': (from ?? now.subtract(const Duration(hours: 24)))
            .toUtc()
            .toIso8601String(),
        'to': (to ?? now).toUtc().toIso8601String(),
        if (agg != null) 'agg': agg,
        'limit': limit,
      });
      return (res.data as List)
          .whereType<Map>()
          .map((e) => TelemetryPoint.tryFromJson(Map<String, dynamic>.from(e)))
          .whereType<TelemetryPoint>()
          .toList();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  AppException _map(DioException e) {
    if (e.error is AppException) return e.error as AppException;
    final body = e.response?.data;
    final msg = body is Map ? body['error'] as String? : null;
    return ApiException(e.response?.statusCode ?? 0, msg ?? 'Unknown error');
  }
}

class ProvisionedDevice {
  const ProvisionedDevice({
    required this.device,
    required this.secretKey,
  });

  final Device device;
  final String secretKey;
}
