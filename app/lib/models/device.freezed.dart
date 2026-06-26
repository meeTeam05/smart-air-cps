// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Device _$DeviceFromJson(Map<String, dynamic> json) {
  return _Device.fromJson(json);
}

/// @nodoc
mixin _$Device {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  @JsonKey(name: 'home_id')
  String get homeId => throw _privateConstructorUsedError;
  @JsonKey(name: 'room_id')
  String? get roomId => throw _privateConstructorUsedError;
  bool get online => throw _privateConstructorUsedError;
  @JsonKey(name: 'last_seen')
  DateTime? get lastSeen => throw _privateConstructorUsedError;
  @JsonKey(name: 'firmware_ver')
  String? get firmwareVer => throw _privateConstructorUsedError;
  String? get mode => throw _privateConstructorUsedError;
  @JsonKey(name: 'relay_1')
  bool? get relay1 => throw _privateConstructorUsedError;
  @JsonKey(name: 'relay_2')
  bool? get relay2 => throw _privateConstructorUsedError;
  @JsonKey(name: 'relay_3')
  bool? get relay3 => throw _privateConstructorUsedError;
  @JsonKey(name: 'auto_mode')
  bool get autoMode => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime? get createdAt => throw _privateConstructorUsedError;

  /// Serializes this Device to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Device
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DeviceCopyWith<Device> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DeviceCopyWith<$Res> {
  factory $DeviceCopyWith(Device value, $Res Function(Device) then) =
      _$DeviceCopyWithImpl<$Res, Device>;
  @useResult
  $Res call(
      {String id,
      String name,
      @JsonKey(name: 'home_id') String homeId,
      @JsonKey(name: 'room_id') String? roomId,
      bool online,
      @JsonKey(name: 'last_seen') DateTime? lastSeen,
      @JsonKey(name: 'firmware_ver') String? firmwareVer,
      String? mode,
      @JsonKey(name: 'relay_1') bool? relay1,
      @JsonKey(name: 'relay_2') bool? relay2,
      @JsonKey(name: 'relay_3') bool? relay3,
      @JsonKey(name: 'auto_mode') bool autoMode,
      @JsonKey(name: 'created_at') DateTime? createdAt});
}

/// @nodoc
class _$DeviceCopyWithImpl<$Res, $Val extends Device>
    implements $DeviceCopyWith<$Res> {
  _$DeviceCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Device
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? homeId = null,
    Object? roomId = freezed,
    Object? online = null,
    Object? lastSeen = freezed,
    Object? firmwareVer = freezed,
    Object? mode = freezed,
    Object? relay1 = freezed,
    Object? relay2 = freezed,
    Object? relay3 = freezed,
    Object? autoMode = null,
    Object? createdAt = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      homeId: null == homeId
          ? _value.homeId
          : homeId // ignore: cast_nullable_to_non_nullable
              as String,
      roomId: freezed == roomId
          ? _value.roomId
          : roomId // ignore: cast_nullable_to_non_nullable
              as String?,
      online: null == online
          ? _value.online
          : online // ignore: cast_nullable_to_non_nullable
              as bool,
      lastSeen: freezed == lastSeen
          ? _value.lastSeen
          : lastSeen // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      firmwareVer: freezed == firmwareVer
          ? _value.firmwareVer
          : firmwareVer // ignore: cast_nullable_to_non_nullable
              as String?,
      mode: freezed == mode
          ? _value.mode
          : mode // ignore: cast_nullable_to_non_nullable
              as String?,
      relay1: freezed == relay1
          ? _value.relay1
          : relay1 // ignore: cast_nullable_to_non_nullable
              as bool?,
      relay2: freezed == relay2
          ? _value.relay2
          : relay2 // ignore: cast_nullable_to_non_nullable
              as bool?,
      relay3: freezed == relay3
          ? _value.relay3
          : relay3 // ignore: cast_nullable_to_non_nullable
              as bool?,
      autoMode: null == autoMode
          ? _value.autoMode
          : autoMode // ignore: cast_nullable_to_non_nullable
              as bool,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DeviceImplCopyWith<$Res> implements $DeviceCopyWith<$Res> {
  factory _$$DeviceImplCopyWith(
          _$DeviceImpl value, $Res Function(_$DeviceImpl) then) =
      __$$DeviceImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      @JsonKey(name: 'home_id') String homeId,
      @JsonKey(name: 'room_id') String? roomId,
      bool online,
      @JsonKey(name: 'last_seen') DateTime? lastSeen,
      @JsonKey(name: 'firmware_ver') String? firmwareVer,
      String? mode,
      @JsonKey(name: 'relay_1') bool? relay1,
      @JsonKey(name: 'relay_2') bool? relay2,
      @JsonKey(name: 'relay_3') bool? relay3,
      @JsonKey(name: 'auto_mode') bool autoMode,
      @JsonKey(name: 'created_at') DateTime? createdAt});
}

