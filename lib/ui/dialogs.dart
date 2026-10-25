import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

class AppDialogFrame extends StatelessWidget {
  const AppDialogFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    required this.child,
    this.actions = const [],
    this.width = 480,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 48,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  IconSquare(icon: icon!, color: iconColor, size: 40),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 12.5,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            child,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    actions[i],
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> showLoginDialog(BuildContext context) async {
  final state = context.read<AppState>();
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LoginDialog(state: state),
  );
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({required this.state});

  final AppState state;

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
    if (!widget.state.loggingIn && !widget.state.loggedIn) {
      unawaited(widget.state.startLogin());
    }
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.state.loggedIn && !_closed) {
      _closed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    if (widget.state.loggingIn && !widget.state.loggedIn) {
      unawaited(widget.state.cancelLogin());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final c = context.colors;
    final steps = <(String, String)>[
      ('在浏览器中打开 Cloudflare 授权页面', '若浏览器未自动打开，可点击下方按钮。'),
      ('选择要授权的域名', '使用已托管在 Cloudflare 的域名完成授权。'),
      ('返回应用', '证书会自动保存到本机，仅用于创建与管理隧道。'),
    ];

    return AppDialogFrame(
      title: '连接 Cloudflare 账户',
      subtitle: '授权后会生成 origin certificate，用于创建命名隧道与配置 DNS。',
      icon: Icons.verified_user_outlined,
      width: 540,
      actions: [
        OutlinedButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        if (state.loginUrl != null)
          FilledButton.icon(
            onPressed: () => state.openLoginUrl(),
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: const Text('打开授权页面'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.accent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        steps[i].$1,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        steps[i].$2,
                        style: TextStyle(
                          color: c.faint,
                          fontSize: 11.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (i < steps.length - 1) const SizedBox(height: 14),
          ],
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surfaceSunken,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                if (state.loggedIn)
                  Icon(Icons.check_circle_rounded, size: 18, color: c.success)
                else
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: state.loginUrl == null ? c.muted : c.accent,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.loggedIn
                            ? '授权成功'
                            : (state.loginUrl == null ? '正在创建授权链接…' : '等待浏览器授权…'),
                        style: TextStyle(
                          color: c.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (state.loginUrl != null && !state.loggedIn) ...[
                        const SizedBox(height: 4),
                        CopyText(
                          state.loginUrl!,
                          display: state.loginUrl,
                          size: 11,
                          color: c.muted,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '提示：授权期间请保持此窗口打开。若浏览器已经登录多个账户，请选择拥有目标域名的账户。',
            style: TextStyle(color: c.faint, fontSize: 11, height: 1.55),
          ),
        ],
      ),
    );
  }
}

Future<Tunnel?> showCreateTunnelDialog(BuildContext context) async {
  final state = context.read<AppState>();
  return showDialog<Tunnel>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CreateTunnelDialog(state: state),
  );
}

class _CreateTunnelDialog extends StatefulWidget {
  const _CreateTunnelDialog({required this.state});

  final AppState state;

  @override
  State<_CreateTunnelDialog> createState() => _CreateTunnelDialogState();
}

class _CreateTunnelDialogState extends State<_CreateTunnelDialog> {
  final TextEditingController _name = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim().toLowerCase();
    if (!isValidTunnelName(name)) {
      setState(() => _error = '仅支持小写字母、数字与连字符，长度 1–32，且不能以连字符开头或结尾');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final tunnel = await widget.state.createTunnel(name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (tunnel != null) {
      Navigator.of(context).pop(tunnel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppDialogFrame(
      title: '新建命名隧道',
      subtitle: '隧道凭证将保存在本机，域名映射与 DNS 由本应用统一管理。',
      icon: Icons.add_link_rounded,
      actions: [
        OutlinedButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        BusyButton(
          label: '创建隧道',
          busy: _busy,
          onPressed: _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabeledField(
            label: '隧道名称',
            hint: '例如 home-nas、dev-server。名称用于在本机与 Cloudflare 面板中识别该隧道。',
            child: TextField(
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'home-nas',
                prefixIcon: const Icon(Icons.tag_rounded, size: 16),
                errorText: _error,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.accent.withValues(alpha: 0.18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: c.accent),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '创建完成后会立即引导你添加域名与本地端口映射。首次使用需要在 Cloudflare 中已托管域名。',
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 11.5,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> showEndpointDialog(
  BuildContext context, {
  required Tunnel tunnel,
  TunnelEndpoint? existing,
}) async {
  final state = context.read<AppState>();
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EndpointDialog(
      state: state,
      tunnel: tunnel,
      existing: existing,
    ),
  );
  return result ?? false;
}

class _EndpointDialog extends StatefulWidget {
  const _EndpointDialog({
    required this.state,
    required this.tunnel,
    this.existing,
  });

  final AppState state;
  final Tunnel tunnel;
  final TunnelEndpoint? existing;

  @override
  State<_EndpointDialog> createState() => _EndpointDialogState();
}

class _EndpointDialogState extends State<_EndpointDialog> {
  late final TextEditingController _hostname;
  late final TextEditingController _port;
  late final TextEditingController _path;
  String _scheme = 'http';
  bool _createDns = true;
  bool _overwriteDns = false;
  bool _busy = false;
  String? _hostnameError;
  String? _portError;
  String? _pathError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _hostname = TextEditingController(text: e?.hostname ?? '');
    _port = TextEditingController(text: e?.port.toString() ?? '');
    _path = TextEditingController(text: e?.path ?? '');
    _scheme = e?.scheme ?? 'http';
    _createDns = widget.state.loggedIn;
    _overwriteDns = false;
  }

  @override
  void dispose() {
    _hostname.dispose();
    _port.dispose();
    _path.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final host = _hostname.text.trim().toLowerCase();
    final port = int.tryParse(_port.text.trim());
    var path = _path.text.trim();
    if (path.isNotEmpty && !path.startsWith('/')) path = '/$path';
    final hostOk = isValidHostname(host);
    final portOk = isValidPort(port);
    final pathOk = path.isEmpty || !path.contains(' ');
    setState(() {
      _hostnameError = hostOk ? null : '请输入完整的域名，如 app.example.com';
      _portError = portOk ? null : '端口需在 1–65535 之间';
      _pathError = pathOk ? null : '路径不能包含空格';
    });
    if (!hostOk || !portOk || !pathOk) return;

    setState(() => _busy = true);
    if (_isEdit) {
      final updated = TunnelEndpoint(
        id: widget.existing!.id,
        hostname: host,
        port: port!,
        scheme: _scheme,
        path: path.isEmpty ? null : path,
        dnsRouted: widget.existing!.dnsRouted,
      );
      await widget.state.updateEndpoint(widget.tunnel.id, updated);
    } else {
      final endpoint = TunnelEndpoint(
        id: newId(),
        hostname: host,
        port: port!,
        scheme: _scheme,
        path: path.isEmpty ? null : path,
      );
      await widget.state.addEndpoint(
        widget.tunnel.id,
        endpoint,
        routeDns: _createDns && widget.state.loggedIn,
        overwriteDns: _overwriteDns,
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final running = widget.state.runtimes[widget.tunnel.id]?.phase.isLive ?? false;
    final hostPreview = _hostname.text.trim().isEmpty
        ? 'app.example.com'
        : _hostname.text.trim().toLowerCase();
    final portPreview = _port.text.trim().isEmpty ? '8080' : _port.text.trim();
    var pathPreview = _path.text.trim();
    if (pathPreview.isNotEmpty && !pathPreview.startsWith('/')) {
      pathPreview = '/$pathPreview';
    }
    final service = '$_scheme://localhost:$portPreview$pathPreview';

    return AppDialogFrame(
      title: _isEdit ? '编辑端口映射' : '添加端口映射',
      subtitle: '将 Cloudflare 托管的域名指向本机端口，流量经隧道加密回源。',
      icon: Icons.alt_route_rounded,
      width: 540,
      actions: [
        OutlinedButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        BusyButton(
          label: _isEdit ? '保存修改' : '添加映射',
          busy: _busy,
          onPressed: _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabeledField(
            label: '公网域名',
            hint: '该域名必须已托管在 Cloudflare。请不要输入协议或路径。',
            child: TextField(
              controller: _hostname,
              autofocus: !_isEdit,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'app.example.com',
                prefixIcon: const Icon(Icons.language_rounded, size: 16),
                errorText: _hostnameError,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: LabeledField(
                  label: '本机服务协议',
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: c.surfaceSunken,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      children: [
                        for (final scheme in ['http', 'https'])
                          Expanded(child: _schemeButton(scheme)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: LabeledField(
                  label: '本机端口',
                  child: TextField(
                    controller: _port,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '8080',
                      prefixIcon: const Icon(Icons.settings_ethernet_rounded, size: 16),
                      errorText: _portError,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: '路径前缀（可选）',
            hint: '留空表示匹配整个域名；如需只转发 /api，可填写 /api。',
            child: TextField(
              controller: _path,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '/api',
                prefixIcon: const Icon(Icons.route_rounded, size: 16),
                errorText: _pathError,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: c.surfaceSunken,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '映射预览',
                  style: TextStyle(
                    color: c.faint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    MonoText('https://$hostPreview$pathPreview', size: 11.5, color: c.accent),
                    Icon(Icons.arrow_forward_rounded, size: 13, color: c.faint),
                    MonoText(service, size: 11.5, color: c.text),
                  ],
                ),
              ],
            ),
          ),
          if (!_isEdit) ...[
            const SizedBox(height: 14),
            _DnsOptions(
              enabled: !_busy,
              loggedIn: widget.state.loggedIn,
              createDns: _createDns && widget.state.loggedIn,
              overwrite: _overwriteDns,
              onChanged: (create, overwrite) {
                setState(() {
                  _createDns = create;
                  _overwriteDns = overwrite;
                });
              },
            ),
          ],
          if (running) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.restart_alt_rounded, size: 14, color: c.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '隧道正在运行，保存后需要重启隧道才能生效。',
                    style: TextStyle(color: c.warning, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _schemeButton(String scheme) {
    final selected = _scheme == scheme;
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _busy ? null : () => setState(() => _scheme = scheme),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? c.accent.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            scheme.toUpperCase(),
            style: TextStyle(
              color: selected ? c.accent : c.faint,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _DnsOptions extends StatelessWidget {
  const _DnsOptions({
    required this.enabled,
    required this.loggedIn,
    required this.createDns,
    required this.overwrite,
    required this.onChanged,
  });

  final bool enabled;
  final bool loggedIn;
  final bool createDns;
  final bool overwrite;
  final void Function(bool create, bool overwrite) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!loggedIn) {
      return Text(
        '尚未登录 Cloudflare，保存映射后可稍后在隧道卡片中配置 DNS。',
        style: TextStyle(color: c.faint, fontSize: 11.5),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled ? () => onChanged(!createDns, overwrite) : null,
          child: Row(
            children: [
              Checkbox(
                value: createDns,
                onChanged: enabled ? (v) => onChanged(v ?? false, overwrite) : null,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '同时创建 DNS CNAME 记录',
                  style: TextStyle(color: c.text, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 32),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: enabled && createDns
                ? () => onChanged(createDns, !overwrite)
                : null,
            child: Row(
              children: [
                Checkbox(
                  value: overwrite && createDns,
                  onChanged: enabled && createDns
                      ? (v) => onChanged(createDns, v ?? false)
                      : null,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '覆盖已存在的 DNS 记录',
                    style: TextStyle(
                      color: createDns ? c.muted : c.faint,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          '若域名已有 A / CNAME 记录，需勾选覆盖；操作会替换原有解析。',
          style: TextStyle(color: c.faint, fontSize: 11, height: 1.5),
        ),
      ],
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  bool danger = false,
  String? details,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final c = context.colors;
      return AppDialogFrame(
        title: title,
        icon: danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
        iconColor: danger ? c.danger : c.accent,
        width: 460,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: c.danger,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.65),
            ),
            if (details != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surfaceSunken,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: c.border),
                ),
                child: Text(
                  details,
                  style: TextStyle(
                    color: c.faint,
                    fontSize: 11.5,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
  return result ?? false;
}

Future<void> confirmDeleteTunnel(BuildContext context, Tunnel tunnel) async {
  final state = context.read<AppState>();
  final ok = await showConfirmDialog(
    context,
    title: '删除隧道「${tunnel.name}」？',
    message: '将从 Cloudflare 删除该隧道并清理本机凭证。此操作不可撤销。',
    confirmLabel: '删除隧道',
    danger: true,
    details: '已配置的域名 DNS 记录不会被自动删除，如需停止解析，请前往 Cloudflare 控制台移除对应的 CNAME。',
  );
  if (ok) {
    await state.deleteTunnel(tunnel.id);
  }
}

Future<void> confirmLogout(BuildContext context) async {
  final state = context.read<AppState>();
  final ok = await showConfirmDialog(
    context,
    title: '退出 Cloudflare 账户？',
    message: '本机授权证书将被删除，正在运行的隧道会先被停止。隧道与映射配置会保留。',
    confirmLabel: '退出登录',
    danger: true,
  );
  if (ok) {
    await state.logout();
  }
}
