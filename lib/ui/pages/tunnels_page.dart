import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../dialogs.dart';
import '../widgets/common.dart';

class TunnelsPage extends StatelessWidget {
  const TunnelsPage({super.key});

  Future<void> _createFlow(BuildContext context) async {
    final tunnel = await showCreateTunnelDialog(context);
    if (tunnel != null && context.mounted) {
      await showEndpointDialog(context, tunnel: tunnel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.colors;

    return Scrollbar(
      child: SingleChildScrollView(
        padding: responsivePagePadding(context),
        child: ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                eyebrow: 'Tunnels',
                title: '隧道',
                subtitle: '管理命名隧道、域名映射与 DNS 指向，所有配置都保存在本机。',
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
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                    ),
                  ),
                  Tooltip(
                    message: state.loggedIn ? '创建命名隧道' : '请先登录 Cloudflare',
                    child: FilledButton.icon(
                      onPressed: state.loggedIn && !state.creating
                          ? () => _createFlow(context)
                          : null,
                      icon: state.creating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded, size: 17),
                      label: const Text('新建隧道'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (!state.isBinaryReady) ...[
                InfoBanner(
                  icon: Icons.error_outline_rounded,
                  title: 'cloudflared 运行时不可用',
                  message: state.binaryError ?? '请先准备 cloudflared 运行时。',
                  tone: InfoTone.danger,
                  action: FilledButton(
                    onPressed: state.downloading ? null : state.downloadRuntime,
                    child: Text(
                      state.downloading
                          ? '下载中 ${(state.downloadProgress * 100).toStringAsFixed(0)}%'
                          : '下载运行时',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ] else if (!state.loggedIn) ...[
                InfoBanner(
                  icon: Icons.shield_outlined,
                  title: '需要 Cloudflare 授权',
                  message: '创建命名隧道与写入 DNS 需要账户授权。登录后即可继续。',
                  action: FilledButton.icon(
                    onPressed: () => showLoginDialog(context),
                    icon: const Icon(Icons.login_rounded, size: 16),
                    label: const Text('立即登录'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (state.tunnels.isEmpty)
                _TunnelsEmptyState(
                  loggedIn: state.loggedIn,
                  onCreate: () => _createFlow(context),
                  onLogin: () => showLoginDialog(context),
                )
              else ...[
                for (final tunnel in state.tunnels) ...[
                  _TunnelCard(
                    state: state,
                    tunnel: tunnel,
                    onCreateFlow: () {
                      _createFlow(context);
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 12, color: c.faint),
                    const SizedBox(width: 6),
                    Text(
                      '隧道凭证与 ingress 配置保存在本机数据目录，不会上传到第三方服务。',
                      style: TextStyle(color: c.faint, fontSize: 10.5),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TunnelCard extends StatelessWidget {
  const _TunnelCard({
    required this.state,
    required this.tunnel,
    required this.onCreateFlow,
  });

  final AppState state;
  final Tunnel tunnel;
  final VoidCallback onCreateFlow;

  Future<void> _addMapping(BuildContext context) async {
    await showEndpointDialog(context, tunnel: tunnel);
  }

  Future<void> _editMapping(
    BuildContext context,
    TunnelEndpoint endpoint,
  ) async {
    await showEndpointDialog(context, tunnel: tunnel, existing: endpoint);
  }

  Future<void> _removeMapping(
    BuildContext context,
    TunnelEndpoint endpoint,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除该端口映射？',
      message: '将从隧道配置中移除 ${endpoint.hostname}${endpoint.path ?? ''}，本地服务不会受到影响。',
      confirmLabel: '删除映射',
      danger: true,
      details: '已创建的 DNS 记录不会被删除。',
    );
    if (ok) {
      await state.removeEndpoint(tunnel.id, endpoint.id);
    }
  }

  Future<void> _rerouteDns(
    BuildContext context,
    TunnelEndpoint endpoint,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: '重新创建 DNS 记录？',
      message: '将为 ${endpoint.hostname} 创建新的 CNAME 并覆盖现有解析记录。',
      confirmLabel: '覆盖并创建',
      danger: true,
    );
    if (ok) {
      await state.routeEndpointDns(tunnel.id, endpoint.id, overwrite: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final narrow = isNarrow(context);
    final runtime = state.runtimes[tunnel.id];
    final phase = runtime?.phase ?? TunnelPhase.stopped;
    final phaseTint = phaseColor(phase, c);
    final pending = state.pendingRestart.contains(tunnel.id);
    final credsMissing = state.missingCredentials.contains(tunnel.id);
    final goneRemote = state.remoteMissing.contains(tunnel.id);
    final unrouted = tunnel.endpoints.where((e) => !e.dnsRouted).length;
    final routingAny = tunnel.endpoints.any(
      (e) => state.routingEndpoints.contains(e.id),
    );
    final hasEndpoint = tunnel.endpoints.isNotEmpty;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      highlighted: phase.isConnected && !pending,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: phaseTint.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: phaseTint.withValues(alpha: 0.20)),
                ),
                child: Icon(Icons.dns_rounded, size: 19, color: phaseTint),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            tunnel.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        StatusPill(
                          label: phase.label,
                          color: phaseTint,
                          dense: true,
                          pulse: phase.isConnected || phase.isStarting,
                        ),
                        if (pending) ...[
                          const SizedBox(width: 6),
                          TinyTag(
                            label: '待重启生效',
                            icon: Icons.restart_alt_rounded,
                            color: c.warning,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 10,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        CopyText(
                          tunnel.id,
                          display: shortId(tunnel.id),
                          size: 10.5,
                          mono: true,
                          color: c.faint,
                        ),
                        TinyTag(
                          label: '${tunnel.endpoints.length} 个映射',
                          color: c.faint,
                        ),
                        if (credsMissing)
                          TinyTag(
                            label: '缺少凭证',
                            icon: Icons.key_rounded,
                            color: c.warning,
                          ),
                        if (goneRemote)
                          TinyTag(
                            label: '云端已删除',
                            icon: Icons.cloud_off_outlined,
                            color: c.danger,
                          ),
                        Text(
                          '创建于 ${_dateLabel(tunnel.createdAt)}',
                          style: TextStyle(color: c.faint, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (unrouted > 0)
                if (narrow)
                  IconButton(
                    tooltip: '为 $unrouted 个映射创建 DNS CNAME',
                    onPressed: state.loggedIn && !routingAny
                        ? () => state.routeAllDns(tunnel.id)
                        : null,
                    icon: routingAny
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Badge.count(
                            count: unrouted,
                            backgroundColor: c.warning,
                            textColor: c.onAccent,
                            child: const Icon(
                              Icons.cloud_upload_outlined,
                              size: 19,
                            ),
                          ),
                  )
                else
                  Tooltip(
                    message: '为 $unrouted 个映射创建 DNS CNAME',
                    child: OutlinedButton.icon(
                      onPressed: state.loggedIn && !routingAny
                          ? () => state.routeAllDns(tunnel.id)
                          : null,
                      icon: routingAny
                          ? const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined, size: 15),
                      label: Text('配置 DNS ($unrouted)'),
                    ),
                  ),
              const SizedBox(width: 8),
              _StartStopButton(
                state: state,
                tunnel: tunnel,
                runtime: runtime,
                compact: narrow,
              ),
              const SizedBox(width: 2),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                icon: const Icon(Icons.more_horiz_rounded, size: 19),
                onSelected: (value) async {
                  switch (value) {
                    case 'copy':
                      await Clipboard.setData(ClipboardData(text: tunnel.id));
                      break;
                    case 'dashboard':
                      await state.openUrl(
                        'https://one.dash.cloudflare.com/?to=/:account/networks/tunnels',
                      );
                      break;
                    case 'delete':
                      if (context.mounted) {
                        await confirmDeleteTunnel(context, tunnel);
                      }
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'copy',
                    child: _MenuRow(icon: Icons.copy_rounded, label: '复制隧道 ID'),
                  ),
                  const PopupMenuItem(
                    value: 'dashboard',
                    child: _MenuRow(
                      icon: Icons.open_in_new_rounded,
                      label: '打开 Cloudflare 控制台',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: _MenuRow(
                      icon: Icons.delete_outline_rounded,
                      label: '删除隧道',
                      color: c.danger,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (runtime?.error != null && !phase.isConnected) ...[
            const SizedBox(height: 10),
            Tooltip(
              message: runtime!.error!,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  color: c.danger.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.danger.withValues(alpha: 0.18)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, size: 13, color: c.danger),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        runtime.error!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.danger, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Divider(color: c.border),
          const SizedBox(height: 4),
          if (tunnel.endpoints.isEmpty)
            _EmptyMappings(
              onAdd: () {
                _addMapping(context);
              },
              loggedIn: state.loggedIn,
            )
          else
            for (var i = 0; i < tunnel.endpoints.length; i++) ...[
              _EndpointRow(
                state: state,
                endpoint: tunnel.endpoints[i],
                onEdit: () => _editMapping(context, tunnel.endpoints[i]),
                onDelete: () => _removeMapping(context, tunnel.endpoints[i]),
                onRoute: () => state.routeEndpointDns(
                  tunnel.id,
                  tunnel.endpoints[i].id,
                ),
                onReroute: () => _rerouteDns(context, tunnel.endpoints[i]),
              ),
              if (i < tunnel.endpoints.length - 1)
                Divider(color: c.border.withValues(alpha: 0.7), height: 1),
            ],
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _addMapping(context),
                icon: const Icon(Icons.add_rounded, size: 15),
                label: const Text('添加端口映射'),
              ),
              if (state.tunnels.length == 1 && tunnel.endpoints.isEmpty)
                TextButton.icon(
                  onPressed: onCreateFlow,
                  icon: const Icon(Icons.add_link_rounded, size: 15),
                  label: const Text('再建一条隧道'),
                ),
              if (credsMissing)
                TextButton.icon(
                  onPressed: state.loggedIn
                      ? () => state.repairCredentials(tunnel.id)
                      : null,
                  icon: const Icon(Icons.key_rounded, size: 15),
                  label: const Text('从云端取回凭证'),
                ),
              const Spacer(),
              if (credsMissing)
                Text(
                  '本机缺少凭证，取回后即可启动，无需重建隧道',
                  style: TextStyle(color: c.warning, fontSize: 10.5),
                )
              else if (pending)
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 12, color: c.warning),
                    const SizedBox(width: 5),
                    Text(
                      '配置已修改，重启隧道后生效',
                      style: TextStyle(color: c.warning, fontSize: 10.5),
                    ),
                  ],
                )
              else if (!hasEndpoint)
                Text(
                  '添加映射后即可启动隧道',
                  style: TextStyle(color: c.faint, fontSize: 10.5),
                )
              else
                Text(
                  '启动后流量经 Cloudflare 边缘转发',
                  style: TextStyle(color: c.faint, fontSize: 10.5),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _dateLabel(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }
}

class _StartStopButton extends StatelessWidget {
  const _StartStopButton({
    required this.state,
    required this.tunnel,
    required this.runtime,
    this.compact = false,
  });

  final AppState state;
  final Tunnel tunnel;
  final TunnelRuntime? runtime;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final phase = runtime?.phase ?? TunnelPhase.stopped;
    if (compact) {
      if (phase.isLive) {
        final busy = phase.isStarting;
        return IconButton(
          tooltip: busy ? '正在连接' : '停止隧道',
          onPressed: busy ? null : () => state.stopTunnel(tunnel.id),
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.stop_circle_outlined, size: 20),
        );
      }
      if (tunnel.endpoints.isEmpty) {
        return Tooltip(
          message: '请先添加至少一个端口映射',
          child: IconButton(
            onPressed: null,
            icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
          ),
        );
      }
      return IconButton(
        tooltip: phase.isError ? '重试启动' : '启动隧道',
        onPressed: () => state.startTunnel(tunnel.id),
        icon: Icon(
          phase.isError
              ? Icons.refresh_rounded
              : Icons.play_circle_fill_rounded,
          size: 22,
          color: phase.isError ? context.colors.warning : context.colors.accent,
        ),
      );
    }
    if (phase.isLive) {
      final busy = phase.isStarting;
      return OutlinedButton.icon(
        onPressed: busy ? null : () => state.stopTunnel(tunnel.id),
        icon: busy
            ? const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.stop_rounded, size: 15),
        label: Text(busy ? '连接中' : '停止'),
      );
    }
    if (tunnel.endpoints.isEmpty) {
      return Tooltip(
        message: '请先添加至少一个端口映射',
        child: FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.play_arrow_rounded, size: 17),
          label: const Text('启动'),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: () => state.startTunnel(tunnel.id),
      icon: const Icon(Icons.play_arrow_rounded, size: 17),
      label: Text(phase.isError ? '重试' : '启动'),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({
    required this.state,
    required this.endpoint,
    required this.onEdit,
    required this.onDelete,
    required this.onRoute,
    required this.onReroute,
  });

  final AppState state;
  final TunnelEndpoint endpoint;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRoute;
  final VoidCallback onReroute;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final routing = state.routingEndpoints.contains(endpoint.id);

    final publicBlock = MouseRegion(
      cursor: endpoint.dnsRouted
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: endpoint.dnsRouted ? () => state.openUrl(endpoint.publicUrl) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.language_rounded,
                  size: 15,
                  color: endpoint.dnsRouted ? c.success : c.muted,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    endpoint.hostname,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: endpoint.dnsRouted ? c.success : c.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if ((endpoint.path ?? '').isNotEmpty) ...[
                  const SizedBox(width: 6),
                  TinyTag(label: endpoint.path!, color: c.accent),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              endpoint.publicUrl,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.faint,
                fontSize: 10,
                fontFamily: 'Cascadia Mono',
                fontFamilyFallback: const ['Consolas'],
              ),
            ),
          ],
        ),
      ),
    );

    final localBlock = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.computer_rounded, size: 12, color: c.muted),
          const SizedBox(width: 6),
          MonoText('localhost:${endpoint.port}', size: 11.2, color: c.text),
          const SizedBox(width: 5),
          Text(endpoint.scheme, style: TextStyle(color: c.faint, fontSize: 9.5)),
        ],
      ),
    );

    final dnsChip = _DnsChip(
      routed: endpoint.dnsRouted,
      routing: routing,
      loggedIn: state.loggedIn,
      onTap: endpoint.dnsRouted ? null : onRoute,
      onReroute: endpoint.dnsRouted ? onReroute : null,
    );

    final actions = [
      IconButton(
        tooltip: '编辑映射',
        onPressed: onEdit,
        icon: const Icon(Icons.tune_rounded, size: 16),
      ),
      IconButton(
        tooltip: '删除映射',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline_rounded, size: 16),
      ),
    ];

    if (isNarrow(context)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            publicBlock,
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.arrow_forward_rounded, size: 13, color: c.faint),
                const SizedBox(width: 8),
                localBlock,
                const Spacer(),
                dnsChip,
                ...actions,
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
      child: Row(
        children: [
          Expanded(flex: 5, child: publicBlock),
          const SizedBox(width: 10),
          Icon(Icons.arrow_forward_rounded, size: 13, color: c.faint),
          const SizedBox(width: 10),
          Expanded(flex: 4, child: Align(alignment: Alignment.centerLeft, child: localBlock)),
          const SizedBox(width: 10),
          dnsChip,
          const SizedBox(width: 4),
          ...actions,
        ],
      ),
    );
  }
}

class _DnsChip extends StatelessWidget {
  const _DnsChip({
    required this.routed,
    required this.routing,
    required this.loggedIn,
    this.onTap,
    this.onReroute,
  });

  final bool routed;
  final bool routing;
  final bool loggedIn;
  final VoidCallback? onTap;
  final VoidCallback? onReroute;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (routing) {
      return StatusPill(
        label: '配置中',
        color: c.warning,
        dense: true,
        pulse: true,
      );
    }
    final chip = MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: routed
              ? 'DNS 已指向隧道'
              : (loggedIn ? '点击创建 DNS CNAME 记录' : '登录后可配置 DNS'),
          child: TinyTag(
            label: routed ? 'DNS 已指向' : '待配置 DNS',
            icon: routed ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            color: routed ? c.success : c.warning,
          ),
        ),
      ),
    );
    if (!routed || onReroute == null) return chip;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip,
        const SizedBox(width: 2),
        IconButton(
          tooltip: '重新创建 DNS',
          onPressed: onReroute,
          icon: const Icon(Icons.sync_rounded, size: 14),
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

class _EmptyMappings extends StatelessWidget {
  const _EmptyMappings({required this.onAdd, required this.loggedIn});

  final VoidCallback onAdd;
  final bool loggedIn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surfaceSunken.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(Icons.alt_route_rounded, size: 17, color: c.faint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '还没有端口映射。添加一个域名，把请求转发到本机服务。',
              style: TextStyle(color: c.muted, fontSize: 11.5),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 14),
            label: const Text('添加映射'),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = color ?? c.text;
    return Row(
      children: [
        Icon(icon, size: 15, color: tint),
        const SizedBox(width: 9),
        Text(label, style: TextStyle(color: tint, fontSize: 12.5)),
      ],
    );
  }
}

class _TunnelsEmptyState extends StatelessWidget {
  const _TunnelsEmptyState({
    required this.loggedIn,
    required this.onCreate,
    required this.onLogin,
  });

  final bool loggedIn;
  final VoidCallback onCreate;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final steps = [
      (Icons.add_link_rounded, '创建命名隧道', '在 Cloudflare 注册唯一隧道'),
      (Icons.alt_route_rounded, '添加端口映射', '绑定域名与 localhost 端口'),
      (Icons.cloud_done_outlined, '自动配置 DNS', '写入 CNAME，一键启动'),
    ];

    return AppCard(
      padding: const EdgeInsets.fromLTRB(28, 38, 28, 34),
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.accent.withValues(alpha: 0.22)),
            ),
            child: Icon(Icons.lan_outlined, size: 30, color: c.accent),
          ),
          const SizedBox(height: 18),
          Text(
            '创建你的第一条命名隧道',
            style: TextStyle(
              color: c.text,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              '命名隧道拥有固定的域名入口和本机凭证，适合长期运行的服务。临时测试也可以使用概览页的 trycloudflare 隧道。',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.65),
            ),
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: c.faint.withValues(alpha: 0.6),
                    ),
                  ),
                SizedBox(
                  width: 150,
                  child: Column(
                    children: [
                      Icon(steps[i].$1, size: 18, color: c.accent),
                      const SizedBox(height: 7),
                      Text(
                        steps[i].$2,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        steps[i].$3,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.faint, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: loggedIn ? onCreate : onLogin,
            icon: Icon(
              loggedIn ? Icons.add_rounded : Icons.login_rounded,
              size: 17,
            ),
            label: Text(loggedIn ? '新建隧道' : '连接账户后开始'),
          ),
        ],
      ),
    );
  }
}
