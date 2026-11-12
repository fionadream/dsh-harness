import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dsh_remote/dsh_remote.dart';
import 'filebrowser.dart';
import 'files.dart';
import 'markdown.dart';
import 'settings.dart';
import 'theme.dart';

/// 应用版本（设置页显示，便于核对装的是不是最新包）。
const String kAppVersion = '0.2.34';

void main() => runApp(const DshMiniApp());

/// logo 资源缺失时的兜底图标。
Widget _logoFallback(BuildContext context, Object error, StackTrace? stack) =>
    const Icon(Icons.terminal_rounded, size: 24, color: T.brand);

/// 模型名缩写：只保留版本部分。
/// `deepseek-v4.1-flash-1017` → `v4.1-flash`
/// `deepseek-v4-pro` → `v4-pro`
/// `DeepSeek-V4.1-Flash High` → `v4.1-flash high`
String shortModelName(String raw) {
  var name = raw.trim();
  if (name.isEmpty) return '模型';

  // 去掉 provider 前缀（如 official/）
  final slash = name.lastIndexOf('/');
  if (slash >= 0 && slash + 1 < name.length) name = name.substring(slash + 1);

  // 去掉 deepseek 前缀
  name = name.replaceFirst(RegExp(r'^(deepseek|DeepSeek)[\s\-_]*'), '');

  // 去掉尾部构建号（3 位以上数字）
  name = name.replaceFirst(RegExp(r'[\s\-_]*\d{3,}$'), '');

  name = name.trim();
  if (name.isEmpty) return '模型';
  // 只有像版本号（数字开头）才补 v 前缀；中文名保持原样
  if (RegExp(r'^\d').hasMatch(name)) name = 'v$name';
  return name.toLowerCase();
}

/// 全局字号缩放（设置里可调）。
final ValueNotifier<double> kFontScale = ValueNotifier<double>(1.0);

class DshMiniApp extends StatelessWidget {
  const DshMiniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([kFontScale, kWeight]),
      builder: (context, _) => MaterialApp(
        title: 'DSH R',
        debugShowCheckedModeBanner: false,
        theme: T.theme(),
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: kFontScale.value,
          maxScaleFactor: kFontScale.value,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const GatePage(),
      ),
    );
  }
}

/* ------------------------------------------------------------------ 账号 */

class SecureStore implements SecretStore {
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

RemoteAccount? _account;

/// 供其它页面复用的安全存储读写。
Future<String?> secureStoreRead(String key) async {
  try {
    return await SecureStore().read(key);
  } catch (_) {
    return null;
  }
}

Future<void> secureStoreWrite(String key, String value) async {
  try {
    await SecureStore().write(key, value);
  } catch (_) {}
}

RemoteAccount get account => _account ??= RemoteAccount(
      secrets: SecureStore(),
      deviceName: 'DSH Harness',
      platform: 'android',
      clientVersion: '0.1.0',
    );

/* ------------------------------------------------------------------ 路由 */

class GatePage extends StatefulWidget {
  const GatePage({super.key});
  @override
  State<GatePage> createState() => _GatePageState();
}

class _GatePageState extends State<GatePage> {
  late Future<RemoteUser?> _future;

  @override
  void initState() {
    super.initState();
    _future = account.currentUser();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RemoteUser?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        if (user == null) return const LoginPage();
        return HostsPage(user: user);
      },
    );
  }
}

