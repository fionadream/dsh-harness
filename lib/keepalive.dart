import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// 切到后台后允许保持连接的最长时间；超时且用户没切回来就断开。
const Duration kKeepAliveWindow = Duration(hours: 1);

/// 前台服务的空任务处理器：只负责让进程不被冻结，不做业务。
@pragma('vm:entry-point')
void keepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 定期唤醒一次，保持进程与网络活跃。
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// 保活控制：进入后台启动前台服务并开始倒计时，回到前台立即撤销。
class KeepAliveService {
  KeepAliveService._();

  static Timer? _timer;
  static bool _initialized = false;
  static bool _running = false;

  /// 由 main 注入：返回 true 表示"现在有正在进行的下载，别断开"。
  static bool Function()? busyGuard;

  /// 是否因为超过 1 小时被主动断开（供 UI 提示）。
  static final ValueNotifier<bool> expired = ValueNotifier<bool>(false);

  static bool get isRunning => _running;

  /// App 启动时调用一次。
  static void init() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'dsh_r_keepalive',
        channelName: 'DSH R 连接保持',
        channelDescription: '保持与电脑的连接，切回应用或满 1 小时后自动关闭。',
        onlyAlertOnce: true,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// 申请通知权限 + 忽略电池优化（只做一次，失败不阻塞）。
  static Future<void> ensurePermissions() async {
    if (!Platform.isAndroid) return;
    try {
      final notification = await FlutterForegroundTask.checkNotificationPermission();
      if (notification != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (_) {}

    try {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (_) {}
  }

  /// 切到后台：启动前台服务，并开始 1 小时倒计时。
  static Future<void> start({String? device}) async {
    init();
    expired.value = false;
    _armTimer();

    if (_running) {
      try {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'DSH R',
          notificationText: device == null || device.isEmpty ? '已保持连接' : '已连接 $device',
          callback: keepAliveCallback,
        );
      } catch (_) {}
      return;
    }

    try {
      final result = await FlutterForegroundTask.startService(
        serviceId: 4152,
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: 'DSH R',
        notificationText: device == null || device.isEmpty ? '已保持连接' : '已连接 $device',
        callback: keepAliveCallback,
      );
      _running = result is ServiceRequestSuccess;
    } catch (_) {
      _running = false;
    }
  }

  /// 起一个 1 小时的计时；到点时若正在下载则续期，不打断任务。
  static void _armTimer() {
    _timer?.cancel();
    _timer = Timer(kKeepAliveWindow, () async {
      final busy = busyGuard?.call() ?? false;
      if (busy) {
        // 正在下载：再给一小时，且不标记过期
        _armTimer();
        return;
      }
      expired.value = true;
      await stop();
    });
  }

  /// 回到前台：撤销倒计时并停止服务。
  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    if (!_running) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    _running = false;
  }

  /// 更新通知里的设备名（连接成功后调用）。
  static Future<void> updateDevice(String device) async {
    if (!_running) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'DSH R',
        notificationText: '已连接 $device',
        callback: keepAliveCallback,
      );
    } catch (_) {}
  }
}