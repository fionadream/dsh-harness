import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dsh_remote/dsh_remote.dart';
import 'markdown.dart';
import 'settings.dart';

void main() => runApp(const DshMiniApp());

const kBrand = Color(0xFF4D6BFE);

/// 全局字号缩放（设置里可调）。
final ValueNotifier<double> kFontScale = ValueNotifier<double>(1.0);

class DshMiniApp extends StatelessWidget {
  const DshMiniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: kFontScale,
      builder: (context, scale, _) => MaterialApp(
        title: 'DSH Harness',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorSchemeSeed: kBrand,
          scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        ),
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircleAvatar(
                radius: 34,
                backgroundColor: Colors.black,
                child: Icon(Icons.terminal_rounded, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 22),
              const Text('DSH Harness', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('登录后即可连接你在电脑上的 DSH', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _busy ? null : _signIn,
                  style: FilledButton.styleFrom(backgroundColor: Colors.black),
                  child: _busy
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('使用 GitHub 登录', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 18),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12), textAlign: TextAlign.center),
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
      appBar: AppBar(
        title: const Text('选择电脑'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => setState(() => _future = account.listHosts()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<RemoteHost>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text('加载失败：${snapshot.error}'));
          final hosts = snapshot.data ?? const <RemoteHost>[];
          if (hosts.isEmpty) return const Center(child: Text('没有在线的电脑'));
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: hosts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final host = hosts[index];
              final busy = _connecting == host.id;
              return Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: Icon(Icons.computer_rounded, color: host.online ? kBrand : Colors.grey),
                  title: Text(host.name),
                  subtitle: Text(host.online ? '在线' : '离线'),
                  trailing: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right),
                  onTap: host.online && !busy ? () => _connect(host) : null,
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  List<SessionSummary> _sessions = const [];
  List<Workspace> _workspaces = const [];
  final Set<String> _expanded = {};
  SessionSummary? _current;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
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
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(context);
                _rename(session);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('归档'),
              onTap: () {
                Navigator.pop(context);
                _archive(session);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _open(SessionSummary session) {
    setState(() => _current = session);
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

  Widget _sessionTile(SessionSummary s) {
    final title = s.projections.title ?? '未命名';
    final selected = _current?.sessionId == s.sessionId;
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: const Color(0xFFEEF2FF),
      contentPadding: const EdgeInsets.only(left: 34, right: 12),
      leading: Icon(
        s.running ? Icons.circle : Icons.chat_bubble_outline_rounded,
        size: s.running ? 10 : 16,
        color: s.running ? const Color(0xFF32C48D) : Colors.black38,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
      onTap: () => _open(s),
      onLongPress: () => _actions(s),
    );
  }

  Widget _workspaceRow(Workspace ws) {
    final open = _expanded.contains(ws.workspaceId);
    final items = _groupSessions(ws);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (open) {
              _expanded.remove(ws.workspaceId);
            } else {
              _expanded.add(ws.workspaceId);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              children: [
                Icon(open ? Icons.folder_open_rounded : Icons.folder_outlined, size: 17, color: Colors.black54),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(ws.title.isEmpty ? '未命名工作区' : ws.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                ),
                Text('${items.length}', style: const TextStyle(fontSize: 11, color: Colors.black38)),
                const SizedBox(width: 4),
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 16, color: Colors.black38),
              ],
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
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 2),
              child: Row(
                children: [
                  Icon(Icons.terminal_rounded, size: 22, color: Colors.black),
                  SizedBox(width: 8),
                  Text('DSH Harness', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 10, 18, 6),
              child: Text('工作区', style: TextStyle(fontSize: 12, color: Colors.black45)),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Padding(padding: const EdgeInsets.all(18), child: Text('加载失败：$_error'))
                      : ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            ..._workspaces.map(_workspaceRow),
                            if (ungrouped.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.fromLTRB(18, 12, 18, 4),
                                child: Text('未分组', style: TextStyle(fontSize: 12, color: Colors.black45)),
                              ),
                              ...ungrouped.map(_sessionTile),
                            ],
                          ],
                        ),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.settings_outlined, size: 18),
              title: const Text('设置', style: TextStyle(fontSize: 14)),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              ),
            ),
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
        drawer: _drawer(),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          title: Text(_current?.projections.title ?? '新对话',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          centerTitle: true,
        ),
        body: _current == null
            ? const _EmptyChat()
            : ChatView(
                key: ValueKey(_current!.sessionId),
                client: widget.client,
                session: _current!,
                onTurnEnd: _refreshTitle,
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
          Icon(Icons.bubble_chart_rounded, size: 46, color: Color(0xFFC7CEE0)),
          SizedBox(height: 12),
          Text('左滑打开会话列表', style: TextStyle(color: Colors.black45)),
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
  });

  final DshClient client;
  final SessionSummary session;
  final Future<void> Function()? onTurnEnd;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final List<_Turn> _turns = [];
  final List<String> _orphanUsers = [];
  final List<String> _orphanAnswers = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<DshEvent>? _sub;
  int _lastSeq = 0;
  bool _loading = true;
  bool _sending = false;
  String? _pending;
  String? _error;
  String _modelLabel = '模型';

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
          if (!event.committed) setState(() => _turns.isNotEmpty ? _turns.last.live = '' : null);
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

  void _ingest(SessionLogEvent event) {
    final data = event.data;
    switch (event.type) {
      case 'turn/start':
        final turn = data['turn'];
        _turns.add(_Turn(turn is int ? turn : _turns.length + 1, event.time));
        return;
      case 'user/message':
        final message = data['message'];
        if (message is! Map) return;
        final source = message['source'];
        final kind = source is Map ? source['kind'] : null;
        if (kind != 'user') return;
        final text = visibleTextOf(message['content']);
        if (text.trim().isEmpty) return;
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
      final nearBottom = position.pixels >= position.maxScrollExtent - 120;
      if (force || nearBottom) _scroll.jumpTo(position.maxScrollExtent);
    });
  }

  bool get _running => _turns.isNotEmpty && !_turns.last.done;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _pending = text;
    });
    _input.clear();
    _scrollToEnd(force: true);
    try {
      await widget.client.prompt(widget.session.sessionId, text);
    } catch (error) {
      if (mounted) {
        setState(() => _pending = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _stop() async {
    try {
      await widget.client.cancel(widget.session.sessionId);
    } catch (_) {}
  }

  Future<void> _pickModel() async {
    try {
      final catalog = await widget.client.listModels();
      if (!mounted) return;
      final chosen = await showModalBottomSheet<({String provider, String model, String name})>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final group in catalog.groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(group.name, style: const TextStyle(fontSize: 12, color: Colors.black45)),
                ),
                for (final model in group.models)
                  ListTile(
                    dense: true,
                    title: Text(model.name, style: const TextStyle(fontSize: 14)),
                    trailing: model.id == _modelLabel ? const Icon(Icons.check, size: 18) : null,
                    onTap: () => Navigator.pop(
                      context,
                      (provider: group.id, model: model.id, name: model.name),
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
          margin: const EdgeInsets.only(left: 56, top: 6, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: pending ? const Color(0xFFF0F2F5) : const Color(0xFFE8F0FE),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(text,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: pending ? Colors.black45 : const Color(0xFF1A1A1A),
              )),
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
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF9AA0AA))),
          if (!turn.done) ...[
            const SizedBox(width: 6),
            const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _answerBlock(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, right: 6),
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
            height: 12,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEDEFF3),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [bar(0.5), bar(0.9), bar(0.75)],
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

    return Column(
      children: [
        if (_error != null)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF1F0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFD4380D))),
          ),
        Expanded(
          child: _loading
              ? _skeleton()
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  children: children,
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.tune, size: 14),
                      label: Text(_modelLabel, style: const TextStyle(fontSize: 12)),
                      onPressed: _pickModel,
                    ),
                    const Spacer(),
                    if (_running)
                      ActionChip(
                        avatar: const Icon(Icons.stop_circle_outlined, size: 14),
                        label: const Text('停止', style: TextStyle(fontSize: 12)),
                        onPressed: _stop,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFE6E9EF)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            hintText: '发消息…',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: FilledButton(
                        onPressed: _sending ? null : _send,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: const CircleBorder(),
                          backgroundColor: kBrand,
                        ),
                        child: _sending
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.arrow_upward, size: 20),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}