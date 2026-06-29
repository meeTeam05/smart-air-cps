import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app_theme.dart';
import '../../models/realtime_event.dart';
import '../../services/realtime_service.dart';
import 'atmosphere_bottom_nav.dart';

/// App shell with persistent bottom navigation.
/// Wraps the 3 tab screens (Home, Notifications, Profile).
/// Used by GoRouter ShellRoute to provide consistent navigation chrome.
class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({
    super.key,
    required this.navigationShell,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(realtimeConnectionStatusProvider);
    final showBanner = status == RealtimeStatus.disconnected ||
        status == RealtimeStatus.degraded;

    return Scaffold(
      body: Column(
        children: [
          if (showBanner) _ConnectionBanner(status: status),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: AtmosphereBottomNav(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  final RealtimeStatus status;

  const _ConnectionBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDegraded = status == RealtimeStatus.degraded;
    final bg = isDegraded ? c.warnTint : c.dangerTint;
    final fg = isDegraded ? c.warn : c.danger;
    final message = isDegraded ? 'Kết nối không ổn định' : 'Mất kết nối realtime';

    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              message,
              style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