/// @nodoc
class __$$DeviceImplCopyWithImpl<$Res>
    extends _$DeviceCopyWithImpl<$Res, _$DeviceImpl>
    implements _$$DeviceImplCopyWith<$Res> {
  __$$DeviceImplCopyWithImpl(
      _$DeviceImpl _value, $Res Function(_$DeviceImpl) _then)
      : super(_value, _then);

  /// Create a copy of Device
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? homeId = null,
    Object? roomId = freezed,
    Object? online = null,
    Object? lastSeen = freezed,
    Object? firmwareVer = freezed,
    Object? mode = freezed,
    Object? relay1 = freezed,
    Object? relay2 = freezed,
    Object? relay3 = freezed,
    Object? autoMode = null,
    Object? createdAt = freezed,
  }) {
    return _then(_$DeviceImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      homeId: null == homeId
          ? _value.homeId
          : homeId // ignore: cast_nullable_to_non_nullable
              as String,
      roomId: freezed == roomId
          ? _value.roomId
          : roomId // ignore: cast_nullable_to_non_nullable
              as String?,
      online: null == online
          ? _value.online
          : online // ignore: cast_nullable_to_non_nullable
              as bool,
      lastSeen: freezed == lastSeen
          ? _value.lastSeen
          : lastSeen // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      firmwareVer: freezed == firmwareVer
          ? _value.firmwareVer
          : firmwareVer // ignore: cast_nullable_to_non_nullable
              as String?,
      mode: freezed == mode
          ? _value.mode
          : mode // ignore: cast_nullable_to_non_nullable
              as String?,
      relay1: freezed == relay1
          ? _value.relay1
          : relay1 // ignore: cast_nullable_to_non_nullable
              as bool?,
      relay2: freezed == relay2
          ? _value.relay2
          : relay2 // ignore: cast_nullable_to_non_nullable
              as bool?,
      relay3: freezed == relay3
          ? _value.relay3
          : relay3 // ignore: cast_nullable_to_non_nullable
              as bool?,
      autoMode: null == autoMode
          ? _value.autoMode
          : autoMode // ignore: cast_nullable_to_non_nullable
              as bool,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DeviceImpl implements _Device {
  const _$DeviceImpl(
      {required this.id,
      required this.name,
      @JsonKey(name: 'home_id') required this.homeId,
      @JsonKey(name: 'room_id') this.roomId,
      this.online = false,
      @JsonKey(name: 'last_seen') this.lastSeen,
      @JsonKey(name: 'firmware_ver') this.firmwareVer,
      this.mode,
      @JsonKey(name: 'relay_1') this.relay1,
      @JsonKey(name: 'relay_2') this.relay2,
      @JsonKey(name: 'relay_3') this.relay3,
      @JsonKey(name: 'auto_mode') this.autoMode = false,
      @JsonKey(name: 'created_at') this.createdAt});

  factory _$DeviceImpl.fromJson(Map<String, dynamic> json) =>
      _$$DeviceImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  @JsonKey(name: 'home_id')
  final String homeId;
  @override
  @JsonKey(name: 'room_id')
  final String? roomId;
  @override
  @JsonKey()
  final bool online;
  @override
  @JsonKey(name: 'last_seen')
  final DateTime? lastSeen;
  @override
  @JsonKey(name: 'firmware_ver')
  final String? firmwareVer;
  @override
  final String? mode;
  @override
  @JsonKey(name: 'relay_1')
  final bool? relay1;
  @override
  @JsonKey(name: 'relay_2')
  final bool? relay2;
  @override
  @JsonKey(name: 'relay_3')
  final bool? relay3;
  @override
  @JsonKey(name: 'auto_mode')
  final bool autoMode;
  @override
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;

  @override
  String toString() {
    return 'Device(id: $id, name: $name, homeId: $homeId, roomId: $roomId, online: $online, lastSeen: $lastSeen, firmwareVer: $firmwareVer, mode: $mode, relay1: $relay1, relay2: $relay2, relay3: $relay3, autoMode: $autoMode, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DeviceImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.homeId, homeId) || other.homeId == homeId) &&
            (identical(other.roomId, roomId) || other.roomId == roomId) &&
            (identical(other.online, online) || other.online == online) &&
            (identical(other.lastSeen, lastSeen) ||
                other.lastSeen == lastSeen) &&
            (identical(other.firmwareVer, firmwareVer) ||
                other.firmwareVer == firmwareVer) &&
            (identical(other.mode, mode) || other.mode == mode) &&
            (identical(other.relay1, relay1) || other.relay1 == relay1) &&
            (identical(other.relay2, relay2) || other.relay2 == relay2) &&
            (identical(other.relay3, relay3) || other.relay3 == relay3) &&
            (identical(other.autoMode, autoMode) ||
                other.autoMode == autoMode) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, homeId, roomId, online,
      lastSeen, firmwareVer, mode, relay1, relay2, relay3, autoMode, createdAt);

  /// Create a copy of Device
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DeviceImplCopyWith<_$DeviceImpl> get copyWith =>
      __$$DeviceImplCopyWithImpl<_$DeviceImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DeviceImplToJson(
      this,
    );
  }
}

abstract class _Device implements Device {
  const factory _Device(
      {required final String id,
      required final String name,
      @JsonKey(name: 'home_id') required final String homeId,
      @JsonKey(name: 'room_id') final String? roomId,
      final bool online,
      @JsonKey(name: 'last_seen') final DateTime? lastSeen,
      @JsonKey(name: 'firmware_ver') final String? firmwareVer,
      final String? mode,
      @JsonKey(name: 'relay_1') final bool? relay1,
      @JsonKey(name: 'relay_2') final bool? relay2,
      @JsonKey(name: 'relay_3') final bool? relay3,
      @JsonKey(name: 'auto_mode') final bool autoMode,
      @JsonKey(name: 'created_at') final DateTime? createdAt}) = _$DeviceImpl;

  factory _Device.fromJson(Map<String, dynamic> json) = _$DeviceImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  @JsonKey(name: 'home_id')
  String get homeId;
  @override
  @JsonKey(name: 'room_id')
  String? get roomId;
  @override
  bool get online;
  @override
  @JsonKey(name: 'last_seen')
  DateTime? get lastSeen;
  @override
  @JsonKey(name: 'firmware_ver')
  String? get firmwareVer;
  @override
  String? get mode;
  @override
  @JsonKey(name: 'relay_1')
  bool? get relay1;
  @override
  @JsonKey(name: 'relay_2')
  bool? get relay2;
  @override
  @JsonKey(name: 'relay_3')
  bool? get relay3;
  @override
  @JsonKey(name: 'auto_mode')
  bool get autoMode;
  @override
  @JsonKey(name: 'created_at')
  DateTime? get createdAt;

  /// Create a copy of Device
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DeviceImplCopyWith<_$DeviceImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DeviceShadow _$DeviceShadowFromJson(Map<String, dynamic> json) {
  return _DeviceShadow.fromJson(json);
}

/// @nodoc
mixin _$DeviceShadow {
  Map<String, dynamic> get reported => throw _privateConstructorUsedError;
  Map<String, dynamic> get desired => throw _privateConstructorUsedError;
  @JsonKey(name: 'updatedAt')
  DateTime? get updatedAt => throw _privateConstructorUsedError;

  /// Serializes this DeviceShadow to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DeviceShadow
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DeviceShadowCopyWith<DeviceShadow> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DeviceShadowCopyWith<$Res> {
  factory $DeviceShadowCopyWith(
          DeviceShadow value, $Res Function(DeviceShadow) then) =
      _$DeviceShadowCopyWithImpl<$Res, DeviceShadow>;
  @useResult
  $Res call(
      {Map<String, dynamic> reported,
      Map<String, dynamic> desired,
      @JsonKey(name: 'updatedAt') DateTime? updatedAt});
}

/// @nodoc
class _$DeviceShadowCopyWithImpl<$Res, $Val extends DeviceShadow>
    implements $DeviceShadowCopyWith<$Res> {
  _$DeviceShadowCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DeviceShadow
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? reported = null,
    Object? desired = null,
    Object? updatedAt = freezed,
  }) {
    return _then(_value.copyWith(
      reported: null == reported
          ? _value.reported
          : reported // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      desired: null == desired
          ? _value.desired
          : desired // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DeviceShadowImplCopyWith<$Res>
    implements $DeviceShadowCopyWith<$Res> {
  factory _$$DeviceShadowImplCopyWith(
          _$DeviceShadowImpl value, $Res Function(_$DeviceShadowImpl) then) =
      __$$DeviceShadowImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {Map<String, dynamic> reported,
      Map<String, dynamic> desired,
      @JsonKey(name: 'updatedAt') DateTime? updatedAt});
}

/// @nodoc
class __$$DeviceShadowImplCopyWithImpl<$Res>
    extends _$DeviceShadowCopyWithImpl<$Res, _$DeviceShadowImpl>
    implements _$$DeviceShadowImplCopyWith<$Res> {
  __$$DeviceShadowImplCopyWithImpl(
      _$DeviceShadowImpl _value, $Res Function(_$DeviceShadowImpl) _then)
      : super(_value, _then);

  /// Create a copy of DeviceShadow
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? reported = null,
    Object? desired = null,
    Object? updatedAt = freezed,
  }) {
    return _then(_$DeviceShadowImpl(
      reported: null == reported
          ? _value._reported
          : reported // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      desired: null == desired
          ? _value._desired
          : desired // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DeviceShadowImpl implements _DeviceShadow {
  const _$DeviceShadowImpl(
      {final Map<String, dynamic> reported = const {},
      final Map<String, dynamic> desired = const {},
      @JsonKey(name: 'updatedAt') this.updatedAt})
      : _reported = reported,
        _desired = desired;

  factory _$DeviceShadowImpl.fromJson(Map<String, dynamic> json) =>
      _$$DeviceShadowImplFromJson(json);

  final Map<String, dynamic> _reported;
  @override
  @JsonKey()
  Map<String, dynamic> get reported {
    if (_reported is EqualUnmodifiableMapView) return _reported;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_reported);
  }

  final Map<String, dynamic> _desired;
  @override
  @JsonKey()
  Map<String, dynamic> get desired {
    if (_desired is EqualUnmodifiableMapView) return _desired;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_desired);
  }

  @override
  @JsonKey(name: 'updatedAt')
  final DateTime? updatedAt;

  @override
  String toString() {
    return 'DeviceShadow(reported: $reported, desired: $desired, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DeviceShadowImpl &&
            const DeepCollectionEquality().equals(other._reported, _reported) &&
            const DeepCollectionEquality().equals(other._desired, _desired) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_reported),
      const DeepCollectionEquality().hash(_desired),
      updatedAt);

  /// Create a copy of DeviceShadow
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DeviceShadowImplCopyWith<_$DeviceShadowImpl> get copyWith =>
      __$$DeviceShadowImplCopyWithImpl<_$DeviceShadowImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DeviceShadowImplToJson(
      this,
    );
  }
}

abstract class _DeviceShadow implements DeviceShadow {
  const factory _DeviceShadow(
          {final Map<String, dynamic> reported,
          final Map<String, dynamic> desired,
          @JsonKey(name: 'updatedAt') final DateTime? updatedAt}) =
      _$DeviceShadowImpl;

  factory _DeviceShadow.fromJson(Map<String, dynamic> json) =
      _$DeviceShadowImpl.fromJson;

  @override
  Map<String, dynamic> get reported;
  @override
  Map<String, dynamic> get desired;
  @override
  @JsonKey(name: 'updatedAt')
  DateTime? get updatedAt;

  /// Create a copy of DeviceShadow
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DeviceShadowImplCopyWith<_$DeviceShadowImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
