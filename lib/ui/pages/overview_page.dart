import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../dialogs.dart';
import '../widgets/common.dart';

class OverviewPage extends StatefulWidget {
  const OverviewPage({
    super.key,
    required this.onOpenTunnels,
  });

  final VoidCallback onOpenTunnels;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  late final TextEditingController _quickPort;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _quickPort = TextEditingController(text: '${state.settings.quickPort}');
  }

  @override
  void dispose() {
    _quickPort.dispose();
    super.dispose();
  }

  Future<void> _createTunnel() async {
    final tunnel = await showCreateTunnelDialog(context);
    if (tunnel != null && mounted) {
      await showEndpointDialog(context, tunnel: tunnel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.colors;
    final runningTunnels = state.tunnels
        .where((t) => state.runtimes[t.id]?.phase.isLive ?? false)
        .toList();
    final banner = _setupBanner(context, state);

    return Scrollbar(
      child: SingleChildScrollView(
        padding: responsivePagePadding(context),
        child: ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                eyebrow: 'Dashboard',
                title: '概览',
                subtitle: '通过 Cloudflare 边缘安全访问内网服务，无需公网 IP 与入站端口。',
                actions: [
                  Tooltip(
                    message: state.loggedIn
                        ? '同步云端隧道（导入已有隧道并取回凭证）'
                        : '请先登录 Cloudflare',
                    child: IconButton(
                      onPressed: state.loggedIn && !state.syncing
                          ? () => state.syncAccount()
                          : null,
                      icon: state.syncing
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.muted,
                              ),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                    ),
                  ),
                  Tooltip(
                    message: state.loggedIn ? '创建命名隧道' : '请先登录 Cloudflare',
                    child: FilledButton.icon(
                      onPressed: state.loggedIn ? _createTunnel : null,
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('新建隧道'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (banner != null) ...[
                banner,
                const SizedBox(height: 16),
              ],
              _HeroCard(
                state: state,
                onOpenTunnels: widget.onOpenTunnels,
                onCreateTunnel:
                    state.loggedIn ? _createTunnel : null,
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 12.0;
                  final columns = constraints.maxWidth >= 880
                      ? 4
                      : (constraints.maxWidth >= 540 ? 2 : 1);
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  final stats = [
                    _StatData(
                      label: '命名隧道',
                      value: '${state.tunnels.length}',
                      suffix: '条',
                      caption: '由本应用管理',
                      icon: Icons.dns_outlined,
                      tint: c.accent,
                    ),
                    _StatData(
                      label: '在线隧道',
                      value: '${state.activeTunnelCount}',
                      suffix: '条',
                      caption: '已建立边缘连接',
                      icon: Icons.bolt_rounded,
                      tint: c.success,
                    ),
                    _StatData(
                      label: '端口映射',
                      value: '${state.endpointCount}',
                      suffix: '个',
                      caption: '域名 → 本地端口',
                      icon: Icons.alt_route_rounded,
                      tint: c.warning,
                    ),
                    _StatData(
                      label: '边缘连接',
                      value: '${state.totalConnectionCount}',
                      suffix: '条',
                      caption: 'Quic / Http2 通道',
                      icon: Icons.hub_outlined,
                      tint: c.muted,
                    ),
                  ];
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final stat in stats)
                        SizedBox(width: width, child: _StatCard(stat: stat)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 26),
              SectionLabel(
                '临时公网测试',
                trailing: TinyTag(
                  label: '无需登录',
                  icon: Icons.bolt_rounded,
                  color: c.faint,
                ),
              ),
              const SizedBox(height: 10),
              _QuickCard(state: state, portController: _quickPort),
              const SizedBox(height: 26),
              SectionLabel(
                '在线隧道',
                trailing: HoverTextButton(
                  label: '管理全部',
                  icon: Icons.arrow_forward_rounded,
                  onTap: widget.onOpenTunnels,
                ),
              ),
              const SizedBox(height: 10),
              if (runningTunnels.isEmpty)
                EmptyState(
                  compact: true,
                  icon: Icons.lan_outlined,
                  title: '暂无在线命名隧道',
                  message: state.tunnels.isEmpty
                      ? '创建一条命名隧道，把本机端口映射到你的 Cloudflare 域名。'
                      : '在「隧道」页启动映射后，公网入口会显示在这里。',
                  action: state.loggedIn
                      ? FilledButton.icon(
                          onPressed: state.tunnels.isEmpty
                              ? _createTunnel
                              : widget.onOpenTunnels,
                          icon: Icon(
                            state.tunnels.isEmpty
                                ? Icons.add_rounded
                                : Icons.settings_ethernet_rounded,
                            size: 16,
                          ),
                          label: Text(
                            state.tunnels.isEmpty ? '创建第一条隧道' : '前往隧道管理',
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => showLoginDialog(context),
                          icon: const Icon(Icons.login_rounded, size: 16),
                          label: const Text('先连接账户'),
                        ),
                )
              else
                for (final tunnel in runningTunnels) ...[
                  _ActiveTunnelTile(
                    state: state,
                    tunnel: tunnel,
                    onManage: widget.onOpenTunnels,
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget? _setupBanner(BuildContext context, AppState state) {
    if (state.preparingRuntime) {
      return const InfoBanner(
        icon: Icons.settings_suggest_outlined,
        title: '正在准备 cloudflared 运行时',
        message: '首次启动会将内置的 cloudflared 释放到本地数据目录，请稍候。',
        progress: 0,
      );
    }
    if (state.downloading) {
      return InfoBanner(
        icon: Icons.downloading_rounded,
        title: '正在下载 cloudflared 运行时',
        message: '从 Cloudflare 官方 GitHub 发布页下载最新版本，完成后自动启用。',
        progress: state.downloadProgress,
        action: Text(
          '${(state.downloadProgress * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: context.colors.accent,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (!state.isBinaryReady) {
      return InfoBanner(
        icon: Icons.error_outline_rounded,
        title: 'cloudflared 运行时不可用',
        message: state.binaryError ?? '未找到可用的 cloudflared 可执行文件。',
        tone: InfoTone.danger,
        action: FilledButton.icon(
          onPressed: state.downloadRuntime,
          icon: const Icon(Icons.download_rounded, size: 16),
          label: const Text('下载运行时'),
        ),
      );
    }
    if (!state.loggedIn) {
      return InfoBanner(
        icon: Icons.shield_outlined,
        title: '连接 Cloudflare 账户',
        message: '登录后即可创建命名隧道、绑定自定义域名并自动写入 DNS CNAME 记录。',
        action: FilledButton.icon(
          onPressed: () => showLoginDialog(context),
          icon: const Icon(Icons.login_rounded, size: 16),
          label: const Text('立即登录'),
        ),
      );
    }
    return null;
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.state,
    required this.onOpenTunnels,
    this.onCreateTunnel,
  });

  final AppState state;
  final VoidCallback onOpenTunnels;
  final VoidCallback? onCreateTunnel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = state.activeTunnelCount;
    final quickActive = state.quick.phase.isLive;
    final quickReady = state.quick.phase.isConnected;
    final hasRunning = state.anyTunnelRunning;
    final startable = state.tunnels.any(
      (t) =>
          t.endpoints.isNotEmpty &&
          !(state.runtimes[t.id]?.phase.isLive ?? false),
    );

    final phaseLabel = active > 0
        ? '网络运行中'
        : (quickReady
            ? '临时隧道在线'
            : (quickActive
                ? '连接中'
                : (state.loggedIn ? '待启动' : '待授权')));
    final statusColor = active > 0 || quickReady
        ? c.success
        : (quickActive || !state.loggedIn ? c.warning : c.faint);
    final pulse = active > 0 || quickActive;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: context.isDark
              ? [const Color(0xFF111821), const Color(0xFF0C1118)]
              : [c.surface, c.surfaceAlt],
        ),
        boxShadow: context.isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ]
            : [
                BoxShadow(
                  color: const Color(0xFF0B1220).withValues(alpha: 0.05),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned(
              right: -70,
              top: -120,
              child: Container(
                width: 330,
                height: 330,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      c.accent.withValues(alpha: context.isDark ? 0.16 : 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                StatusPill(
                                  label: phaseLabel,
                                  color: statusColor,
                                  pulse: pulse,
                                ),
                                const SizedBox(width: 8),
                                TinyTag(
                                  label: 'CLOUDFLARE EDGE',
                                  color: c.accent,
                                ),
                              ],
                            ),
                            const SizedBox(height: 15),
                            Text(
                              active > 0
                                  ? '本地服务已安全接入公网'
                                  : (quickReady
                                      ? '临时隧道已接入公网'
                                      : (quickActive
                                          ? '正在建立临时隧道'
                                          : '内网服务，安全直达公网')),
                              style: context.texts.displaySmall?.copyWith(
                                fontSize: wide ? 30 : 25,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              active > 0
                                  ? '当前有 $active 条命名隧道在线，流量经由 Cloudflare 加密边缘转发到本机。'
                                  : (quickReady
                                      ? '公网请求经 Cloudflare 边缘转发到本机 :${state.settings.quickPort}，临时地址关闭后立即失效。'
                                      : (quickActive
                                          ? '正在与 Cloudflare 边缘协商连接，公网地址稍后可用。'
                                          : '建立出站加密通道，把本地端口映射到托管域名，无需开放任何入站端口。')),
                              style: TextStyle(
                                color: c.muted,
                                fontSize: 12.5,
                                height: 1.65,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (startable)
                                  FilledButton.icon(
                                    onPressed: state.startAllTunnels,
                                    icon: const Icon(Icons.play_arrow_rounded, size: 17),
                                    label: const Text('启动全部'),
                                  ),
                                if (hasRunning)
                                  OutlinedButton.icon(
                                    onPressed: state.stopAllTunnels,
                                    icon: const Icon(Icons.stop_rounded, size: 16),
                                    label: const Text('全部停止'),
                                  ),
                                TextButton(
                                  onPressed: onCreateTunnel ?? onOpenTunnels,
                                  child: Text(
                                    state.tunnels.isEmpty ? '创建隧道' : '查看隧道',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (wide) ...[
                        const SizedBox(width: 24),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PulsingRing(
                              color: active > 0 ? c.success : c.accent,
                              size: 148,
                              child: Icon(
                                Icons.cloud_rounded,
                                size: 34,
                                color: active > 0 ? c.success : c.accent,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'EDGE NETWORK',
                              style: TextStyle(
                                color: c.faint,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.7,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatData {
  _StatData({
    required this.label,
    required this.value,
    required this.suffix,
    required this.caption,
    required this.icon,
    required this.tint,
  });

  final String label;
  final String value;
  final String suffix;
  final String caption;
  final IconData icon;
  final Color tint;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});

  final _StatData stat;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(stat.icon, size: 14, color: stat.tint),
              const SizedBox(width: 6),
              Text(
                stat.label,
                style: TextStyle(
                  color: c.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                stat.value,
                style: TextStyle(
                  color: c.text,
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                stat.suffix,
                style: TextStyle(
                  color: c.faint,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            stat.caption,
            style: TextStyle(color: c.faint, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.state, required this.portController});

  final AppState state;
  final TextEditingController portController;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final quick = state.quick;
    final active = quick.phase.isLive;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconSquare(
                icon: Icons.science_outlined,
                color: c.warning,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '临时隧道',
                          style: TextStyle(
                            color: c.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TinyTag(
                          label: 'trycloudflare.com',
                          color: c.faint,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '不依赖域名与账户，生成随机公网地址用于快速测试本地服务。',
                      style: TextStyle(color: c.muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              if (active)
                StatusPill(
                  label: quick.phase.label,
                  color: phaseColor(quick.phase, c),
                  pulse: quick.phase.isConnected,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (active && quick.url != null)
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: c.surfaceSunken,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.success.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.link_rounded, size: 15, color: c.success),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CopyText(
                            quick.url!,
                            size: 12.5,
                            mono: true,
                            color: c.text,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '本机 :${state.settings.quickPort}',
                          style: TextStyle(color: c.faint, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '在浏览器中打开',
                  onPressed: () => state.openUrl(quick.url!),
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: state.stopQuickTunnel,
                  icon: const Icon(Icons.stop_rounded, size: 15),
                  label: const Text('停止'),
                ),
              ],
            )
          else
            Row(
              children: [
                SizedBox(
                  width: 170,
                  child: TextField(
                    controller: portController,
                    enabled: !active && state.isBinaryReady,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '本机端口',
                      hintText: '8080',
                      prefixIcon: Icon(Icons.settings_ethernet_rounded, size: 16),
                    ),
                    onSubmitted: (value) {
                      final port = int.tryParse(value.trim());
                      if (port != null) state.startQuickTunnel(port);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: !state.isBinaryReady || active
                      ? null
                      : () {
                          final port = int.tryParse(portController.text.trim());
                          if (port != null) state.startQuickTunnel(port);
                        },
                  icon: const Icon(Icons.bolt_rounded, size: 16),
                  label: const Text('生成临时地址'),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    quick.error ??
                        '地址通常在 5–15 秒内就绪，关闭隧道后立即失效。',
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: quick.error != null ? c.danger : c.faint,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ActiveTunnelTile extends StatelessWidget {
  const _ActiveTunnelTile({
    required this.state,
    required this.tunnel,
    required this.onManage,
  });

  final AppState state;
  final Tunnel tunnel;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final runtime = state.runtimes[tunnel.id];
    final phase = runtime?.phase ?? TunnelPhase.stopped;
    final endpoints = tunnel.endpoints;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      highlighted: phase.isConnected,
      child: Row(
        children: [
          StatusDot(
            color: phaseColor(phase, c),
            size: 8,
            pulse: phase.isConnected,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      tunnel.name,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(label: phase.label, color: phaseColor(phase, c), dense: true),
                    if (runtime != null && runtime.connectionCount > 0) ...[
                      const SizedBox(width: 6),
                      TinyTag(
                        label: '${runtime.connectionCount} 条边缘连接',
                        color: c.faint,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    for (final endpoint in endpoints.take(3))
                      CopyText(
                        endpoint.publicUrl,
                        size: 11.5,
                        mono: true,
                        color: c.success,
                      ),
                    if (endpoints.length > 3)
                      Text(
                        '+${endpoints.length - 3} 个域名',
                        style: TextStyle(color: c.faint, fontSize: 11),
                      ),
                    if (endpoints.isEmpty)
                      Text(
                        '尚未配置端口映射',
                        style: TextStyle(color: c.faint, fontSize: 11.5),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onManage,
            child: const Text('管理'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '停止隧道',
            onPressed: () => state.stopTunnel(tunnel.id),
            icon: const Icon(Icons.stop_circle_outlined, size: 19),
          ),
        ],
      ),
    );
  }
}