/* ------------------------------------------------------------------ 登录 */

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final login = await account.startLogin(providerId: 'github');
      await launchUrl(login.loginUrl, mode: LaunchMode.externalApplication);
      final user = await login.result;
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => HostsPage(user: user)),
        (_) => false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/icon.png', width: 72, height: 72, errorBuilder: (_, __, ___) =>
                  const Icon(Icons.terminal_rounded, size: 64, color: T.text)),
              const SizedBox(height: 24),
              const Text('DSH R',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: T.text)),
              const SizedBox(height: 10),
              const Text('登录后即可连接你在电脑上的 DSH',
                  style: TextStyle(fontSize: T.secondary, color: T.textSecondary)),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _busy ? null : _signIn,
                  style: FilledButton.styleFrom(
                    backgroundColor: T.text,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('使用 GitHub 登录',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 18),
                Text(_error!, style: const TextStyle(color: T.danger, fontSize: 13), textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ 主机 */

class HostsPage extends StatefulWidget {
  const HostsPage({super.key, required this.user});
  final RemoteUser user;
  @override
  State<HostsPage> createState() => _HostsPageState();
}

class _HostsPageState extends State<HostsPage> {
  late Future<List<RemoteHost>> _future;
  String? _connecting;

  @override
  void initState() {
    super.initState();
    _future = account.listHosts();
  }

  Future<void> _connect(RemoteHost host) async {
    setState(() => _connecting = host.id);
    try {
      final client = await account.connectHost(host);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => HomePage(client: client, host: host)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('连接失败：$error')));
    } finally {
      if (mounted) setState(() => _connecting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: const Text('选择电脑'),
        actions: [
          IconButton(
            onPressed: () => setState(() => _future = account.listHosts()),
            icon: const Icon(Icons.refresh_rounded, size: 22),
          ),
        ],
      ),
      body: FutureBuilder<List<RemoteHost>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('加载失败：${snapshot.error}',
                  style: const TextStyle(color: T.textSecondary, fontSize: 14)),
            );
          }
          final hosts = snapshot.data ?? const <RemoteHost>[];
          if (hosts.isEmpty) {
            return const Center(
              child: Text('没有在线的电脑', style: TextStyle(color: T.textSecondary, fontSize: 15)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: hosts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final host = hosts[index];
              final busy = _connecting == host.id;
              return Container(
                decoration: BoxDecoration(
                  color: T.bg,
                  borderRadius: BorderRadius.circular(T.rCard),
                  border: Border.all(color: T.divider),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(T.rCard),
                  onTap: host.online && !busy ? () => _connect(host) : null,
                  child: SizedBox(
                    height: 64,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.computer_rounded,
                              size: 22, color: host.online ? T.brand : T.textTertiary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(host.name,
                                    style: const TextStyle(fontSize: T.body, color: T.text)),
                                const SizedBox(height: 2),
                                Text(host.online ? '在线' : '离线',
                                    style: const TextStyle(fontSize: T.tiny, color: T.textSecondary)),
                              ],
                            ),
                          ),
                          if (busy)
                            const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            const Icon(Icons.chevron_right, size: 20, color: T.textTertiary),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/* ------------------------------------------------------------------ 主页 */

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.client, required this.host});
  final DshClient client;
  final RemoteHost host;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _collapsedKey = 'drawer.collapsed';
  static const _readAtKey = 'sessions.readAt';
  static const _saveDirKey = 'files.saveDir';

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  List<SessionSummary> _sessions = const [];
  List<Workspace> _workspaces = const [];
  Set<String> _collapsed = {};
  final Map<String, DateTime> _readAt = {};
  String? _saveDir;
  SessionSummary? _current;
  bool _currentHasApproval = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadDrawerState();
    _loadReadState();
    _loadSaveDir();
  }

  Future<void> _loadSaveDir() async {
    try {
      final raw = await SecureStore().read(_saveDirKey);
      if (!mounted || raw == null) return;
      setState(() => _saveDir = raw.isEmpty ? null : raw);
    } catch (_) {}
  }

  Future<void> _loadDrawerState() async {
    try {
      final raw = await SecureStore().read(_collapsedKey);
      if (!mounted || raw == null || raw.isEmpty) return;
      setState(() => _collapsed = raw.split(',').where((e) => e.isNotEmpty).toSet());
    } catch (_) {}
  }

  Future<void> _saveDrawerState() async {
    try {
      await SecureStore().write(_collapsedKey, _collapsed.join(','));
    } catch (_) {}
  }

  Future<void> _loadReadState() async {
    try {
      final raw = await SecureStore().read(_readAtKey);
      if (!mounted || raw == null || raw.isEmpty) return;
      final parsed = <String, DateTime>{};
      for (final part in raw.split(';')) {
        final index = part.indexOf('=');
        if (index <= 0) continue;
        final time = DateTime.tryParse(part.substring(index + 1));
        if (time != null) parsed[part.substring(0, index)] = time;
      }
      setState(() => _readAt.addAll(parsed));
    } catch (_) {}
  }

  String _encodeRead() =>
      _readAt.entries.map((e) => '${e.key}=${e.value.toIso8601String()}').join(';');

  Future<void> _markRead(String sessionId) async {
    _readAt[sessionId] = DateTime.now();
    try {
      await SecureStore().write(_readAtKey, _encodeRead());
    } catch (_) {}
  }

  /// 任务结束后、还没查看过 → 显示绿点。
  bool _unread(SessionSummary session) {
    final read = _readAt[session.sessionId];
    if (read == null) return false;
    return session.updatedAt.isAfter(read);
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await widget.client.listSessions();
      WorkspaceBaseline? baseline;
      try {
        baseline = await widget.client.watchWorkspaces().first as WorkspaceBaseline;
      } catch (_) {
        baseline = null;
      }
      if (!mounted) return;
      final archived = (baseline?.archivedSessionIds ?? const <String>[]).toSet();
      setState(() {
        _sessions = sessions
            .where((s) => s.parentSessionId == null)
            .where((s) => s.blank != true)
            .where((s) => !archived.contains(s.sessionId))
            .toList();
        _workspaces = baseline?.workspaces ?? const [];
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _refreshTitle() async {
    if (_current == null) return;
    try {
      final sessions = await widget.client.listSessions();
      if (!mounted || _current == null) return;
      for (final s in sessions) {
        if (s.sessionId == _current!.sessionId) {
          setState(() => _current = s);
          await _markRead(s.sessionId);
          return;
        }
      }
    } catch (_) {}
  }

  SessionSummary? _find(String id) {
    for (final s in _sessions) {
      if (s.sessionId == id) return s;
    }
    return null;
  }

  Future<void> _rename(SessionSummary session) async {
    final controller = TextEditingController(text: session.projections.title ?? '');
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    try {
      await widget.client.renameSession(session.sessionId, title);
      await _loadSessions();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重命名失败：$error')));
    }
  }

  Future<void> _archive(SessionSummary session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('归档会话？'),
        content: const Text('归档后不在列表中显示，可在电脑端恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('归档')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.client.archiveSession(session.sessionId);
      if (_current?.sessionId == session.sessionId) setState(() => _current = null);
      await _loadSessions();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('归档失败：$error')));
    }
  }

  void _actions(SessionSummary session) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: T.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            TRow(
              icon: Icons.drive_file_rename_outline,
              label: '重命名',
              showChevron: false,
              onTap: () {
                Navigator.pop(context);
                _rename(session);
              },
            ),
            TRow(
              icon: Icons.archive_outlined,
              label: '归档',
              showChevron: false,
              onTap: () {
                Navigator.pop(context);
                _archive(session);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _open(SessionSummary session) {
    setState(() {
      _current = session;
      _currentHasApproval = false;
    });
    _markRead(session.sessionId);
    setState(() {});
    _scaffoldKey.currentState?.closeDrawer();
  }

  List<SessionSummary> _groupSessions(Workspace ws) {
    final out = <SessionSummary>[];
    for (final id in ws.sessionIds) {
      final s = _find(id);
      if (s != null) out.add(s);
    }
    return out;
  }

  List<SessionSummary> get _ungrouped {
    final grouped = <String>{};
    for (final ws in _workspaces) {
      grouped.addAll(ws.sessionIds);
    }
    return _sessions.where((s) => !grouped.contains(s.sessionId)).toList();
  }

  /// 会话前的状态指示：运行中转圈 / 待审批橙点 / 未读绿点 / 已读留空。
  Widget _statusIndicator(SessionSummary s, bool selected) {
    if (s.running) {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.6, color: T.textSecondary),
      );
    }
    if (selected && _currentHasApproval) {
      return Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(color: T.warn, shape: BoxShape.circle),
      );
    }
    if (_unread(s)) {
      return Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(color: T.success, shape: BoxShape.circle),
      );
    }
    return const SizedBox(width: 8, height: 8);
  }

  Widget _sessionTile(SessionSummary s) {
    final title = s.projections.title ?? '未命名';
    final selected = _current?.sessionId == s.sessionId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(s),
        onLongPress: () => _actions(s),
        child: Container(
          height: 48,
          padding: const EdgeInsets.only(left: T.indentSession, right: 12),
          decoration: BoxDecoration(
            color: selected ? T.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(width: 12, child: Center(child: _statusIndicator(s, selected))),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: T.body, color: selected ? T.brand : T.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _workspaceRow(Workspace ws) {
    final open = !_collapsed.contains(ws.workspaceId);
    final items = _groupSessions(ws);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (open) {
                _collapsed.add(ws.workspaceId);
              } else {
                _collapsed.remove(ws.workspaceId);
              }
            });
            _saveDrawerState();
          },
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(open ? Icons.folder_open_rounded : Icons.folder_outlined,
                      size: 20, color: T.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(ws.title.isEmpty ? '未命名工作区' : ws.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: T.body, color: T.text)),
                  ),
                  Text('${items.length}',
                      style: const TextStyle(fontSize: T.tiny, color: T.textTertiary)),
                  const SizedBox(width: 6),
                  Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 20, color: T.textTertiary),
                ],
              ),
            ),
          ),
        ),
        if (open) ...items.map(_sessionTile),
      ],
    );
  }

  Widget _drawer() {
    final ungrouped = _ungrouped;
    return Drawer(
      backgroundColor: T.bg,
      width: MediaQuery.of(context).size.width * 0.84,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  const Image(
                    image: AssetImage('assets/icon.png'),
                    width: 26,
                    height: 26,
                    errorBuilder: _logoFallback,
                  ),
                  const SizedBox(width: 10),
                  const Text('DSH R',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: T.text)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text('工作区', style: TextStyle(fontSize: T.secondary, color: T.textSecondary)),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('加载失败：$_error',
                              style: const TextStyle(fontSize: 14, color: T.textSecondary)),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 12),
                          children: [
                            ..._workspaces.map(_workspaceRow),
                            if (ungrouped.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                                child: Text('未分组',
                                    style: TextStyle(fontSize: T.secondary, color: T.textSecondary)),
                              ),
                              ...ungrouped.map(_sessionTile),
                            ],
                          ],
                        ),
            ),
            const Divider(height: 0.8, color: T.divider),
            TRow(
              icon: Icons.settings_outlined,
              label: '设置',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v > 250) _scaffoldKey.currentState?.openDrawer();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: T.bg,
        drawer: _drawer(),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu_rounded, size: 26),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          title: Text(_current?.projections.title ?? '新对话'),
          actions: [
            IconButton(
              icon: const Icon(Icons.folder_outlined, size: 22),
              onPressed: () {
                final session = _current;
                if (session == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('先打开一个会话，再浏览它的工作区文件')),
                  );
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FileBrowserPage(
                      client: widget.client,
                      sessionId: session.sessionId,
                      saveDir: _saveDir,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: T.bg,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (context) => const SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('新建会话需要在电脑端创建',
                        style: TextStyle(fontSize: T.secondary, color: T.textSecondary)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _current == null
            ? const _EmptyChat()
            : ChatView(
                key: ValueKey(_current!.sessionId),
                client: widget.client,
                session: _current!,
                onTurnEnd: _refreshTitle,
                onApprovalPending: (value) => setState(() => _currentHasApproval = value),
              ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image(
            image: AssetImage('assets/icon.png'),
            width: 56,
            height: 56,
            errorBuilder: _logoFallback,
          ),
          SizedBox(height: 20),
          Text('今天有什么可以帮到你？',
              style: TextStyle(fontSize: T.title, fontWeight: FontWeight.w700, color: T.text)),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------ 对话 */

class _Turn {
  _Turn(this.turn, this.start);
  final int turn;
  final DateTime start;
  DateTime? end;
  String? endKind;
  final List<String> users = [];
  final List<String> answers = [];
  String live = '';

  bool get done => end != null;
  bool get stopped => endKind == 'aborted' || endKind == 'interrupted';
  bool get failed => endKind == 'error' || endKind == 'failed';
}

String _formatDuration(Duration d) {
  final seconds = d.inMilliseconds / 1000;
  if (seconds < 60) {
    final rounded = (seconds * 10).round() / 10;
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
    return '${text}秒';
  }
  final whole = seconds.round();
  return '${whole ~/ 60}分${whole % 60}秒';
}

class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.client,
    required this.session,
    this.onTurnEnd,
    this.onApprovalPending,
  });

  final DshClient client;
  final SessionSummary session;
  final Future<void> Function()? onTurnEnd;
  final void Function(bool)? onApprovalPending;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final List<_Turn> _turns = [];
  final List<String> _orphanUsers = [];
  final List<String> _orphanAnswers = [];
  final List<ApprovalRequest> _approvals = [];
  final List<UserQuestionRequest> _questions = [];
  final Map<String, Set<String>> _picked = {};
  final List<String> _audit = [];
  final List<({String receiptId, String name})> _uploads = [];
  bool _uploading = false;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<DshEvent>? _sub;
  int _lastSeq = 0;
  bool _loading = true;
  bool _sending = false;
  bool _autoAllow = false;
  String? _pending;
  String? _error;
  String _modelLabel = '模型';

  static const Set<String> _nonHumanKinds = {
    'context', 'system', 'tool', 'runtime-context', 'runtimeContext', 'injected',
  };

  /// 运行时上下文的文本前缀（兜底过滤）。
  static const List<String> _contextPrefixes = [
    'Current runtime context',
    'Time sampled while preparing',
    'Current working directory:',
    'Session artifacts directory',
    'Current DSH file policy',
    'Approval prompts are enabled',
    'Current DeepSeek Harness',
    'The available skill catalog changed',
  ];

  @override
  void initState() {
    super.initState();
    final next = widget.session.projections.nextModel;
    if (next != null) _modelLabel = next.model;
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await widget.client.history(
        widget.session.sessionId,
        throughSeq: widget.session.projections.asOfSeq,
        maxMessages: 40,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _turns.clear();
        _orphanUsers.clear();
        _orphanAnswers.clear();
        for (final event in page.events) {
          _ingest(event);
        }
        _lastSeq = page.events.isEmpty ? 0 : page.events.last.seq;
        _replayPendingApprovals(page.events);
      });
      _scrollToEnd(force: true);
      _sub = widget.client.watch(widget.session.sessionId).listen((event) {
        if (event is SessionLogEvent) {
          if (event.seq <= _lastSeq) return;
          setState(() {
            _ingest(event);
            _lastSeq = event.seq;
          });
          _scrollToEnd();
          return;
        }
        if (event is AssistantChunkEvent) {
          final chunk = event.chunk;
          if (chunk is TextDeltaChunk && _turns.isNotEmpty) {
            setState(() => _turns.last.live += chunk.text);
            _scrollToEnd();
          }
          return;
        }
        if (event is AssistantStreamEnded) {
          if (!event.committed) {
            setState(() {
              if (_turns.isNotEmpty) _turns.last.live = '';
            });
          }
          return;
        }
        if (event is ApprovalRequestedEvent) {
          _onApproval(event.request);
          return;
        }
        if (event is UserQuestionRequestedEvent) {
          setState(() {
            if (!_questions.any((q) => q.eventId == event.request.eventId)) {
              _questions.add(event.request);
            }
          });
          widget.onApprovalPending?.call(true);
          _scrollToEnd(force: true);
          return;
        }
        if (event is HostRequestCancelledEvent) {
          setState(() {
            _approvals.removeWhere((a) => a.eventId == event.eventId);
            _questions.removeWhere((q) => q.eventId == event.eventId);
          });
          widget.onApprovalPending?.call(_approvals.isNotEmpty || _questions.isNotEmpty);
          return;
        }
        if (event is ConnectionStateEvent) {
          final ok = event.state == DshConnectionState.connected;
          setState(() => _error = ok ? null : '连接已断开，正在重连…');
          return;
        }
      }, onError: (Object error) {
        if (mounted) setState(() => _error = '$error');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  /// 从历史里恢复「问了但没决定」的审批（订阅前就挂起的那种）。
  void _replayPendingApprovals(List<SessionLogEvent> events) {
    final asked = <String, Map<String, Object?>>{};
    for (final event in events) {
      final id = event.data['id'];
      if (id is! String) continue;
      if (event.type == 'approval/asked') {
        asked[id] = event.data;
      } else if (event.type == 'approval/decided') {
        asked.remove(id);
      }
    }
    for (final entry in asked.entries) {
      _approvals.add(ApprovalRequest(
        eventId: entry.key,
        sessionId: widget.session.sessionId,
        toolName: (entry.value['toolName'] as String?) ?? 'tool',
        callId: entry.value['callId'] as String?,
        reason: entry.value['reason'] as String?,
      ));
    }
    if (asked.isNotEmpty) widget.onApprovalPending?.call(true);
  }

  void _onApproval(ApprovalRequest request) {
    if (_approvals.any((a) => a.eventId == request.eventId)) return;
    // 「全部允许」开启后，本会话所有审批一律自动通过（用户 2026-11-12 选择方案 A）。
    if (_autoAllow) {
      _answer(request, ApprovalDecision.allowOnce, silent: true);
      return;
    }
    setState(() {
      _approvals.add(request);
      _audit.clear();
    });
    widget.onApprovalPending?.call(true);
    _scrollToEnd(force: true);
  }

  void _ingest(SessionLogEvent event) {
    final data = event.data;
    switch (event.type) {
      case 'turn/start':
        final turn = data['turn'];
        _turns.add(_Turn(turn is int ? turn : _turns.length + 1, event.time));
        return;
      case 'user/message':
        final message = data['message'];
        final map = message is Map ? message : data;
        final source = map['source'];
        final kind = source is Map ? source['kind'] as String? : null;
        if (kind != null && _nonHumanKinds.contains(kind)) return;
        final text = visibleTextOf(map['content']);
        if (text.trim().isEmpty) return;
        final head = text.trimLeft();
        if (_contextPrefixes.any(head.startsWith)) return;
        if (_pending != null && _pending!.trim() == text.trim()) _pending = null;
        if (_turns.isEmpty) {
          _orphanUsers.add(text);
        } else {
          _turns.last.users.add(text);
        }
        return;
      case 'assistant/message':
        final message = data['message'];
        if (message is! Map) return;
        final text = visibleTextOf(message['content']);
        if (text.trim().isEmpty) return;
        if (_turns.isEmpty) {
          _orphanAnswers.add(text);
        } else {
          _turns.last.answers.add(text);
          _turns.last.live = '';
        }
        return;
      case 'turn/end':
        if (_turns.isEmpty) return;
        final turn = _turns.last;
        turn.end = event.time;
        turn.live = '';
        final reason = data['reason'];
        turn.endKind = reason is Map ? reason['kind'] as String? : null;
        final refresh = widget.onTurnEnd;
        if (refresh != null) Future<void>.delayed(const Duration(milliseconds: 900), refresh);
        return;
      default:
        return;
    }
  }

  void _scrollToEnd({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final nearBottom = position.pixels >= position.maxScrollExtent - 140;
      if (force || nearBottom) _scroll.jumpTo(position.maxScrollExtent);
    });
  }

  bool get _running => _turns.isNotEmpty && !_turns.last.done;

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _uploads.isEmpty) || _sending) return;
    final receipts = _uploads.map((e) => e.receiptId).toList(growable: false);
    setState(() {
      _sending = true;
      _pending = text.isEmpty ? null : text;
    });
    _input.clear();
    _scrollToEnd(force: true);
    try {
      await widget.client.prompt(
        widget.session.sessionId,
        text.isEmpty ? '（已发送文件）' : text,
        fileReceiptIds: receipts,
      );
      if (receipts.isNotEmpty && mounted) setState(_uploads.clear);
    } catch (error) {
      if (mounted) {
        setState(() => _pending = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attachFile() async {
    if (_uploading) return;
    try {
      final picked = await pickFileForUpload();
      if (picked == null || !mounted) return;
      if (picked.size > kMaxUploadBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件超过 30 MiB，请先压缩或拆分')),
        );
        return;
      }
      setState(() => _uploading = true);
      final upload = await uploadToSession(widget.client, widget.session.sessionId, picked);
      if (!mounted) return;
      setState(() => _uploads.add(upload));
      _scrollToEnd(force: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败：$error')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _stop() async {
    try {
      await widget.client.cancel(widget.session.sessionId);
    } catch (_) {}
  }

  Future<void> _answer(ApprovalRequest request, ApprovalDecision decision, {bool silent = false}) async {
    setState(() {
      _approvals.removeWhere((a) => a.eventId == request.eventId);
      if (silent) {
        _audit.add('已自动允许：${request.toolName}');
      }
    });
    widget.onApprovalPending?.call(_approvals.isNotEmpty || _questions.isNotEmpty);
    try {
      await widget.client.respondApproval(request, decision);
    } catch (error) {
      if (!mounted) return;
      setState(() => _approvals.add(request));
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    }
  }

  Future<void> _submitQuestion(UserQuestionRequest request) async {
    final answers = <QuestionAnswer>[];
    for (final q in request.questions) {
      final selected = _picked[q.id];
      if (selected == null || selected.isEmpty) return;
      answers.add(QuestionAnswer(q.id, selected: selected.toList()));
    }
    setState(() {
      _questions.removeWhere((q) => q.eventId == request.eventId);
      _picked.clear();
    });
    widget.onApprovalPending?.call(_approvals.isNotEmpty || _questions.isNotEmpty);
    try {
      await widget.client.answerQuestion(request, answers);
    } catch (error) {
      if (!mounted) return;
      setState(() => _questions.add(request));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提交失败：$error')));
    }
  }

  Future<void> _toggleAutoAllow() async {
    if (_autoAllow) {
      setState(() => _autoAllow = false);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('开启自动允许？'),
        content: const Text('本次会话内，所有审批都会自动通过，不再逐条询问。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('开启')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _autoAllow = true);
  }

  Future<void> _pickModel() async {
    try {
      final catalog = await widget.client.listModels();
      if (!mounted) return;
      final chosen = await showModalBottomSheet<({String provider, String model, String name})>(
        context: context,
        backgroundColor: T.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final group in catalog.groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Text(group.name,
                      style: const TextStyle(fontSize: T.secondary, color: T.textSecondary)),
                ),
                for (final model in group.models)
                  SizedBox(
                    height: 52,
                    child: InkWell(
                      onTap: () => Navigator.pop(
                        context,
                        (provider: group.id, model: model.id, name: model.name),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(model.name, style: const TextStyle(fontSize: T.body)),
                            ),
                            if (model.id == _modelLabel)
                              const Icon(Icons.check_rounded, size: 20, color: T.brand),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
      if (chosen == null) return;
      await widget.client.setModel(widget.session.sessionId, provider: chosen.provider, model: chosen.model);
      if (mounted) setState(() => _modelLabel = chosen.name);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('切换失败：$error')));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _userBubble(String text, {bool pending = false}) {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onLongPress: () => Clipboard.setData(ClipboardData(text: text)),
        child: Container(
          margin: const EdgeInsets.only(left: 48, top: 8, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
          decoration: BoxDecoration(
            color: pending ? const Color(0xFFF2F2F4) : T.bubble,
            borderRadius: BorderRadius.circular(T.rBubble),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: T.body,
              height: 1.6,
              color: pending ? T.textSecondary : T.text,
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusLine(_Turn turn) {
    final String label;
    if (!turn.done) {
      label = '处理中…';
    } else if (turn.stopped) {
      label = '已停止';
    } else if (turn.failed) {
      label = '处理失败';
    } else {
      label = '已完成，用时 ${_formatDuration(turn.end!.difference(turn.start))}';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: T.secondary, color: T.textSecondary)),
          if (!turn.done) ...[
            const SizedBox(width: 8),
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
          ],
        ],
      ),
    );
  }

  Widget _answerBlock(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onLongPress: () => Clipboard.setData(ClipboardData(text: text)),
        child: SimpleMarkdown(text),
      ),
    );
  }

  List<Widget> _turnWidgets(_Turn turn) {
    final widgets = <Widget>[];
    for (final text in turn.users) {
      widgets.add(_userBubble(text));
    }
    widgets.add(_statusLine(turn));
    for (final answer in turn.answers) {
      widgets.add(_answerBlock(answer));
    }
    if (turn.live.isNotEmpty) {
      widgets.add(_answerBlock(turn.live));
    }
    return widgets;
  }

  Widget _skeleton() {
    Widget bar(double widthFactor) => FractionallySizedBox(
          widthFactor: widthFactor,
          child: Container(
            height: 14,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F4),
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.pad, 32, T.pad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [bar(0.55), bar(0.92), bar(0.78), bar(0.4)],
      ),
    );
  }

  Widget _barAction({
    required IconData icon,
    required String label,
    required Color color,
    bool filled = false,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: filled ? null : Border.all(color: color, width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: filled ? Colors.white : color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: weightOf(kWeight.value),
                  color: filled ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _approvalPanel() {
    final request = _approvals.first;
    final rest = _approvals.length - 1;
    return Container(
      width: double.infinity,
      color: T.warnBg,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 16, color: Color(0xFFB7791F)),
              const SizedBox(width: 6),
              const Text('需要你确认',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF8A5A00))),
              const Spacer(),
              Text(request.toolName, style: const TextStyle(fontSize: 13, color: T.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            request.displayReason['zh'] ?? request.describe('zh'),
            style: const TextStyle(fontSize: 15, height: 1.6, color: T.text),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _barAction(
                icon: Icons.close_rounded,
                label: '拒绝',
                color: T.danger,
                onTap: () => _answer(request, ApprovalDecision.reject),
              ),
              const SizedBox(width: 12),
              _barAction(
                icon: Icons.check_rounded,
                label: '允许',
                color: T.brand,
                filled: true,
                onTap: () => _answer(request, ApprovalDecision.allowOnce),
              ),
              const SizedBox(width: 12),
              _barAction(
                icon: Icons.bolt_rounded,
                label: '全部',
                color: T.warn,
                onTap: () async {
                  await _toggleAutoAllow();
                  if (!mounted || !_autoAllow) return;
                  await _answer(request, ApprovalDecision.allowOnce, silent: true);
                },
              ),
            ],
          ),
          if (rest > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('还有 $rest 条待确认',
                  style: const TextStyle(fontSize: T.tiny, color: T.textSecondary)),
            ),
        ],
      ),
    );
  }

  Widget _questionPanel() {
    final request = _questions.first;
    final question = request.questions.first;
    final picked = _picked[question.id] ?? <String>{};
    return Container(
      width: double.infinity,
      color: const Color(0xFFF0F6FF),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('需要你回答',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: T.brand)),
          const SizedBox(height: 8),
          Text(question.question, style: const TextStyle(fontSize: 15, height: 1.6, color: T.text)),
          if (question.detail != null && question.detail!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(question.detail!,
                style: const TextStyle(fontSize: T.tiny, color: T.textSecondary)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in question.options)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      final set = _picked.putIfAbsent(question.id, () => <String>{});
                      if (question.multiSelect) {
                        if (!set.remove(option.label)) set.add(option.label);
                      } else {
                        set
                          ..clear()
                          ..add(option.label);
                      }
                    });
                    if (!question.multiSelect) _submitQuestion(request);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: picked.contains(option.label) ? T.brand : T.bg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: picked.contains(option.label) ? T.brand : T.divider),
                    ),
                    child: Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 14,
                        color: picked.contains(option.label) ? Colors.white : T.text,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (question.multiSelect) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: picked.isEmpty ? null : () => _submitQuestion(request),
                style: FilledButton.styleFrom(
                  backgroundColor: T.brand,
                  minimumSize: const Size(0, 38),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
                ),
                child: const Text('提交'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: T.bg,
          borderRadius: BorderRadius.circular(T.rInput),
          border: Border.all(color: T.divider),
          boxShadow: const [
            BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 4)),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(18, 6, 10, 10),
        child: Column(
          children: [
            if (_uploads.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _uploads.length; i += 1)
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                        decoration: BoxDecoration(
                          color: T.chipBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.insert_drive_file_outlined, size: 14, color: T.brand),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 170),
                              child: Text(
                                _uploads[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: T.tiny, color: T.brand),
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => setState(() => _uploads.removeAt(i)),
                              child: const Icon(Icons.close_rounded, size: 14, color: T.brand),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              style: const TextStyle(fontSize: T.body, height: 1.5),
              decoration: const InputDecoration(
                hintText: '发消息…',
                hintStyle: TextStyle(fontSize: T.body, color: T.textTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: _uploading ? null : _attachFile,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(color: T.chipBg, shape: BoxShape.circle),
                    child: _uploading
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2, color: T.brand),
                          )
                        : const Icon(Icons.add_rounded, size: 20, color: T.brand),
                  ),
                ),
                const SizedBox(width: 8),
                _chip(icon: Icons.tune_rounded, label: shortModelName(_modelLabel), onTap: _pickModel),
                const Spacer(),
                if (_running)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: FilledButton(
                        onPressed: _stop,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: const CircleBorder(),
                          backgroundColor: const Color(0xFF6B6B70),
                        ),
                        child: const Icon(Icons.stop_rounded, size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                if (_autoAllow)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: _toggleAutoAllow,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF5A623),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.bolt_rounded, size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: FilledButton(
                    onPressed: _sending ? null : _send,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                      backgroundColor: T.brand,
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.arrow_upward_rounded, size: 20, color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(T.rChip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: T.chipBg, borderRadius: BorderRadius.circular(T.rChip)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: T.brand),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: T.tiny, color: T.brand)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final text in _orphanUsers) {
      children.add(_userBubble(text));
    }
    for (final text in _orphanAnswers) {
      children.add(_answerBlock(text));
    }
    for (final turn in _turns) {
      children.addAll(_turnWidgets(turn));
    }
    if (_pending != null) {
      children.add(_userBubble(_pending!, pending: true));
    }
    for (final line in _audit) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(line, style: const TextStyle(fontSize: T.tiny, color: T.textSecondary)),
      ));
    }

    return Column(
      children: [
        if (_error != null)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF1F0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFD4380D))),
          ),
        Expanded(
          child: _loading
              ? _skeleton()
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(T.pad, 8, T.pad, 16),
                  children: children,
                ),
        ),
        if (_questions.isNotEmpty) _questionPanel(),
        if (_approvals.isNotEmpty) _approvalPanel(),
        _composer(),
      ],
    );
  }
}
