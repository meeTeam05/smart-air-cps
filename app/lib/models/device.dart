import 'package:freezed_annotation/freezed_annotation.dart';

part 'device.freezed.dart';
part 'device.g.dart';

@freezed
class Device with _$Device {
  const factory Device({
    required String id,
    required String name,
    @JsonKey(name: 'home_id') required String homeId,
    @JsonKey(name: 'room_id') String? roomId,
    @Default(false) bool online,
    @JsonKey(name: 'last_seen') DateTime? lastSeen,
    @JsonKey(name: 'firmware_ver') String? firmwareVer,
    String? mode,
    @JsonKey(name: 'relay_1') bool? relay1,
    @JsonKey(name: 'relay_2') bool? relay2,
    @JsonKey(name: 'relay_3') bool? relay3,
    @JsonKey(name: 'auto_mode') @Default(false) bool autoMode,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _Device;

  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);
}

@freezed
class DeviceShadow with _$DeviceShadow {
  const factory DeviceShadow({
    @Default({}) Map<String, dynamic> reported,
    @Default({}) Map<String, dynamic> desired,
    @JsonKey(name: 'updatedAt') DateTime? updatedAt,
  }) = _DeviceShadow;

  factory DeviceShadow.fromJson(Map<String, dynamic> json) =>
      _$DeviceShadowFromJson(json);
}
