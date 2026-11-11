import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dsh_remote/dsh_remote.dart';

void main() => runApp(const DshMiniApp());

const _brand = Color(0xFF4D6BFE);

class DshMiniApp extends StatelessWidget {
  const DshMiniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DSH Harness',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: _brand,
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      ),
      home: const GatePage(),
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
                backgroundColor: _brand,
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
                  leading: Icon(Icons.computer_rounded, color: host.online ? _brand : Colors.grey),
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
  Set<String> _archived = const {};
  final Set<String> _expanded = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sessions = await widget.client.listSessions();
      WorkspaceBaseline? baseline;
      try {
        baseline = await widget.client.watchWorkspaces().first as WorkspaceBaseline;
      } catch (_) {
        baseline = null;
      }
      if (!mounted) return;
      setState(() {
        _sessions = sessions
            .where((s) => s.parentSessionId == null)
            .where((s) => !(baseline?.archivedSessionIds.contains(s.sessionId) ?? false))
            .toList();
        _workspaces = baseline?.workspaces ?? const [];
        _archived = (baseline?.archivedSessionIds ?? const <String>[]).toSet();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  SessionSummary? _find(String id) {
    for (final s in _sessions) {
      if (s.sessionId == id) return s;
    }
    return null;
  }

  void _open(SessionSummary session) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatPage(
        client: widget.client,
        session: session,
        title: session.projections.title ?? '未命名',
      ),
    ));
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
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 34, right: 12),
      leading: Icon(
        s.running ? Icons.circle : Icons.chat_bubble_outline_rounded,
        size: s.running ? 10 : 16,
        color: s.running ? const Color(0xFF32C48D) : Colors.black38,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
      onTap: () => _open(s),
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
                Icon(open ? Icons.folder_open_rounded : Icons.folder_outlined,
                    size: 17, color: Colors.black54),
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

  @override
  Widget build(BuildContext context) {
    final ungrouped = _ungrouped;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('新对话', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '刷新',
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 2),
                child: Row(
                  children: [
                    Icon(Icons.terminal_rounded, size: 22, color: _brand),
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
                leading: const Icon(Icons.logout_rounded, size: 18),
                title: const Text('退出登录', style: TextStyle(fontSize: 14)),
                onTap: () async {
                  await account.logout();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(builder: (_) => const GatePage()),
                    (_) => false,
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v > 250) _scaffoldKey.currentState?.openDrawer();
        },
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bubble_chart_rounded, size: 46, color: Color(0xFFC7CEE0)),
              SizedBox(height: 12),
              Text('点左上角或右滑选择会话', style: TextStyle(color: Colors.black45)),
            ],
          ),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ 对话 */

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.client, required this.session, required this.title});
  final DshClient client;
  final SessionSummary session;
  final String title;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<SessionLogEvent> _events = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<DshEvent>? _sub;
  int _lastSeq = 0;
  bool _sending = false;
  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _running = widget.session.running;
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await widget.client.history(
        widget.session.sessionId,
        throughSeq: widget.session.projections.asOfSeq,
        maxMessages: 30,
      );
      if (!mounted) return;
      setState(() {
        _events
          ..clear()
          ..addAll(page.events);
        _lastSeq = page.events.isEmpty ? 0 : page.events.last.seq;
      });
      _scrollToEnd();
      _sub = widget.client.watch(widget.session.sessionId).listen((event) {
        if (event is! SessionLogEvent) return;
        if (event.seq <= _lastSeq) return;
        setState(() {
          _events.add(event);
          _lastSeq = event.seq;
          if (event.type == 'turn/start') _running = true;
          if (event.type == 'turn/end') _running = false;
        });
        _scrollToEnd();
      }, onError: (Object error) {
        if (mounted) setState(() => _error = '$error');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.client.prompt(widget.session.sessionId, text);
      _input.clear();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败：$error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _stop() async {
    try {
      await widget.client.cancel(widget.session.sessionId);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _textOf(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map && part['text'] is String) buffer.write(part['text']);
      }
      return buffer.toString();
    }
    return '';
  }

  Widget _bubble(SessionLogEvent event) {
    final data = event.data;
    final message = data['message'];
    final content = message is Map ? message['content'] : data['content'];
    final text = _textOf(content);
    switch (event.type) {
      case 'user/message':
        if (text.trim().isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(left: 48, top: 4, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(16)),
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
        );
      case 'assistant/message':
        if (text.trim().isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(right: 40, top: 4, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Text(text, style: const TextStyle(fontSize: 15, height: 1.45)),
          ),
        );
      case 'tool/call':
        final name = data['name'] ?? 'tool';
        final args = data['arguments'] ?? '';
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            title: Text('🔧 $name', style: const TextStyle(fontSize: 13, color: Colors.black54)),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$args', style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          if (_running)
            TextButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: const Text('停止', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('错误：$_error', style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              children: _events.map(_bubble).toList(),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Row(
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
                        textInputAction: TextInputAction.newline,
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
                        backgroundColor: _brand,
                      ),
                      child: _sending
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.arrow_upward, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
