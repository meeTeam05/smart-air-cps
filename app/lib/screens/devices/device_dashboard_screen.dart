import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_theme.dart';
import '../../core/back_navigation.dart';
import '../../models/command.dart';
import '../../models/device.dart';
import '../../models/telemetry.dart';
import '../../providers/devices_provider.dart';
import '../../services/device_service.dart';
import '../../widgets/shell/atmosphere_app_bar.dart';
import '../../widgets/atoms/mode_card.dart';
import '../../widgets/atoms/sensor_tile.dart';
import '../../widgets/atoms/relay_card.dart';
import '../../widgets/atoms/history_row.dart';
import '../../widgets/atoms/pill.dart';
import '../../widgets/atoms/card.dart';

const _commandPendingUiTimeout = Duration(seconds: 5);
const _shadowRefreshGrace = Duration(seconds: 1);

enum _PendingControlKind { mode, relay }

class _PendingControlAction {
  _PendingControlAction.mode({
    required this.commandId,
    required this.expectedMode,
  })  : kind = _PendingControlKind.mode,
        channel = null,
        expectedRelayState = null;

  _PendingControlAction.relay({
    required this.commandId,
    required this.channel,
    required this.expectedRelayState,
  })  : kind = _PendingControlKind.relay,
        expectedMode = null;

  final String commandId;
  final _PendingControlKind kind;
  final int? channel;
  final String? expectedMode;
  final bool? expectedRelayState;
  Timer? queueTimer;
  Timer? shadowRefreshTimer;
  bool queuedNoticeShown = false;
}

class DeviceDashboardScreen extends ConsumerStatefulWidget {
  const DeviceDashboardScreen({super.key, required this.deviceId});
  final String deviceId;

  @override
  ConsumerState<DeviceDashboardScreen> createState() =>
      _DeviceDashboardScreenState();
}

class _DeviceDashboardScreenState extends ConsumerState<DeviceDashboardScreen> {
  bool _modeLoading = false;
  final Map<int, bool> _relayLoading = {};
  bool _refreshing = false;
  bool _autoModeLoading = false;
  _PendingControlAction? _pendingModeAction;
  final Map<int, _PendingControlAction> _pendingRelayActions = {};

