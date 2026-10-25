import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final ScrollController _scroll = ScrollController();
  String _source = '全部';
  bool _autoScroll = true;
  int _lastCount = -1;
  String _lastSource = '';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<LogEntry> _filtered(AppState state, String source) {
    final all = state.allLogs;
    if (source == '全部') return all;
    return all.where((entry) => entry.source == source).toList();
  }

  Future<void> _copy(List<LogEntry> logs) async {
    if (logs.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(text: logs.map((e) => e.plain).join('\n')),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            width: 420,
            backgroundColor: context.colors.surfaceAlt,
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 16, color: context.colors.success),
                const SizedBox(width: 9),
                Text(
                  '已复制 ${logs.length} 行日志',
                  style: TextStyle(color: context.colors.text, fontSize: 12.5),
                ),
              ],
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = context.colors;
    final sources = state.logSources;
    final source = sources.contains(_source) ? _source : '全部';

    return Padding(
      padding: responsivePagePadding(context),
      child: ContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              eyebrow: 'Console',
              title: '运行日志',
              subtitle: 'cloudflared 的实时输出，便于排查连接、DNS 与隧道状态。',
              actions: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: c.success.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.success.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusDot(color: c.success, size: 6, pulse: true),
                      const SizedBox(width: 6),
                      Text(
                        '实时',
                        style: TextStyle(
                          color: c.success,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Container(
                decoration: appCardDecoration(context, radius: 16),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                      child: Row(
                        children: [
                          PopupMenuButton<String>(
                            tooltip: '筛选日志来源',
                            onSelected: (value) => setState(() {
                              _source = value;
                              _lastCount = -1;
                            }),
                            itemBuilder: (context) => [
                              for (final item in sources)
                                PopupMenuItem(
                                  value: item,
                                  child: Row(
                                    children: [
                                      Icon(
                                        item == source
                                            ? Icons.check_rounded
                                            : Icons.circle_outlined,
                                        size: 14,
                                        color: item == source ? c.accent : c.faint,
                                      ),
                                      const SizedBox(width: 9),
                                      Text(item, style: TextStyle(fontSize: 12.5)),
                                    ],
                                  ),
                                ),
                            ],
                            child: Container(
                              height: 34,
                              padding: const EdgeInsets.symmetric(horizontal: 11),
                              decoration: BoxDecoration(
                                color: c.surfaceSunken,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(color: c.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.filter_list_rounded, size: 15, color: c.muted),
                                  const SizedBox(width: 6),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 130),
                                    child: Text(
                                      source,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: c.text,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.keyboard_arrow_down_rounded,
                                      size: 14, color: c.faint),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '聚合 ${sources.length - 1} 个来源',
                            style: TextStyle(color: c.faint, fontSize: 10.5),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Text(
                                '自动滚动',
                                style: TextStyle(color: c.muted, fontSize: 11.5),
                              ),
                              const SizedBox(width: 6),
                              Transform.scale(
                                scale: 0.75,
                                child: Switch(
                                  value: _autoScroll,
                                  onChanged: (value) {
                                    setState(() => _autoScroll = value);
                                    if (value) _jumpToBottom();
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip: '复制当前日志',
                                onPressed: () => _copy(_filtered(state, source)),
                                icon: const Icon(Icons.copy_all_rounded, size: 17),
                              ),
                              IconButton(
                                tooltip: '清空日志',
                                onPressed: state.clearLogs,
                                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Divider(color: c.border, height: 1),
                    Expanded(
                      child: ValueListenableBuilder<int>(
                        valueListenable: state.logRevision,
                        builder: (context, revision, _) {
                          final logs = _filtered(state, source);
                          if (_autoScroll &&
                              (logs.length != _lastCount || source != _lastSource)) {
                            _lastCount = logs.length;
                            _lastSource = source;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _jumpToBottom();
                            });
                          }
                          if (logs.isEmpty) {
                            return _EmptyConsole(source: source);
                          }
                          return Container(
                            color: c.surfaceSunken.withValues(
                              alpha: context.isDark ? 0.45 : 0.55,
                            ),
                            child: SelectionArea(
                              child: Scrollbar(
                                controller: _scroll,
                                child: ListView.builder(
                                  controller: _scroll,
                                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                                  itemCount: logs.length,
                                  itemBuilder: (context, index) {
                                    return _LogLine(entry: logs[index]);
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _jumpToBottom() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (_scroll.offset >= max - 4) return;
      _scroll.animateTo(
        max,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = switch (entry.level) {
      LogLevel.error => c.danger,
      LogLevel.warn => c.warning,
      LogLevel.debug => c.faint,
      LogLevel.info => c.muted,
    };
    final label = switch (entry.level) {
      LogLevel.error => 'ERR',
      LogLevel.warn => 'WRN',
      LogLevel.debug => 'DBG',
      LogLevel.info => 'INF',
    };
    final tint = entry.level == LogLevel.error
        ? c.danger.withValues(alpha: 0.045)
        : (entry.level == LogLevel.warn
            ? c.warning.withValues(alpha: 0.04)
            : Colors.transparent);

    final mono = TextStyle(
      fontFamily: 'Cascadia Mono',
      fontFamilyFallback: const ['Consolas', 'Courier New'],
      fontSize: 11.5,
      height: 1.6,
      letterSpacing: 0.05,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              entry.timeLabel,
              style: mono.copyWith(color: c.faint.withValues(alpha: 0.75)),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              label,
              style: mono.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              entry.source,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(color: c.faint, fontSize: 10.5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.message,
              style: mono.copyWith(
                color: entry.level == LogLevel.debug ? c.faint : c.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyConsole extends StatelessWidget {
  const _EmptyConsole({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.surfaceSunken.withValues(alpha: 0.45),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal_rounded, size: 30, color: c.faint),
            const SizedBox(height: 12),
            Text(
              source == '全部' ? '暂无日志' : '「$source」暂无日志',
              style: TextStyle(
                color: c.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '启动隧道或临时测试后，cloudflared 的输出会实时显示在这里。',
              style: TextStyle(color: c.faint, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
