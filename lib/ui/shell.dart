import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'pages/logs_page.dart';
import 'pages/overview_page.dart';
import 'pages/settings_page.dart';
import 'pages/tunnels_page.dart';
import 'widgets/common.dart';

enum AppPage { overview, tunnels, logs, settings }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppPage _page = AppPage.overview;
  StreamSubscription<UiMessage>? _messageSub;

  @override
  void initState() {
    super.initState();
    _messageSub = context.read<AppState>().messages.listen(_showMessage);
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  void _showMessage(UiMessage message) {
    if (!mounted) return;
    final c = context.colors;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          width: 440,
          duration: Duration(seconds: message.error ? 5 : 3),
          backgroundColor: c.surfaceAlt,
          content: Row(
            children: [
              Icon(
                message.error
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 17,
                color: message.error ? c.danger : c.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message.text,
                  style: TextStyle(color: c.text, fontSize: 12.5, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      );
  }

  void _select(AppPage page) {
    if (_page == page) return;
    setState(() => _page = page);
  }

  Widget _pageWidget() {
    return switch (_page) {
      AppPage.overview => OverviewPage(
        onOpenTunnels: () => _select(AppPage.tunnels),
      ),
      AppPage.tunnels => const TunnelsPage(),
      AppPage.logs => const LogsPage(),
      AppPage.settings => const SettingsPage(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (!state.ready) return const _SplashScreen();
        return Scaffold(
          backgroundColor: context.colors.bg,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 640;
              final content = Stack(
                children: [
                  const Positioned.fill(child: _Backdrop()),
                  Positioned.fill(
                    // 手机上的状态栏：内容不能顶到刘海/时钟下面。
                    child: SafeArea(
                      bottom: false,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) {
                          final offset = Tween<Offset>(
                            begin: const Offset(0.008, 0),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(_page),
                          child: _pageWidget(),
                        ),
                      ),
                    ),
                  ),
                ],
              );

              if (narrow) {
                return Column(
                  children: [
                    Expanded(child: content),
                    _MobileNavBar(page: _page, onSelect: _select),
                  ],
                );
              }

              return Row(
                children: [
                  _Sidebar(
                    page: _page,
                    collapsed: constraints.maxWidth < 1120,
                    onSelect: _select,
                  ),
                  Expanded(child: content),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _MobileNavBar extends StatelessWidget {
  const _MobileNavBar({required this.page, required this.onSelect});

  final AppPage page;
  final ValueChanged<AppPage> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = context.select<AppState, int>(
      (state) => state.activeTunnelCount,
    );
    final items = [
      (
        AppPage.overview,
        '概览',
        Icons.space_dashboard_outlined,
        Icons.space_dashboard_rounded,
      ),
      (AppPage.tunnels, '隧道', Icons.lan_outlined, Icons.lan_rounded),
      (AppPage.logs, '日志', Icons.terminal_outlined, Icons.terminal_rounded),
      (AppPage.settings, '设置', Icons.tune_rounded, Icons.tune_rounded),
    ];
    return Container(
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(top: BorderSide(color: c.border)),
      ),
      // 让底色铺到手势条下面，但按钮不压在手势条上。
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: NavigationBar(
          height: 62,
          selectedIndex: page.index,
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          indicatorColor: c.accentSoft,
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
          ),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (index) => onSelect(items[index].$1),
          destinations: [
            for (final item in items)
              NavigationDestination(
                icon: item.$1 == AppPage.tunnels && active > 0
                    ? Badge.count(
                        count: active,
                        backgroundColor: c.accent,
                        textColor: c.onAccent,
                        child: Icon(item.$3, size: 21),
                      )
                    : Icon(item.$3, size: 21),
                selectedIcon: Icon(item.$4, size: 21, color: c.accent),
                label: item.$2,
              ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.page,
    required this.collapsed,
    required this.onSelect,
  });

  final AppPage page;
  final bool collapsed;
  final ValueChanged<AppPage> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Consumer<AppState>(
      builder: (context, state, _) {
        final ready = state.isBinaryReady;
        final active = state.activeTunnelCount;
        final items = <_NavSpec>[
          _NavSpec(
            page: AppPage.overview,
            label: '概览',
            icon: Icons.space_dashboard_outlined,
            activeIcon: Icons.space_dashboard_rounded,
          ),
          _NavSpec(
            page: AppPage.tunnels,
            label: '隧道',
            icon: Icons.lan_outlined,
            activeIcon: Icons.lan_rounded,
            badge: active > 0 ? '$active' : null,
          ),
          _NavSpec(
            page: AppPage.logs,
            label: '日志',
            icon: Icons.terminal_outlined,
            activeIcon: Icons.terminal_rounded,
          ),
          _NavSpec(
            page: AppPage.settings,
            label: '设置',
            icon: Icons.tune_rounded,
            activeIcon: Icons.tune_rounded,
          ),
        ];

        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: collapsed ? 76 : 232,
          decoration: BoxDecoration(
            color: c.sidebar,
            border: Border(right: BorderSide(color: c.border)),
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  collapsed ? 21 : 20,
                  22,
                  collapsed ? 21 : 18,
                  18,
                ),
                child: collapsed
                    ? const Tooltip(
                        message: 'Cloudflare Tunnel Manager',
                        child: LogoMark(size: 34),
                      )
                    : Row(
                        children: [
                          const LogoMark(size: 35),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cloudflare',
                                  style: TextStyle(
                                    color: c.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  'TUNNEL MANAGER',
                                  style: TextStyle(
                                    color: c.faint,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
              Divider(color: c.border, height: 1),
              if (!collapsed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '工作区',
                      style: TextStyle(
                        color: c.faint.withValues(alpha: 0.8),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(height: 12),
              for (final item in items)
                _NavItem(
                  spec: item,
                  selected: page == item.page,
                  collapsed: collapsed,
                  onTap: () => onSelect(item.page),
                ),
              const Spacer(),
              if (!collapsed)
                _StatusPanel(
                  state: state,
                  onTap: () => onSelect(AppPage.settings),
                )
              else
                _CollapsedStatus(
                  state: state,
                  authColor: state.loggedIn ? c.success : c.faint,
                  runtimeColor: ready ? c.success : c.warning,
                  onTap: () => onSelect(AppPage.settings),
                ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: collapsed
                    ? Text(
                        'v1.0',
                        style: TextStyle(
                          color: c.faint.withValues(alpha: 0.7),
                          fontSize: 9,
                        ),
                      )
                    : Text(
                        'v1.0.0  ·  built with cloudflared',
                        style: TextStyle(
                          color: c.faint.withValues(alpha: 0.7),
                          fontSize: 9,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NavSpec {
  const _NavSpec({
    required this.page,
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badge,
  });

  final AppPage page;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String? badge;
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.spec,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final _NavSpec spec;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final spec = widget.spec;
    final item = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 40,
            padding: EdgeInsets.symmetric(
              horizontal: widget.collapsed ? 0 : 12,
            ),
            decoration: BoxDecoration(
              color: widget.selected
                  ? c.accentSoft
                  : (_hovered ? c.surfaceAlt : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.selected
                    ? c.accent.withValues(alpha: 0.18)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: widget.collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  widget.selected ? spec.activeIcon : spec.icon,
                  size: 18,
                  color: widget.selected
                      ? c.accent
                      : (_hovered ? c.text : c.muted),
                ),
                if (!widget.collapsed) ...[
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      spec.label,
                      style: TextStyle(
                        color: widget.selected ? c.text : c.muted,
                        fontSize: 12.5,
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (spec.badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        spec.badge!,
                        style: TextStyle(
                          color: c.onAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (!widget.collapsed) return item;
    return Tooltip(message: spec.label, child: item);
  }
}

class _StatusPanel extends StatefulWidget {
  const _StatusPanel({required this.state, required this.onTap});

  final AppState state;
  final VoidCallback onTap;

  @override
  State<_StatusPanel> createState() => _StatusPanelState();
}

class _StatusPanelState extends State<_StatusPanel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = widget.state;
    final ready = state.isBinaryReady;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _hovered ? c.borderStrong : c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusDot(
                      color: ready ? c.success : c.warning,
                      size: 6,
                      pulse: state.downloading || state.preparingRuntime,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'cloudflared',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      state.binaryVersion != null
                          ? 'v${state.binaryVersion}'
                          : (state.downloading
                                ? '${(state.downloadProgress * 100).toStringAsFixed(0)}%'
                                : '—'),
                      style: TextStyle(color: c.faint, fontSize: 9),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Icon(
                      state.loggedIn
                          ? Icons.person_rounded
                          : Icons.person_outline_rounded,
                      size: 12,
                      color: state.loggedIn ? c.success : c.faint,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Cloudflare 账户',
                      style: TextStyle(color: c.muted, fontSize: 10),
                    ),
                    const Spacer(),
                    Text(
                      state.loggedIn ? '已登录' : '未登录',
                      style: TextStyle(
                        color: state.loggedIn ? c.success : c.faint,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.bolt_rounded, size: 12, color: c.faint),
                    const SizedBox(width: 6),
                    Text(
                      '在线隧道',
                      style: TextStyle(color: c.muted, fontSize: 10),
                    ),
                    const Spacer(),
                    Text(
                      '${state.activeTunnelCount}',
                      style: TextStyle(
                        color: state.activeTunnelCount > 0 ? c.accent : c.faint,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapsedStatus extends StatelessWidget {
  const _CollapsedStatus({
    required this.state,
    required this.authColor,
    required this.runtimeColor,
    required this.onTap,
  });

  final AppState state;
  final Color authColor;
  final Color runtimeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Tooltip(
          message: state.isBinaryReady
              ? 'cloudflared v${state.binaryVersion ?? ''}'
              : '运行时未就绪',
          child: IconButton(
            onPressed: onTap,
            icon: Icon(Icons.memory_rounded, size: 18, color: runtimeColor),
          ),
        ),
        Tooltip(
          message: state.loggedIn ? 'Cloudflare 账户已登录' : 'Cloudflare 账户未登录',
          child: IconButton(
            onPressed: onTap,
            icon: Icon(Icons.person_rounded, size: 18, color: authColor),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${state.activeTunnelCount}',
          style: TextStyle(
            color: state.activeTunnelCount > 0 ? c.accent : c.faint,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _DotGridPainter(
                color: c.borderStrong.withValues(
                  alpha: context.isDark ? 0.32 : 0.5,
                ),
              ),
            ),
          ),
          Positioned(
            top: -180,
            right: -140,
            child: Container(
              width: 540,
              height: 540,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    c.accent.withValues(alpha: context.isDark ? 0.075 : 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -260,
            left: -160,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    c.success.withValues(alpha: context.isDark ? 0.035 : 0.04),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const step = 30.0;
    for (var x = step / 2; x < size.width; x += step) {
      for (var y = step / 2; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: _Backdrop()),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LogoMark(size: 58),
                const SizedBox(height: 20),
                Text(
                  'Cloudflare Tunnel',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '内网穿透控制台',
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 11.5,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 150,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: c.surfaceSunken,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '正在准备 cloudflared 运行时…',
                  style: TextStyle(color: c.faint, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
