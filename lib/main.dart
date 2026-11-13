import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:dsh_remote/dsh_remote.dart';
import 'deliverables.dart';
import 'filecard.dart';
import 'files.dart';
import 'images.dart';
import 'keepalive.dart';
import 'markdown.dart';
import 'settings.dart';
import 'theme.dart';

/// 应用版本（设置页显示，便于核对装的是不是最新包）。
const String kAppVersion = '0.4.3';

/// 从后台切回前台时递增，会话页据此触发一次重新同步。
final ValueNotifier<int> kResumeTick = ValueNotifier<int>(0);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _restorePreferences();
  KeepAliveService.init();
  runApp(const DshMiniApp());
}

/// 字号 / 字重的存储键。
const String kFontScaleKey = 'font.scale';
const String kFontWeightKey = 'font.weight';

/// 启动时恢复上次的字体设置。
Future<void> _restorePreferences() async {
  try {
    final scale = await secureStoreRead(kFontScaleKey);
    if (scale != null) {
      final value = double.tryParse(scale);
      if (value != null && value >= 0.8 && value <= 1.7) kFontScale.value = value;
    }
    final weight = await secureStoreRead(kFontWeightKey);
    if (weight != null) {
      final value = double.tryParse(weight);
      if (value != null && value >= 300 && value <= 700) kWeight.value = value;
    }
  } catch (_) {}
}

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

/// 当前连接的电脑名（保活通知里显示）。
final ValueNotifier<String?> kLastDevice = ValueNotifier<String?>(null);

class DshMiniApp extends StatefulWidget {
  const DshMiniApp({super.key});

  @override
  State<DshMiniApp> createState() => _DshMiniAppState();
}

class _DshMiniAppState extends State<DshMiniApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // 切到后台：启动前台服务保活，并开始 1 小时倒计时。
        KeepAliveService.start(device: _lastDevice);
      case AppLifecycleState.resumed:
        // 回到前台：撤销倒计时、停服务，并让会话重新同步。
        KeepAliveService.stop();
        kResumeTick.value += 1;
      default:
        break;
    }
  }

  String? get _lastDevice => kLastDevice.value;

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
          // 单列居中、等距；只有一台电脑时也落在画面中间。
          return LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 48).clamp(0.0, double.infinity),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final host in hosts)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: _HostTile(
                              name: host.name,
                              online: host.online,
                              busy: _connecting == host.id,
                              onTap: () => _connect(host),
                            ),
                          ),
                        ),
                    ],
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

/* -------------------------------------------------------------- 显示器件 */

/// 主机卡片：线稿显示器（外框 + 屏幕分割线 + 外扩支架 + 底座），
/// 屏幕里是「应用图标方块 + 主机名」。照参考图比例 1.568:1 复刻。
/// 在线：彩色、可点；离线：整项灰度压暗、不可点。
class _HostTile extends StatelessWidget {
  const _HostTile({
    required this.name,
    required this.online,
    required this.busy,
    required this.onTap,
  });

  final String name;
  final bool online;
  final bool busy;
  final VoidCallback onTap;

  /// 显示器尺寸（上一版 120×96，这版整体放大到 184×117）。
  static const double screenW = 184;
  static const double screenH = 117;
  static const double standH = 25;

  /// 屏幕里的应用图标方块。
  static const double _iconBox = 45;

  /// 屏幕下边框（bezel）上沿的 y；图标和名字都排在它上面。
  static const double _bezelY = 100;

