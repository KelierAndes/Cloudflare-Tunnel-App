import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../dialogs.dart';
import '../widgets/common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _path;

  @override
  void initState() {
    super.initState();
    _path = TextEditingController(
      text: context.read<AppState>().settings.binaryPath ?? '',
    );
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.colors;

    return Scrollbar(
      child: SingleChildScrollView(
        padding: responsivePagePadding(context),
        child: ContentWidth(
          maxWidth: 960,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                eyebrow: 'Preferences',
                title: '设置',
                subtitle: '管理运行时、Cloudflare 授权、外观与本地数据。',
                actions: [
                  if (state.canOpenDataFolder)
                    OutlinedButton.icon(
                      onPressed: state.openDataFolder,
                      icon: const Icon(Icons.folder_open_rounded, size: 15),
                      label: const Text('数据目录'),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              _SettingsSection(
                icon: Icons.memory_rounded,
                title: 'cloudflared 运行时',
                subtitle: 'Cloudflare 官方隧道客户端，负责建立出站加密连接。',
                trailing: state.downloading
                    ? StatusPill(
                        label: '下载中',
                        color: c.warning,
                        dense: true,
                        pulse: true,
                      )
                    : StatusPill(
                        label: state.isBinaryReady ? '就绪' : '不可用',
                        color: state.isBinaryReady ? c.success : c.danger,
                        dense: true,
                      ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                      label: '版本',
                      child: MonoText(
                        state.binaryVersion != null
                            ? 'v${state.binaryVersion}'
                            : (state.preparingRuntime ? '准备中…' : '未检测到'),
                        size: 12,
                        color: state.binaryVersion != null ? c.text : c.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: '可执行文件',
                      child: CopyText(
                        state.binaryPath ?? state.binaryError ?? '尚未准备',
                        size: 11,
                        mono: true,
                        color: state.binaryPath != null ? c.muted : c.danger,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: '更新来源',
                      child: Text(
                        'GitHub · cloudflare/cloudflared releases',
                        style: TextStyle(color: c.muted, fontSize: 11.5),
                      ),
                    ),
                    if (state.downloading) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: state.downloadProgress == 0
                                    ? null
                                    : state.downloadProgress,
                                minHeight: 5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${(state.downloadProgress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: c.accent,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (state.binaryError != null && !state.downloading) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: c.danger.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: c.danger.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(
                          state.binaryError!,
                          style: TextStyle(
                            color: c.danger,
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: state.downloading
                              ? null
                              : () async {
                                  await state.downloadRuntime();
                                  if (mounted &&
                                      state.settings.binaryPath == null) {
                                    _path.text = '';
                                  }
                                },
                          icon: state.downloading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.download_rounded, size: 16),
                          label: Text(state.downloading ? '下载中…' : '下载 / 更新'),
                        ),
                        OutlinedButton.icon(
                          onPressed: state.refreshRuntimeVersion,
                          icon: const Icon(Icons.biotech_outlined, size: 16),
                          label: const Text('重新检测'),
                        ),
                        if (state.canOpenDataFolder)
                          TextButton(
                            onPressed: state.openDataFolder,
                            child: const Text('查看运行时文件'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      Platform.isWindows
                          ? '下载会替换内置运行时，请先停止所有隧道。内置版本随应用发布，离线也可使用。'
                          : '当前平台不打包运行时，首次使用需从 Cloudflare 官方发布页下载；下载前请先停止所有隧道。',
                      style: TextStyle(color: c.faint, fontSize: 10.5, height: 1.55),
                    ),
                    const SizedBox(height: 16),
                    Divider(color: c.border),
                    const SizedBox(height: 16),
                    LabeledField(
                      label: '自定义运行时路径（可选）',
                      hint: '留空或点击「使用内置」即使用应用自带版本。可填写已安装的 cloudflared.exe 所在路径。',
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _path,
                              style: const TextStyle(
                                fontFamily: 'Cascadia Mono',
                                fontFamilyFallback: ['Consolas'],
                                fontSize: 11.5,
                              ),
                              decoration: const InputDecoration(
                                hintText: r'C:\Program Files\cloudflared\cloudflared.exe',
                                prefixIcon: Icon(Icons.terminal_rounded, size: 15),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () async {
                              final ok = await state.setCustomBinaryPath(_path.text);
                              if (ok && mounted) {
                                _path.text = state.settings.binaryPath ?? '';
                              }
                            },
                            child: const Text('应用'),
                          ),
                          const SizedBox(width: 6),
                          TextButton(
                            onPressed: () async {
                              _path.text = '';
                              await state.setCustomBinaryPath('');
                            },
                            child: const Text('使用内置'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                icon: Icons.verified_user_outlined,
                title: 'Cloudflare 账户',
                subtitle: '授权证书用于创建命名隧道、绑定域名与写入 DNS。',
                trailing: StatusPill(
                  label: state.loggedIn ? '已授权' : '未连接',
                  color: state.loggedIn ? c.success : c.faint,
                  dense: true,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                      label: '授权状态',
                      child: Text(
                        state.loggedIn ? 'origin certificate 有效' : '尚未登录 Cloudflare',
                        style: TextStyle(
                          color: state.loggedIn ? c.text : c.muted,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: '证书路径',
                      child: Text(
                        state.store.certFile.path,
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 11,
                          fontFamily: 'Cascadia Mono',
                          fontFamilyFallback: const ['Consolas'],
                        ),
                      ),
                    ),
                    if (state.lastSyncError != null) ...[
                      const SizedBox(height: 8),
                      _InfoRow(
                        label: '最近同步',
                        child: Text(
                          state.lastSyncError!,
                          style: TextStyle(color: c.danger, fontSize: 11),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (state.loggedIn)
                          OutlinedButton.icon(
                            onPressed: () => confirmLogout(context),
                            icon: const Icon(Icons.logout_rounded, size: 15),
                            label: const Text('退出登录'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: () => showLoginDialog(context),
                            icon: const Icon(Icons.login_rounded, size: 16),
                            label: const Text('连接账户'),
                          ),
                        TextButton.icon(
                          onPressed: () => state.openUrl(
                            'https://one.dash.cloudflare.com/',
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 14),
                          label: const Text('打开 Zero Trust 控制台'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '登录会在系统浏览器中完成，证书只保存在本机数据目录，可随时退出清除。',
                      style: TextStyle(color: c.faint, fontSize: 10.5, height: 1.55),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                icon: Icons.palette_outlined,
                title: '外观与行为',
                subtitle: '应用主题与启动行为偏好。',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '界面主题',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        for (final option in [
                          ('dark', '深色', Icons.dark_mode_outlined),
                          ('light', '浅色', Icons.light_mode_outlined),
                          ('system', '跟随系统', Icons.brightness_auto_outlined),
                        ]) ...[
                          Expanded(
                            child: _ThemeTile(
                              label: option.$2,
                              icon: option.$3,
                              selected: state.settings.themeMode == option.$1,
                              onTap: () => state.setThemeMode(option.$1),
                            ),
                          ),
                          if (option.$1 != 'system') const SizedBox(width: 10),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: c.surfaceSunken,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.power_settings_new_rounded,
                              size: 17, color: c.muted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '启动应用时自动连接隧道',
                                  style: TextStyle(
                                    color: c.text,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '自动启动所有已配置端口映射的命名隧道。',
                                  style: TextStyle(color: c.faint, fontSize: 10.5),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: state.settings.autoStartTunnels,
                            onChanged: state.setAutoStart,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (state.supportsBackground) ...[
                _SettingsSection(
                  icon: Icons.minimize_rounded,
                  title: '后台运行',
                  subtitle: '窗口可以关掉，隧道不用停：应用留在系统托盘里继续跑。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingSwitchRow(
                        icon: Icons.visibility_off_outlined,
                        title: '关闭窗口时最小化到托盘',
                        description:
                            '点标题栏关闭只隐藏窗口，隧道保持在线；双击托盘图标可重新打开。',
                        value: state.settings.minimizeToTray,
                        onChanged: state.setMinimizeToTray,
                      ),
                      const SizedBox(height: 10),
                      _SettingSwitchRow(
                        icon: Icons.schedule_rounded,
                        title: '开机自动启动应用',
                        description:
                            '登录 Windows 后静默启动并留在托盘；再打开「启动应用时自动连接隧道」即可开机常驻。',
                        value: state.settings.autoStartOnBoot,
                        onChanged: state.setBootStart,
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: c.surfaceSunken,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.link_rounded, size: 16, color: c.accent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: CopyText(
                                Platform.resolvedExecutable,
                                size: 11,
                                mono: true,
                                color: c.muted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            HoverTextButton(
                              label: '立即隐藏到托盘',
                              icon: Icons.vertical_align_bottom_rounded,
                              onTap: state.hideToTray,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              _SettingsSection(
                icon: Icons.folder_open_rounded,
                title: '本地数据',
                subtitle: '证书、隧道凭证、运行时与日志都保存在本机。',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: c.surfaceSunken,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.folder_rounded, size: 16, color: c.accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: CopyText(
                              state.store.root.path,
                              size: 11,
                              mono: true,
                              color: c.muted,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (state.canOpenDataFolder)
                            TextButton(
                              onPressed: state.openDataFolder,
                              child: const Text('打开目录'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        HoverTextButton(
                          label: 'cloudflared 发布页',
                          icon: Icons.open_in_new_rounded,
                          onTap: () => state.openUrl(
                            'https://github.com/cloudflare/cloudflared/releases',
                          ),
                        ),
                        HoverTextButton(
                          label: 'Cloudflare Tunnel 文档',
                          icon: Icons.menu_book_rounded,
                          onTap: () => state.openUrl(
                            'https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/',
                          ),
                        ),
                        HoverTextButton(
                          label: 'DNS 记录管理',
                          icon: Icons.dns_outlined,
                          onTap: () => state.openUrl(
                            'https://dash.cloudflare.com/',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const _AboutFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconSquare(icon: icon, size: 38),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _SettingSwitchRow extends StatelessWidget {
  const _SettingSwitchRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(color: c.faint, fontSize: 10.5),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: TextStyle(color: c.faint, fontSize: 11.5, height: 1.6),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _ThemeTile extends StatefulWidget {
  const _ThemeTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ThemeTile> createState() => _ThemeTileState();
}

class _ThemeTileState extends State<_ThemeTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final border = widget.selected
        ? c.accent.withValues(alpha: 0.5)
        : (_hovered ? c.borderStrong : c.border);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: widget.selected ? c.accentSoft : c.surfaceSunken,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: border),
          ),
          child: Column(
            children: [
              Icon(
                widget.icon,
                size: 19,
                color: widget.selected ? c.accent : c.muted,
              ),
              const SizedBox(height: 7),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.selected ? c.text : c.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutFooter extends StatelessWidget {
  const _AboutFooter();

  static String get platformLabel {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isMacOS) return 'macOS';
    return 'desktop';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        const LogoMark(size: 28),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cloudflare Tunnel Manager',
              style: TextStyle(
                color: c.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'v1.0.0 · Flutter for $platformLabel',
              style: TextStyle(color: c.faint, fontSize: 10),
            ),
          ],
        ),
        const Spacer(),
        Text(
          '出站加密 · 无需公网 IP',
          style: TextStyle(color: c.faint, fontSize: 10),
        ),
      ],
    );
  }
}