  @override
  void dispose() {
    _cancelPendingAction(_pendingModeAction);
    for (final action in _pendingRelayActions.values) {
      _cancelPendingAction(action);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    final devicesAsync = ref.watch(devicesProvider);
    final device = devicesAsync.valueOrNull
        ?.where((d) => d.id == widget.deviceId)
        .firstOrNull;

    final shadowAsync = ref.watch(shadowProvider(widget.deviceId));
    final shadow = shadowAsync.valueOrNull;

    final reported = shadow?.reported ?? {};
    final reportedMode = (reported['mode'] as String?)?.toLowerCase();
    final mode = reportedMode == 'on' ? 'on' : 'off';
    final isOn = mode.toLowerCase() == 'on';
    final relay1 = reported['relay_1'] as bool? ?? false;
    final relay2 = reported['relay_2'] as bool? ?? false;
    final relay3 = reported['relay_3'] as bool? ?? false;
    final autoMode = device?.autoMode ?? false;

    final telemetryLiveAsync =
        ref.watch(telemetryLiveProvider(widget.deviceId));
    final telemetryState = telemetryLiveAsync.valueOrNull;
    final telemetryPoints = telemetryState?.points ?? const <TelemetryPoint>[];
    final latestTelemetry = telemetryState?.latest;
    final commandsAsync = ref.watch(commandsProvider(widget.deviceId));
    final recentCommands = commandsAsync.valueOrNull ?? const <Command>[];
    ref.listen<AsyncValue<List<Command>>>(
      commandsProvider(widget.deviceId),
      _handleCommandsChanged,
    );
    ref.listen<AsyncValue<DeviceShadow>>(
      shadowProvider(widget.deviceId),
      _handleShadowChanged,
    );
    final blockingError = _blockingErrorMessage(
      device: device,
      devicesAsync: devicesAsync,
      shadow: shadow,
      shadowAsync: shadowAsync,
      telemetryState: telemetryState,
      telemetryLiveAsync: telemetryLiveAsync,
    );
    final blockingLoad = _isBlockingLoad(
      device: device,
      devicesAsync: devicesAsync,
      shadow: shadow,
      shadowAsync: shadowAsync,
      telemetryState: telemetryState,
      telemetryLiveAsync: telemetryLiveAsync,
    );

    if (blockingError != null) {
      return _buildBlockingStateScaffold(
        title: device?.name ?? widget.deviceId,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.warn, size: 36, color: c.danger),
            const SizedBox(height: AtmosphereTokens.space16),
            Text(
              'Unable to load device dashboard.',
              textAlign: TextAlign.center,
              style: AtmosphereTextStyles.h2(c.ink),
            ),
            const SizedBox(height: AtmosphereTokens.space8),
            Text(
              blockingError,
              textAlign: TextAlign.center,
              style: AtmosphereTextStyles.body(c.ink2),
            ),
            const SizedBox(height: AtmosphereTokens.space20),
            FilledButton(
              onPressed: () => _refreshLiveData(refreshDevices: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (blockingLoad) {
      return _buildBlockingStateScaffold(
        title: device?.name ?? widget.deviceId,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AtmosphereTokens.space16),
            Text(
              'Loading device dashboard…',
              textAlign: TextAlign.center,
              style: AtmosphereTextStyles.h2(c.ink),
            ),
          ],
        ),
      );
    }

    final temp =
        latestTelemetry?.temperature ?? reported['temperature'] as num?;
    final humidity = latestTelemetry?.humidity ?? reported['humidity'] as num?;
    final coPpm = latestTelemetry?.coPpm ?? reported['co_ppm'] as num?;
    final no2Ppm = latestTelemetry?.no2Ppm ?? reported['no2_ppm'] as num?;
    // Keep at most 30 recent points so the mini sparkline stays readable.
    List<double> trimSparkline(List<double> l) =>
        l.length > 30 ? l.sublist(l.length - 30) : l;

    final tempSparkline = trimSparkline(telemetryPoints
        .where((p) => p.temperature != null)
        .map((p) => p.temperature!)
        .toList());
    final humiditySparkline = trimSparkline(telemetryPoints
        .where((p) => p.humidity != null)
        .map((p) => p.humidity!)
        .toList());
    final coSparkline = trimSparkline(telemetryPoints
        .where((p) => p.coPpm != null)
        .map((p) => p.coPpm!)
        .toList());
    final no2Sparkline = trimSparkline(telemetryPoints
        .where((p) => p.no2Ppm != null)
        .map((p) => p.no2Ppm!)
        .toList());

    final statusText = _presenceText(device);

    return BackNavigationScope(
      fallbackRoute: '/home',
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AtmosphereAppBar.back(
          title: device?.name ?? widget.deviceId,
          onBack: () => handleBackOrFallback(context, '/home'),
          actions: [
            IconButton(
              icon: Icon(AppIcons.cog, color: c.ink),
              tooltip: 'Device settings',
              onPressed: () =>
                  context.push('/devices/${widget.deviceId}/settings'),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => _refreshLiveData(refreshDevices: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AtmosphereTokens.space20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compactSensors =
                    constraints.maxWidth < 360 || textScale > 1.4;
                final sensorColumns = compactSensors ? 1 : 2;
                final relayColumns = textScale > 1.7
                    ? 1
                    : constraints.maxWidth >= 360
                        ? 2
                        : 1;
                final relayWidth = (constraints.maxWidth -
                        ((relayColumns - 1) * AtmosphereTokens.space12)) /
                    relayColumns;

                final sensorTiles = [
                  SensorTile(
                    value: temp?.toStringAsFixed(2),
                    unit: '°C',
                    label: 'Temperature',
                    icon: AppIcons.temp,
                    tone: SensorTone.warm,
                    sparkColor: c.danger,
                    sparklineData:
                        tempSparkline.isNotEmpty ? tempSparkline : null,
                    dimmed: !isOn,
                  ),
                  SensorTile(
                    value: humidity?.toStringAsFixed(2),
                    unit: '%',
                    label: 'Humidity',
                    icon: AppIcons.humidity,
                    tone: SensorTone.air,
                    sparkColor: c.accent,
                    sparklineData:
                        humiditySparkline.isNotEmpty ? humiditySparkline : null,
                    dimmed: !isOn,
                  ),
                  SensorTile(
                    value: coPpm?.toStringAsFixed(2),
                    unit: 'ppm',
                    label: 'CO',
                    icon: AppIcons.cloud,
                    tone: SensorTone.cool,
                    sparkColor: c.brand,
                    sparklineData: coSparkline.isNotEmpty ? coSparkline : null,
                    dimmed: !isOn,
                  ),
                  SensorTile(
                    value: no2Ppm?.toStringAsFixed(2),
                    unit: 'ppm',
                    label: 'NO₂',
                    icon: AppIcons.smog,
                    tone: SensorTone.no2,
                    sparkColor: const Color(0xFF7A4FD0),
                    sparklineData:
                        no2Sparkline.isNotEmpty ? no2Sparkline : null,
                    dimmed: !isOn,
                  ),
                ];

                final relayCards = [
                  RelayCard(
                    channel: 1,
                    name: 'Fan',
                    on: relay1,
                    disabled: !isOn || autoMode || _relayLoading[1] == true,
                    onTap: () => _handleRelayToggle(1, relay1, isOn, autoMode),
                  ),
                  RelayCard(
                    channel: 2,
                    name: 'Lamp',
                    on: relay2,
                    disabled: !isOn || autoMode || _relayLoading[2] == true,
                    onTap: () => _handleRelayToggle(2, relay2, isOn, autoMode),
                  ),
                  RelayCard(
                    channel: 3,
                    name: 'Filter',
                    on: relay3,
                    disabled: !isOn || autoMode || _relayLoading[3] == true,
                    onTap: () => _handleRelayToggle(3, relay3, isOn, autoMode),
                  ),
                ];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      container: true,
                      sortKey: const OrdinalSortKey(0),
                      header: true,
                      label: '${device?.name ?? widget.deviceId}, $statusText',
                      child: ExcludeSemantics(
                        child: Text(
                          statusText,
                          style: AtmosphereTextStyles.caption(c.ink3),
                        ),
                      ),
                    ),
                    const SizedBox(height: AtmosphereTokens.space16),
                    Semantics(
                      container: true,
                      sortKey: const OrdinalSortKey(1),
                      child: DeviceModeCard(
                        mode: mode,
                        online: device?.online ?? false,
                        onChanged: _modeLoading
                            ? null
                            : (value) => _handleModeToggle(value),
                      ),
                    ),
                    const SizedBox(height: AtmosphereTokens.space20),
                    Semantics(
                      container: true,
                      sortKey: const OrdinalSortKey(2),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: sensorColumns,
                          mainAxisSpacing: AtmosphereTokens.space12,
                          crossAxisSpacing: AtmosphereTokens.space12,
                          mainAxisExtent: compactSensors ? 176 : 168,
                        ),
                        itemCount: sensorTiles.length,
                        itemBuilder: (context, index) => sensorTiles[index],
                      ),
                    ),
                    const SizedBox(height: AtmosphereTokens.space24),
                    Semantics(
                      container: true,
                      sortKey: const OrdinalSortKey(3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Relays',
                                style: AtmosphereTextStyles.h2(c.ink),
                              ),
                              const SizedBox(width: AtmosphereTokens.space8),
                              Text(
                                '· 3 channels',
                                style: AtmosphereTextStyles.caption(c.ink3),
                              ),
                              const Spacer(),
                              Text(
                                'AUTO',
                                style: AtmosphereTextStyles.caption(
                                  autoMode ? c.brand : c.ink3,
                                ),
                              ),
                              const SizedBox(width: AtmosphereTokens.space8),
                              Switch(
                                value: autoMode,
                                onChanged: _autoModeLoading || !isOn
                                    ? null
                                    : (value) => _handleAutoModeToggle(value),
                              ),
                            ],
                          ),
                          const SizedBox(height: AtmosphereTokens.space12),
                          Wrap(
                            spacing: AtmosphereTokens.space12,
                            runSpacing: AtmosphereTokens.space12,
                            children: relayCards
                                .map(
                                  (card) => SizedBox(
                                    width: relayWidth,
                                    child: card,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AtmosphereTokens.space24),
                    Semantics(
                      container: true,
                      sortKey: const OrdinalSortKey(4),
                      child: AtmosphereCard(
                        padding: const EdgeInsets.all(AtmosphereTokens.space16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Recent activity',
                                    style: AtmosphereTextStyles.h2(c.ink),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => context.push(
                                      '/devices/${widget.deviceId}/commands'),
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AtmosphereTokens.space12,
                                      vertical: AtmosphereTokens.space8,
                                    ),
                                  ),
                                  child: Text(
                                    'View all →',
                                    style: AtmosphereTextStyles.body(c.brand),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AtmosphereTokens.space8),
                            if (recentCommands.isEmpty)
                              Text(
                                commandsAsync.hasError
                                    ? 'Unable to load command activity.'
                                    : commandsAsync.isLoading
                                        ? 'Loading command activity...'
                                        : 'No command activity yet.',
                                style: AtmosphereTextStyles.body(
                                  commandsAsync.hasError ? c.danger : c.ink2,
                                ),
                              )
                            else
                              ...recentCommands.take(3).map(
                                (command) {
                                  final (icon, label) =
                                      _formatRecentActivity(command);
                                  final (tone, badgeLabel) =
                                      _statusBadge(command.status);
                                  return HistoryRow(
                                    icon: icon,
                                    label: label,
                                    sub: _relativeTime(command.createdAt),
                                    badgeTone: tone,
                                    badgeLabel: badgeLabel,
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  (IconData, String) _formatRecentActivity(Command command) {
    final payload = command.payload;
    final type = payload['type'] as String? ?? 'unknown';
    return switch (type) {
      'device_mode' => (
          AppIcons.bolt,
          'Mode changed to ${(payload['mode'] ?? '?').toString().toUpperCase()}'
        ),
      'relay_set' => (
          AppIcons.wind,
          'Relay ${payload['relay'] ?? '?'} turned ${payload['state'] == true ? 'on' : 'off'}',
        ),
      'calibrate_co' => (AppIcons.cog, 'CO calibration requested'),
      'calibrate_no2' => (AppIcons.cog, 'NO2 calibration requested'),
      _ => (AppIcons.device, type),
    };
  }

  (PillTone, String) _statusBadge(String status) {
    return switch (status) {
      'done' => (PillTone.online, 'Done'),
      'sent' => (PillTone.brand, 'Sent'),
      'error' => (PillTone.danger, 'Error'),
      'timeout' => (PillTone.warn, 'Timeout'),
      _ => (PillTone.accent, 'Pending'),
    };
  }

  Future<void> _refreshLiveData({
    bool refreshDevices = false,
    bool refreshTelemetry = true,
  }) async {
    if (_refreshing) return;
    _refreshing = true;

    try {
      await Future.wait([
        if (refreshDevices) ref.refresh(devicesProvider.future),
        ref.refresh(shadowProvider(widget.deviceId).future),
        if (refreshTelemetry)
          ref
              .read(telemetryLiveProvider(widget.deviceId).notifier)
              .refreshSnapshot(),
        ref.refresh(commandsProvider(widget.deviceId).future),
      ]);
    } finally {
      _refreshing = false;
    }
  }

  void _showQueuedCommandSnackBar() {
    final c = context.colors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Command queued. It will run when the device reconnects.',
        ),
        backgroundColor: c.warn,
      ),
    );
  }

  void _showCommandFailureSnackBar(String message) {
    final c = context.colors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: c.danger,
      ),
    );
  }

  void _cancelPendingAction(_PendingControlAction? action) {
    action?.queueTimer?.cancel();
    action?.shadowRefreshTimer?.cancel();
  }

  void _trackPendingAction(_PendingControlAction action) {
    _cancelPendingAction(action);
    action.queueTimer = Timer(_commandPendingUiTimeout, () {
      if (!mounted) return;
      if (!_matchesCurrentPendingAction(action)) return;
      action.queuedNoticeShown = true;
      _clearPendingAction(action);
      _showQueuedCommandSnackBar();
    });

    setState(() {
      switch (action.kind) {
        case _PendingControlKind.mode:
          _pendingModeAction = action;
          _modeLoading = true;
          break;
        case _PendingControlKind.relay:
          final channel = action.channel!;
          _pendingRelayActions[channel] = action;
          _relayLoading[channel] = true;
          break;
      }
    });
  }

  bool _matchesCurrentPendingAction(_PendingControlAction action) {
    return switch (action.kind) {
      _PendingControlKind.mode => identical(_pendingModeAction, action),
      _PendingControlKind.relay =>
        identical(_pendingRelayActions[action.channel], action),
    };
  }

  void _clearPendingAction(_PendingControlAction action) {
    _cancelPendingAction(action);
    if (!mounted) return;
    setState(() {
      switch (action.kind) {
        case _PendingControlKind.mode:
          if (identical(_pendingModeAction, action)) {
            _pendingModeAction = null;
            _modeLoading = false;
          }
          break;
        case _PendingControlKind.relay:
          final channel = action.channel!;
          if (identical(_pendingRelayActions[channel], action)) {
            _pendingRelayActions.remove(channel);
            _relayLoading[channel] = false;
          }
          break;
      }
    });
  }

  void _scheduleShadowRefresh(_PendingControlAction action) {
    action.shadowRefreshTimer?.cancel();
    action.shadowRefreshTimer = Timer(_shadowRefreshGrace, () async {
      if (!mounted || !_matchesCurrentPendingAction(action)) return;
      await ref.read(shadowProvider(widget.deviceId).notifier).refresh();
      final refreshedShadow =
          ref.read(shadowProvider(widget.deviceId)).valueOrNull;
      if (refreshedShadow == null) return;
      if (!_applyShadowResolution(refreshedShadow, action)) {
        _clearPendingAction(action);
      }
    });
  }

  void _handleCommandsChanged(
    AsyncValue<List<Command>>? previous,
    AsyncValue<List<Command>> next,
  ) {
    final commands = next.valueOrNull;
    if (commands == null) return;

    final pendingActions = <_PendingControlAction>[
      if (_pendingModeAction != null) _pendingModeAction!,
      ..._pendingRelayActions.values,
    ];

    for (final action in pendingActions) {
      final command =
          commands.where((item) => item.id == action.commandId).firstOrNull;
      if (command == null) continue;

      switch (command.status) {
        case 'done':
          action.queueTimer?.cancel();
          action.queueTimer = null;
          final currentShadow =
              ref.read(shadowProvider(widget.deviceId)).valueOrNull;
          if (currentShadow != null &&
              _applyShadowResolution(currentShadow, action)) {
            continue;
          }
          _scheduleShadowRefresh(action);
          break;
        case 'timeout':
          _clearPendingAction(action);
          if (!action.queuedNoticeShown) {
            _showQueuedCommandSnackBar();
          }
          break;
        case 'error':
          _clearPendingAction(action);
          _showCommandFailureSnackBar(
            action.kind == _PendingControlKind.mode
                ? 'Failed to change mode.'
                : 'Failed to toggle relay.',
          );
          break;
        case 'pending':
        case 'sent':
          break;
        default:
          break;
      }
    }
  }

  void _handleShadowChanged(
    AsyncValue<DeviceShadow>? previous,
    AsyncValue<DeviceShadow> next,
  ) {
    final shadow = next.valueOrNull;
    if (shadow == null) return;

    if (_pendingModeAction != null) {
      _applyShadowResolution(shadow, _pendingModeAction!);
    }

    for (final action in _pendingRelayActions.values.toList()) {
      _applyShadowResolution(shadow, action);
    }
  }

  bool _applyShadowResolution(
    DeviceShadow shadow,
    _PendingControlAction action,
  ) {
    final reported = shadow.reported;
    final resolved = switch (action.kind) {
      _PendingControlKind.mode =>
        (reported['mode'] as String?)?.toLowerCase() == action.expectedMode,
      _PendingControlKind.relay =>
        reported['relay_${action.channel}'] == action.expectedRelayState,
    };

    if (!resolved) return false;
    _clearPendingAction(action);
    return true;
  }

  Future<void> _handleModeToggle(bool value) async {
    final newMode = value ? 'on' : 'off';

    if (!value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Switch to Standby?'),
          content: const Text(
            'Sensors will pause and relays will turn off.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      final commandId = await ref
          .read(deviceServiceProvider)
          .setMode(widget.deviceId, newMode);
      _trackPendingAction(
        _PendingControlAction.mode(
          commandId: commandId,
          expectedMode: newMode,
        ),
      );
    } catch (e) {
      if (mounted) {
        _showCommandFailureSnackBar('Failed to change mode: $e');
      }
    }
  }

  Future<void> _handleAutoModeToggle(bool value) async {
    setState(() => _autoModeLoading = true);
    try {
      await ref.read(deviceServiceProvider).setAutoMode(widget.deviceId, value);
      ref.invalidate(devicesProvider);
    } catch (e) {
      if (mounted) {
        _showCommandFailureSnackBar('Failed to change auto mode: $e');
      }
    } finally {
      if (mounted) setState(() => _autoModeLoading = false);
    }
  }

  Future<void> _handleRelayToggle(
      int channel, bool currentState, bool deviceOn, bool autoMode) async {
    if (autoMode) {
      final c = context.colors;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Auto mode is active. Turn off Auto to control manually.',
          ),
          backgroundColor: c.warn,
        ),
      );
      return;
    }

    if (!deviceOn) {
      final c = context.colors;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Turn device on first'),
          backgroundColor: c.warn,
        ),
      );
      return;
    }

    try {
      final nextState = !currentState;
      final commandId = await ref
          .read(deviceServiceProvider)
          .setRelay(widget.deviceId, channel, nextState);
      _trackPendingAction(
        _PendingControlAction.relay(
          commandId: commandId,
          channel: channel,
          expectedRelayState: nextState,
        ),
      );
    } catch (e) {
      if (mounted) {
        _showCommandFailureSnackBar('Failed to toggle relay: $e');
      }
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _presenceText(Device? device) {
    if (device?.online == true) return '● Online';
    final lastSeen = device?.lastSeen;
    if (lastSeen == null) return '● Offline';
    return '● Offline · ${_relativeTime(lastSeen)}';
  }

  String? _blockingErrorMessage({
    required Device? device,
    required AsyncValue<List<Device>> devicesAsync,
    required DeviceShadow? shadow,
    required AsyncValue<DeviceShadow> shadowAsync,
    required TelemetrySeriesState? telemetryState,
    required AsyncValue<TelemetrySeriesState> telemetryLiveAsync,
  }) {
    if (devicesAsync.hasError && device == null) {
      return 'Unable to load device details.';
    }
    if (shadowAsync.hasError && shadow == null) {
      return 'Unable to load device status.';
    }
    if (telemetryLiveAsync.hasError && telemetryState == null) {
      return 'Unable to load live telemetry.';
    }
    if (device == null) {
      return 'Device not found.';
    }
    return null;
  }

  bool _isBlockingLoad({
    required Device? device,
    required AsyncValue<List<Device>> devicesAsync,
    required DeviceShadow? shadow,
    required AsyncValue<DeviceShadow> shadowAsync,
    required TelemetrySeriesState? telemetryState,
    required AsyncValue<TelemetrySeriesState> telemetryLiveAsync,
  }) {
    return (devicesAsync.isLoading && device == null) ||
        (shadowAsync.isLoading && shadow == null) ||
        (telemetryLiveAsync.isLoading && telemetryState == null);
  }

  Widget _buildBlockingStateScaffold({
    required String title,
    required Widget child,
  }) {
    final c = context.colors;
    return BackNavigationScope(
      fallbackRoute: '/home',
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AtmosphereAppBar.back(
          title: title,
          onBack: () => handleBackOrFallback(context, '/home'),
          actions: const [],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AtmosphereTokens.space24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
