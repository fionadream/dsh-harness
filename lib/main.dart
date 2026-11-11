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
          return const _Splash();
        }
        final user = snapshot.data;
        if (user == null) return const LoginPage();
        return HostsPage(user: user);
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
              const Text(
                '登录后即可连接你在电脑上的 DSH',
                style: TextStyle(color: Colors.black54),
              ),
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
          if (snapshot.hasError) {
            return Center(child: Text('加载失败：${snapshot.error}'));
          }
          final hosts = snapshot.data ?? const <RemoteHost>[];
          if (hosts.isEmpty) {
            return const Center(child: Text('没有在线的电脑\n请确认电脑上的 DSH 已登录'));
          }
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
                  leading: Icon(
                    Icons.computer_rounded,
                    color: host.online ? _brand : Colors.grey,
                  ),
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
  late Future<List<SessionSummary>> _sessions;
  String? _currentId;
  String _currentTitle = '新对话';

  @override
  void initState() {
    super.initState();
    _sessions = widget.client.listSessions();
  }

  void _open(SessionSummary session) {
    setState(() {
      _currentId = session.sessionId;
      _currentTitle = session.title?.isNotEmpty == true ? session.title! : '未命名';
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 10),
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
                child: Text('会话', style: TextStyle(fontSize: 12, color: Colors.black45)),
              ),
              Expanded(
                child: FutureBuilder<List<SessionSummary>>(
                  future: _sessions,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text('加载失败：${snapshot.error}', style: const TextStyle(fontSize: 12)),
                      );
                    }
                    final items = snapshot.data ?? const <SessionSummary>[];
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final s = items[index];
                        final selected = s.sessionId == _currentId;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          selectedTileColor: const Color(0xFFEEF2FF),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          leading: Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: selected ? _brand : Colors.black45,
                          ),
                          title: Text(
                            (s.title?.isNotEmpty == true ? s.title! : '未命名'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () => _open(s),
                        );
                      },
                    );
                  },
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
      body: _currentId == null
          ? const _EmptyChat()
          : Center(
              child: Text(
                '会话已选择\n${_currentId!}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black45),
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
          Text('左滑选择会话', style: TextStyle(color: Colors.black45)),
        ],
      ),
    );
  }
}