  @override
  Widget build(BuildContext context) {
    final line = online ? const Color(0xFFC6C6C8) : T.textTertiary;

    Widget content = SizedBox(
      width: screenW,
      height: screenH + standH,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _MonitorPainter(color: line, screenW: screenW, screenH: screenH),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _bezelY - 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _iconTile(busy: busy),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      height: 1.1,
                      letterSpacing: 0.2,
                      fontWeight: FontWeight.w700,
                      color: online ? T.text : T.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (!online) {
      content = Opacity(
        opacity: 0.55,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
          child: content,
        ),
      );
    }

    return Semantics(
      button: online,
      label: '$name，${online ? '在线' : '离线'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: online && !busy ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: content,
        ),
      ),
    );
  }

  /// 应用图标：白色圆角方块 + 略微放大的鲸鱼；连接中盖一层转圈。
  Widget _iconTile({required bool busy}) {
    final radius = BorderRadius.circular(_iconBox * 0.24);
    return SizedBox(
      width: _iconBox,
      height: _iconBox,
      child: Stack(
        children: [
          Container(
            width: _iconBox,
            height: _iconBox,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: radius,
              boxShadow: const [
                BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            // 放大后裁掉四周留白，让鲸鱼占满方块（照参考图的图标占比）
            child: OverflowBox(
              minWidth: _iconBox * 1.32,
              maxWidth: _iconBox * 1.32,
              minHeight: _iconBox * 1.32,
              maxHeight: _iconBox * 1.32,
              child: Image.asset(
                'assets/icon.png',
                width: _iconBox * 1.32,
                height: _iconBox * 1.32,
                fit: BoxFit.cover,
                errorBuilder: _logoFallback,
              ),
            ),
          ),
          if (busy)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xB3FFFFFF),
                  borderRadius: radius,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 线稿显示器：圆角外框 + 屏幕分割线 + 两只外扩支架 + 底座。
/// 全部用描边画（上一版的实心灰块就是"丑"的来源）。
class _MonitorPainter extends CustomPainter {
  const _MonitorPainter({
    required this.color,
    required this.screenW,
    required this.screenH,
  });

  final Color color;
  final double screenW;
  final double screenH;

  @override
  void paint(Canvas canvas, Size size) {
    final w = screenW;
    final h = screenH;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // 外框
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.65, 0.65, w - 1.3, h - 1.3),
        const Radius.circular(5),
      ),
      stroke,
    );

    // 屏幕与下边框之间的那条线
    final bezelY = h * 0.855;
    canvas.drawLine(Offset(0.65, bezelY), Offset(w - 0.65, bezelY), stroke);

    // 支架：两条竖线 → 外扩圆角 → 底座横条
    final centerX = w / 2;
    final legDx = w * 0.088;
    final baseTop = h + w * 0.11;
    final baseHalf = w * 0.201;

    for (final sign in const <double>[-1, 1]) {
      final x = centerX + sign * legDx;
      final path = Path()
        ..moveTo(x, h - 0.65)
        ..lineTo(x, baseTop - w * 0.035)
        ..quadraticBezierTo(x, baseTop, centerX + sign * baseHalf, baseTop);
      canvas.drawPath(path, stroke);
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX - baseHalf, baseTop, baseHalf * 2, 3.4),
        const Radius.circular(1.7),
      ),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_MonitorPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.screenW != screenW ||
      oldDelegate.screenH != screenH;
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

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  List<SessionSummary> _sessions = const [];
  List<Workspace> _workspaces = const [];
  Set<String> _collapsed = {};
  final Map<String, DateTime> _readAt = {};
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
    kLastDevice.value = widget.host.name;
    // 首次连上后申请通知权限与忽略电池优化。
    WidgetsBinding.instance.addPostFrameCallback((_) => KeepAliveService.ensurePermissions());
    kResumeTick.addListener(_onResume);
  }

  @override
  void dispose() {
    kResumeTick.removeListener(_onResume);
    super.dispose();
  }

  void _onResume() {
    if (!mounted) return;
    _loadSessions();
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

  /// 左滑触发：先选工作区，再创建新会话。
  Future<void> _startNewSession() async {
    final blocks = <Workspace>[..._workspaces];
    final choice = await showModalBottomSheet<Workspace?>(
      context: context,
      backgroundColor: T.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 6, 8, 10),
                child: Text('选择工作区，新建会话',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: T.text)),
              ),
              if (blocks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('没有可用工作区', style: TextStyle(fontSize: 14, color: T.textSecondary)),
                ),
              for (final workspace in blocks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(sheetContext, workspace),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: T.bgGray,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_outlined, size: 20, color: T.textSecondary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  workspace.title.isEmpty ? '未命名工作区' : workspace.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15, color: T.text),
                                ),
                                if (workspace.path.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      workspace.path,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: T.textTertiary),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 18, color: T.textTertiary),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    try {
      final created = await widget.client.createSession(workspaceId: choice.workspaceId);
      await _loadSessions();
      if (!mounted) return;
      final session = _find(created.sessionId);
      if (session != null) {
        _open(session);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会话已创建，下拉刷新列表可见')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新建会话失败：$error'), duration: const Duration(seconds: 4)),
      );
    }
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
        if (v > 250) {
          // 右滑：打开会话抽屉
          _scaffoldKey.currentState?.openDrawer();
        } else if (v < -250) {
          // 左滑：新建会话（先选工作区）
          _startNewSession();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: T.bg,
        drawer: _drawer(),
        appBar: AppBar(
          // 去掉左上角 ☰：抽屉只靠右滑打开。
          // 必须关掉 automaticallyImplyLeading，否则 AppBar 检测到有 drawer 会自动塞回 DrawerButton。
          automaticallyImplyLeading: false,
          title: Text(_current?.projections.title ?? '新对话'),
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

/// 待发送的文件：选完立即出现，上传完成后补上回执。
class _Upload {
  _Upload(this.name, {this.receiptId, this.path, this.uploading = true});

  final String name;
  String? receiptId;
  String? path;
  bool uploading;

  void complete(UploadOutcome outcome) {
    receiptId = outcome.receiptId;
    path = outcome.path;
    uploading = false;
  }
}

/// 一条用户消息：文字 + 可选图片。
class _UserMsg {
  _UserMsg(this.text, [this.images = const []]);
  final String text;
  final List<ImageAttachment> images;
}

class _Turn {
  _Turn(this.turn, this.start);
  final int turn;
  final DateTime start;
  DateTime? end;
  String? endKind;
  final List<_UserMsg> users = [];
  final List<String> answers = [];
  final List<DeliveredFile> delivered = [];
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
  final List<_UserMsg> _orphanUsers = [];
  final List<String> _orphanAnswers = [];
  final List<SessionLogEvent> _events = [];
  int _oldestSeq = 0;
  bool _hasMore = false;
  bool _loadingOlder = false;
  bool _replaying = false;

  /// 每次拉取的历史窗口大小（约 10 轮）。
  static const int _pageSize = 120;
  final List<ApprovalRequest> _approvals = [];
  final List<UserQuestionRequest> _questions = [];
  final Map<String, Set<String>> _picked = {};
  Timer? _clock;
  final List<_Upload> _uploads = [];
  final List<PendingImage> _pendingImages = [];
  bool _uploading = false;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<DshEvent>? _sub;
  int _lastSeq = 0;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _resyncing = false;
  bool _wasDisconnected = false;
  bool _loading = true;
  bool _sending = false;
  bool _autoAllow = false;
  String? _pending;
  String? _error;
  String _modelLabel = '模型';

  /// 当前选中的模型（provider / id），用于面板高亮。
  String? _modelProvider;
  String? _modelId;

  /// 模型目录缓存：点开面板立即显示，不再每次请求。
  ModelCatalog? _modelCatalog;

  /// 缓存的刷新通知器（面板打开时可被后台刷新触发重建）。
  final ValueNotifier<int> _modelCatalogListenable = ValueNotifier<int>(0);
  bool _modelLoading = false;

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
    '[model changed',
    '[model switched',
  ];

  /// 方括号包裹的系统通知（如 [model changed: ...]）一律不显示。
  static bool _isMetaNotice(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return false;
    return trimmed.contains('generated by') ||
        trimmed.contains('model changed') ||
        trimmed.contains('session continues');
  }

  @override
  void initState() {
    super.initState();
    final next = widget.session.projections.nextModel;
    if (next != null) {
      _modelLabel = next.model;
      _modelProvider = next.provider;
      _modelId = next.model;
    }
    _load();
    kResumeTick.addListener(_onResumeSync);
    KeepAliveService.expired.addListener(_onKeepAliveExpired);
    // 「处理中…」的计时刷新
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _running) setState(() {});
    });
  }

  /// 后台超过 1 小时：主动断开，切回来时由 resume 重新连接。
  void _onKeepAliveExpired() {
    if (!mounted || !KeepAliveService.expired.value) return;
    _sub?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    setState(() => _error = '后台超过 1 小时，连接已断开');
  }

  Future<void> _load() async {
    try {
      final page = await widget.client.history(
        widget.session.sessionId,
        throughSeq: widget.session.projections.asOfSeq,
        maxMessages: _pageSize,
        turnWindow: const TurnWindow(120, 12),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _events
          ..clear()
          ..addAll(page.events);
        _hasMore = page.hasMore;
        _lastSeq = page.events.isEmpty ? 0 : page.events.last.seq;
        _rebuild();
      });
      _scrollToEnd(force: true);
      _subscribe();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  /// 用 `_events` 全量重建渲染结构（供首屏、重连、上拉加载复用）。
  void _rebuild() {
    _turns.clear();
    _orphanUsers.clear();
    _orphanAnswers.clear();
    _approvals.clear();
    _questions.clear();
    _replaying = true;
    for (final event in _events) {
      _ingest(event);
    }
    _replaying = false;
    // 注意：这里绝不能恢复 _pending。
    // _ingest 重放历史时，turn/start 会把 _pending 清空；若此处再写回旧值，
    // 灰色的"发送中"气泡就会复活，和真实消息并排显示两条一模一样的。
    _oldestSeq = _events.isEmpty ? 0 : _events.first.seq;
  }

  /// 上拉加载更早的历史。
  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _oldestSeq <= 1) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await widget.client.history(
        widget.session.sessionId,
        throughSeq: _lastSeq,
        beforeSeq: _oldestSeq,
        maxMessages: _pageSize,
        turnWindow: const TurnWindow(120, 12),
      );
      if (!mounted) return;
      final older = page.events.where((e) => e.seq < _oldestSeq).toList(growable: false);
      _apply(() {
        _loadingOlder = false;
        _hasMore = page.hasMore;
        if (older.isNotEmpty) {
          _events.insertAll(0, older);
          _rebuild();
        }
      }, preserveTop: true);
    } catch (_) {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  /// 退避重连：1s / 2s / 4s / 8s / 16s，最多 5 次，之后交给用户手动下拉。
  void _scheduleReconnect() {
    if (_retryTimer != null) return;
    if (_retryAttempt >= 5) return;
    final delay = Duration(seconds: 1 << _retryAttempt);
    _retryAttempt += 1;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      _resync();
    });
  }

  /// 重新拉历史基线 + 重新订阅。
  Future<void> _resync() async {
    if (_resyncing) return;
    _resyncing = true;
    try {
      // asOf 只能前进，绝不回退：服务端投影可能滞后于刚发出的事件。
      var asOf = _lastSeq;
      try {
        final sessions = await widget.client.listSessions();
        for (final s in sessions) {
          if (s.sessionId == widget.session.sessionId) {
            final server = s.projections.asOfSeq;
            if (server > asOf) asOf = server;
            break;
          }
        }
      } catch (_) {}
      if (asOf <= 0) return;

      final page = await widget.client.history(
        widget.session.sessionId,
        throughSeq: asOf,
        maxMessages: _pageSize,
        turnWindow: const TurnWindow(120, 12),
      );
      if (!mounted) return;
      _apply(() {
        // 合并去重，而不是整体替换：
        // 否则服务端快照滞后会把刚发出的消息抹掉，且之后的事件被 seq 过滤丢弃。
        final merged = <int, SessionLogEvent>{
          for (final event in _events) event.seq: event,
          for (final event in page.events) event.seq: event,
        };
        final seqs = merged.keys.toList()..sort();
        _events
          ..clear()
          ..addAll([for (final seq in seqs) merged[seq]!]);
        _hasMore = page.hasMore;
        final newest = _events.isEmpty ? asOf : _events.last.seq;
        if (newest > _lastSeq) _lastSeq = newest;
        _error = null;
        _rebuild();
      });
      _retryAttempt = 0;
      widget.onApprovalPending?.call(_approvals.isNotEmpty || _questions.isNotEmpty);
      // 不再强制跳到底：重连/切回前台时用户可能正在看历史。

      // 重新订阅（旧订阅可能已经静默失效）。
      _sub?.cancel();
      _subscribe();
    } catch (_) {
      _scheduleReconnect();
    } finally {
      _resyncing = false;
    }
  }

  /// 建立（或重建）跟随订阅。断线重连后需要重新调用。
  void _subscribe() {
    _sub?.cancel();
    _sub = widget.client
        .watch(
          widget.session.sessionId,
          options: const WatchOptions(includeSyncEvents: true, assistantStream: false),
        )
        .listen((event) {
        if (event is SessionLogEvent) {
          if (event.seq <= _lastSeq) return;
          _apply(() {
            _events.add(event);
            _ingest(event);
            _lastSeq = event.seq;
          });
          return;
        }
        if (event is AssistantChunkEvent) {
          // 流式已关闭（assistantStream: false），正常不会收到；留一行防御。
          return;
        }
        if (event is AssistantStreamEnded) {
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
          if (ok && _wasDisconnected) {
            _wasDisconnected = false;
            _resync();
          } else if (!ok) {
            _wasDisconnected = true;
          }
          return;
        }
        if (event is SessionSyncEvent) {
          // 跟随流在断线后重新建立：重新拉一次基线，避免界面缺段。
          _resync();
          return;
        }
      }, onError: (Object error) {
        if (!mounted) return;
        setState(() => _error = '连接异常，正在重连…');
        _scheduleReconnect();
      }, onDone: () {
        if (!mounted) return;
        setState(() => _error = '连接已断开，正在重连…');
        _scheduleReconnect();
      });
  }

  void _onResumeSync() {
    _resync();
  }

  /// 从历史里恢复「问了但没决定」的审批（订阅前就挂起的那种）。
  /// 注意：不再从历史里重建审批卡片。
  /// 历史里的 approval id 与 waterfall 的 eventId 不是同一个，
  /// 重建出来的卡片点了会静默无效（$events/result 找不到对应请求）。
  /// 只渲染实时 waterfall 事件下发的审批。

  void _onApproval(ApprovalRequest request) {
    if (_approvals.any((a) => a.eventId == request.eventId)) return;
    // 「全部允许」开启后，本会话所有审批一律自动通过（用户 2026-11-12 选择方案 A）。
    if (_autoAllow) {
      _answer(request, ApprovalDecision.allowOnce, silent: true);
      return;
    }
    setState(() {
      _approvals.add(request);
      });
    widget.onApprovalPending?.call(true);
  }

  void _ingest(SessionLogEvent event) {
    final data = event.data;
    switch (event.type) {
      case 'turn/start':
        final turn = data['turn'];
        _turns.add(_Turn(turn is int ? turn : _turns.length + 1, event.time));
        // 轮次已开始，乐观发送的灰泡不再需要
        _pending = null;
        return;
      case 'user/message':
        final message = data['message'];
        final map = message is Map ? message : data;
        final source = map['source'];
        final kind = source is Map ? source['kind'] as String? : null;
        // 白名单：只有真正由人发出的消息才显示。
        // DSH 会注入 time-context / model-selection / agent-instructions /
        // runtime context 等，它们的 kind 各不相同，黑名单永远补不全。
        if (kind != null && kind != 'user') return;
        final content = map['content'];
        final text = visibleTextOf(content);
        final images = imagePartsOf(content);
        if (text.trim().isEmpty && images.isEmpty) return;
        final head = text.trimLeft();
        if (text.trim().isNotEmpty) {
          if (_contextPrefixes.any(head.startsWith)) return;
          if (_isMetaNotice(text)) return;
        }
        if (_pending != null && text.trim().isNotEmpty) {
          final pending = _pending!.trim();
          final incoming = text.trim();
          if (incoming.contains(pending) || pending.contains(incoming)) _pending = null;
        }
        final userMsg = _UserMsg(text, images);
        if (_turns.isEmpty) {
          _orphanUsers.add(userMsg);
        } else {
          _turns.last.users.add(userMsg);
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
      case 'deliverables/presented':
        final files = DeliveredFile.fromEventData(data);
        if (files.isEmpty) return;
        final turnNumber = data['turn'];
        _Turn? owner;
        for (final candidate in _turns) {
          if (turnNumber is int && candidate.turn == turnNumber) {
            owner = candidate;
            break;
          }
        }
        owner ??= _turns.isNotEmpty ? _turns.last : null;
        if (owner == null) return;
        for (final file in files) {
          final exists = owner.delivered.any((f) => f.path == file.path);
          if (!exists) owner.delivered.add(file);
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
        if (!_replaying && refresh != null) {
          Future<void>.delayed(const Duration(milliseconds: 900), refresh);
        }
        return;
      default:
        return;
    }
  }

  void _scrollToEnd({bool force = false, int attempts = 3}) {
    if (!force) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final max = position.maxScrollExtent;
      final gap = (position.pixels - max).abs();
      if (gap > 4) _scroll.jumpTo(max);
      // 列表子项异步布局会让 maxScrollExtent 变大，多补几帧确保真的贴底
      if (attempts > 1 && gap > 4) {
        _scrollToEnd(force: true, attempts: attempts - 1);
      }
    });
  }

  /// 执行一次会改变列表高度的状态更新。
  ///
  /// 正序列表：新内容追加在视线下方，用户往上翻阅读时**画面完全不动**，
  /// 不需要任何补偿。只有当用户本来就贴着底部时才继续跟随。
  ///
  /// [preserveTop] 用于"在最上面加载更早历史"：内容插到了视线**上方**，
  /// 需要把插入的高度补回滚动位置，否则会跳。
  void _apply(VoidCallback mutate, {bool preserveTop = false}) {
    final hadClients = _scroll.hasClients;
    final beforePixels = hadClients ? _scroll.position.pixels : 0.0;
    final beforeMax = hadClients ? _scroll.position.maxScrollExtent : 0.0;
    setState(mutate);
    // 只有"加载更早历史"需要补偿（内容插到了视线**上方**）。
    // 其他任何情况都不动画面：新内容长在下方，不会推动已有内容。
    if (!hadClients || !preserveTop) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final afterMax = _scroll.position.maxScrollExtent;
      final delta = afterMax - beforeMax;
      if (delta.abs() < 0.5) return;
      final target = (beforePixels + delta).clamp(0.0, afterMax);
      if ((_scroll.offset - target).abs() > 0.5) _scroll.jumpTo(target);
    });
  }

  bool get _running => _turns.isNotEmpty && !_turns.last.done;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_uploads.any((u) => u.uploading)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件还在上传，请稍候')),
      );
      return;
    }
    if ((text.isEmpty && _uploads.isEmpty && _pendingImages.isEmpty) || _sending) return;
    final uploads = List<_Upload>.from(_uploads);
    final images = List<PendingImage>.from(_pendingImages);
    final receiptIds = [
      for (final upload in uploads)
        if (upload.receiptId != null) upload.receiptId!,
    ];
    final workspacePaths = [
      for (final upload in uploads)
        if (upload.path != null) upload.path!,
    ];
    setState(() {
      _sending = true;
      _pending = text.isEmpty ? null : text;
    });
    _input.clear();
    // 发完消息不跳底：保持当前位置，方便从自己这条往上/往下读。
    try {
      final buffer = StringBuffer(text.isEmpty ? '' : text);
      if (workspacePaths.isNotEmpty) {
        buffer.write('\n\n已上传文件：');
        buffer.write(workspacePaths.join('\n'));
      }
      final body = buffer.toString().trim();
      final started = DateTime.now();
      await widget.client.prompt(
        widget.session.sessionId,
        body,
        images: [for (final image in images) image.toPromptImage()],
        fileReceiptIds: receiptIds,
      );
      if (kDebugMode) {
        final ms = DateTime.now().difference(started).inMilliseconds;
        debugPrint('[send] prompt 耗时 ${ms}ms（图片 ${images.length} 张，文件 ${uploads.length} 个）');
      }
      if (mounted) {
        setState(() {
          if (uploads.isNotEmpty) _uploads.clear();
          if (images.isNotEmpty) _pendingImages.clear();
        });
      }
      // 兜底：30 秒内没等到真实消息，也把灰泡清掉
      Future<void>.delayed(const Duration(seconds: 30), () {
        if (mounted && _pending != null) setState(() => _pending = null);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _pending = null);
      final message = isImageUnsupportedError(error) ? '该模型不支持图片' : '发送失败：$error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 点 ＋ 弹出的附件面板（相册 / 文件）。
  Future<void> _openAttachSheet() async {
    if (_uploading) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFFF3F3F5),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFC9C9CE),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _attachTile(
                    icon: Icons.image_outlined,
                    label: '相册',
                    background: const Color(0xFFDCE9FF),
                    foreground: const Color(0xFF2F6FE4),
                    onTap: () => Navigator.pop(context, 'image'),
                  ),
                  _attachTile(
                    icon: Icons.folder_outlined,
                    label: '文件',
                    background: const Color(0xFFFFE7C7),
                    foreground: const Color(0xFFD98600),
                    onTap: () => Navigator.pop(context, 'file'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await _pickAndUpload(imagesOnly: choice == 'image');
  }

  Widget _attachTile({
    required IconData icon,
    required String label,
    required Color background,
    required Color foreground,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 28, color: foreground),
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(fontSize: 14, color: T.text)),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload({required bool imagesOnly}) async {
    if (_uploading) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: imagesOnly ? FileType.image : FileType.any,
        allowMultiple: imagesOnly,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      // 图片：本地压缩后直接进待发送列表，不走工作区上传（秒回）
      if (imagesOnly) {
        final added = <PendingImage>[];
        // 先把原图立刻放进待发送区（缩略图马上可见），再后台压缩替换
        for (final file in result.files) {
          final raw = file.bytes;
          if (raw == null) continue;
          added.add(PendingImage(raw, file.name, compressing: raw.length > kMaxInlineImageBytes));
        }
        if (added.isEmpty || !mounted) return;
        setState(() => _pendingImages.addAll(added));

        for (final image in added) {
          if (!image.compressing) continue;
          final started = DateTime.now();
          final original = image.bytes;
          try {
            final compressed = await compute(compressImageBytes, original);
            if (kDebugMode) {
              final ms = DateTime.now().difference(started).inMilliseconds;
              debugPrint('[image] 压缩 ${original.length} → ${compressed.length} 字节，耗时 ${ms}ms');
            }
            if (!mounted) return;
            setState(() {
              image.bytes = compressed;
              image.compressing = false;
            });
          } catch (_) {
            if (!mounted) return;
            setState(() => image.compressing = false);
          }
        }
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;
      if (bytes.length > kMaxUploadBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件超过 30 MiB，请先压缩或拆分')),
        );
        return;
      }
      // 立刻显示卡片（上传中），上传完成后原地更新为可发送
      final placeholder = _Upload(file.name);
      setState(() {
        _uploads.add(placeholder);
        _uploading = true;
      });
      final picked = PickedUpload(file.name, bytes);
      try {
        final outcome = await uploadToSession(widget.client, widget.session.sessionId, picked);
        if (!mounted) return;
        setState(() => placeholder.complete(outcome));
      } catch (error) {
        if (!mounted) return;
        setState(() => _uploads.remove(placeholder));
        rethrow;
      }
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
    setState(() => _autoAllow = !_autoAllow);
  }

  Future<void> _pickModel() async {
    // 先弹出面板（用缓存），后台再刷新列表，避免每次点都卡一下。
    final cached = _modelCatalog;
    if (cached == null) {
      setState(() => _modelLoading = true);
      try {
        _modelCatalog = await widget.client.listModels();
      } catch (error) {
        if (mounted) {
          setState(() => _modelLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载模型失败：$error')));
        }
        return;
      }
      if (!mounted) return;
      setState(() => _modelLoading = false);
    }

    final chosen = await showModalBottomSheet<({String provider, String model, String name})>(
      context: context,
      backgroundColor: T.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: ListenableBuilder(
          listenable: _modelCatalogListenable,
          builder: (context, _) {
            final catalog = _modelCatalog;
            if (catalog == null) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              children: [
                for (final group in catalog.groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                    child: Text(group.name,
                        style: const TextStyle(fontSize: T.tiny, color: T.textSecondary)),
                  ),
                  for (final model in group.models)
                    _modelRow(
                      sheetContext,
                      provider: group.id,
                      id: model.id,
                      name: model.name,
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );

    if (chosen == null || !mounted) return;

    // 立即更新胶囊，不等网络往返。
    final previousLabel = _modelLabel;
    final previousProvider = _modelProvider;
    final previousId = _modelId;
    setState(() {
      _modelLabel = chosen.name;
      _modelProvider = chosen.provider;
      _modelId = chosen.model;
    });
    try {
      await widget.client.setModel(
        widget.session.sessionId,
        provider: chosen.provider,
        model: chosen.model,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _modelLabel = previousLabel;
        _modelProvider = previousProvider;
        _modelId = previousId;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('切换失败：$error')));
    }
  }

  /// 模型行：选中项整行浅蓝底 + 蓝字 + 左侧竖条。
  Widget _modelRow(
    BuildContext sheetContext, {
    required String provider,
    required String id,
    required String name,
  }) {
    final selected = provider == _modelProvider && id == _modelId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pop(sheetContext, (provider: provider, model: id, name: name)),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEDF1FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(
                color: selected ? T.brand : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: T.body,
                    color: selected ? T.brand : T.text,
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded, size: 22, color: T.brand),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    kResumeTick.removeListener(_onResumeSync);
    KeepAliveService.expired.removeListener(_onKeepAliveExpired);
    _retryTimer?.cancel();
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _olderHint() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_loadingOlder) ...[
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: T.textTertiary),
            ),
            const SizedBox(width: 8),
            const Text('加载更早的消息…',
                style: TextStyle(fontSize: T.tiny, color: T.textTertiary)),
          ] else
            Text(
              _hasMore ? '上滑加载更早的消息' : '没有更多了',
              style: const TextStyle(fontSize: T.tiny, color: T.textTertiary),
            ),
        ],
      ),
    );
  }

  Widget _userBubble(_UserMsg msg, {bool pending = false}) {
    final text = msg.text;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
          margin: const EdgeInsets.only(left: 48, top: 8, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
          decoration: BoxDecoration(
            color: pending ? const Color(0xFFF2F2F4) : T.bubble,
            borderRadius: BorderRadius.circular(T.rBubble),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (msg.images.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: text.trim().isEmpty ? 0 : 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: [
                      for (final ref in msg.images)
                        AttachmentImage(
                          client: widget.client,
                          sessionId: widget.session.sessionId,
                          reference: ref,
                          maxWidth: 160,
                          maxHeight: 200,
                        ),
                    ],
                  ),
                ),
              if (text.trim().isNotEmpty)
                Text(
                  text,
                  style: TextStyle(
                    fontSize: T.body,
                    height: 1.6,
                    color: pending ? T.textSecondary : T.text,
                  ),
                ),
            ],
          ),
        ),
    );
  }

  /// 待发送图片的缩略图（本地字节，零延迟）。
  Widget _pendingImagesStrip() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < _pendingImages.length; i += 1)
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  _pendingImages[i].bytes,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
              if (_pendingImages[i].compressing)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0x55000000),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                  ),
                ),
              Positioned(
                right: -6,
                top: -6,
                child: GestureDetector(
                  onTap: () => setState(() => _pendingImages.removeAt(i)),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Color(0xCC000000),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _statusLine(_Turn turn) {
    final String label;
    if (!turn.done) {
      label = '处理中… ${_shortElapsed(turn.start)}';
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

  /// 运行中的简短计时：25秒 / 1分20秒。
  static String _shortElapsed(DateTime start) {
    final seconds = DateTime.now().difference(start).inSeconds;
    if (seconds < 60) return '${seconds < 1 ? 1 : seconds}秒';
    return '${seconds ~/ 60}分${seconds % 60}秒';
  }

  Widget _answerBlock(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SimpleMarkdown(text),
          FileStrip(
            client: widget.client,
            sessionId: widget.session.sessionId,
            text: text,
            cwd: widget.session.cwd,
          ),
        ],
      ),
    );
  }

  List<Widget> _turnWidgets(_Turn turn) {
    final widgets = <Widget>[];
    for (final msg in turn.users) {
      widgets.add(_userBubble(msg));
    }
    // 乐观发送的灰泡放在本轮用户消息之后、状态行之前，避免列表末尾二次跳动
    if (_pending != null && identical(turn, _turns.isNotEmpty ? _turns.last : null)) {
      // 兜底去重：本轮已有同文本的用户消息时，不再画灰泡
      final pendingText = _pending!.trim();
      final alreadyThere = turn.users.any((u) {
        final text = u.text.trim();
        return text.isNotEmpty && (text.contains(pendingText) || pendingText.contains(text));
      });
      if (!alreadyThere) {
        widgets.add(_userBubble(_UserMsg(_pending!), pending: true));
      }
    }
    widgets.add(_statusLine(turn));
    for (final answer in turn.answers) {
      widgets.add(_answerBlock(answer));
    }
    if (turn.delivered.isNotEmpty) {
      widgets.add(DeliverableCard(
        client: widget.client,
        sessionId: widget.session.sessionId,
        cwd: widget.session.cwd,
        files: List<DeliveredFile>.from(turn.delivered),
      ));
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
                  if (!_autoAllow) await _toggleAutoAllow();
                  if (!mounted) return;
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F6FF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(color: T.brand, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Text('?',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(width: 8),
              const Text('需要你回答',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: T.brand)),
            ],
          ),
          const SizedBox(height: 10),
          Text(question.question, style: const TextStyle(fontSize: 15, height: 1.55, color: T.text)),
          if (question.detail != null && question.detail!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(question.detail!,
                style: const TextStyle(fontSize: T.tiny, height: 1.5, color: T.textSecondary)),
          ],
          const SizedBox(height: 12),
          for (final option in question.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _questionOption(
                label: option.label,
                selected: picked.contains(option.label),
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
                  if (!question.multiSelect) {
                    // 先让选中态显示出来，再提交
                    Future<void>.delayed(const Duration(milliseconds: 160), () {
                      if (mounted) _submitQuestion(request);
                    });
                  }
                },
              ),
            ),
          if (question.multiSelect)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: picked.isEmpty ? null : () => _submitQuestion(request),
                  style: FilledButton.styleFrom(
                    backgroundColor: T.brand,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  ),
                  child: const Text('提交'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 提问选项：整行卡片，选中时浅蓝底 + 蓝边 + 对勾。
  Widget _questionOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE3ECFF) : T.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? T.brand : T.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: selected ? T.brand : T.text,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ),
            if (selected) const Icon(Icons.check_rounded, size: 18, color: T.brand),
          ],
        ),
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
            if (_pendingImages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _pendingImagesStrip(),
                ),
              ),
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
                            if (_uploads[i].uploading)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 1.6, color: T.brand),
                                ),
                              ),
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
                  onTap: _uploading ? null : _openAttachSheet,
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
                _chip(label: shortModelName(_modelLabel), onTap: _pickModel),
                const SizedBox(width: 8),
                _autoAllowButton(),
                const Spacer(),
                _primaryButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 发送 / 停止 合并成一个按钮：
  /// 空闲＝蓝色发送箭头；运行中＝灰色停止方块；发送请求在途＝转圈。
  Widget _primaryButton() {
    final running = _running;
    final busy = _sending && !running;
    const background = T.brand;
    return SizedBox(
      width: 36,
      height: 36,
      child: FilledButton(
        onPressed: busy ? null : (running ? _stop : _send),
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
          backgroundColor: background,
        ),
        child: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(
                running ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                size: 20,
                color: Colors.white,
              ),
      ),
    );
  }

  /// 常驻的「本次会话全部允许」开关：关＝蓝，开＝绿。
  Widget _autoAllowButton() {
    const onColor = Color(0xFF32C48D);
    final color = _autoAllow ? onColor : T.brand;
    return GestureDetector(
      onTap: _toggleAutoAllow,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: _autoAllow ? color : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.4),
        ),
        child: Icon(
          Icons.bolt_rounded,
          size: 18,
          color: _autoAllow ? Colors.white : color,
        ),
      ),
    );
  }

  Widget _chip({IconData? icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(T.rChip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: T.chipBg, borderRadius: BorderRadius.circular(T.rChip)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: T.brand),
              const SizedBox(width: 6),
            ],
            Text(label, style: const TextStyle(fontSize: 11, color: T.brand)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 按"旧 → 新"构造，然后用 reverse:true 反转。
    // 反向列表的视口锚在底部：新消息向下延伸、加载历史向上追加，
    // 都不会推动当前可视内容，因此不会跳页。
    final children = <Widget>[];
    for (final msg in _orphanUsers) {
      children.add(_userBubble(msg));
    }
    for (final text in _orphanAnswers) {
      children.add(_answerBlock(text));
    }
    for (final turn in _turns) {
      children.add(KeyedSubtree(
        key: ValueKey<int>(turn.turn),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _turnWidgets(turn),
        ),
      ));
    }
    if (_pending != null && _turns.isEmpty) {
      children.add(_userBubble(_UserMsg(_pending!), pending: true));
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
              : SelectionArea(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.pixels < 200 && _hasMore && !_loadingOlder) {
                        _loadOlder();
                      }
                      return false;
                    },
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(T.pad, 8, T.pad, 16),
                      children: [
                        if (_events.isNotEmpty) _olderHint(),
                        ...children,
                      ],
                    ),
                  ),
                ),
        ),
        if (_questions.isNotEmpty) _questionPanel(),
        if (_approvals.isNotEmpty) _approvalPanel(),
        _composer(),
      ],
    );
  }
}
