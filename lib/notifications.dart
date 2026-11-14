import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 任务完成通知（用户 2026-11-14 选择方案 A：真正的系统横幅）。
///
/// 只在 App 不在前台时弹，前台看得到就不打扰。
class AppNotifications {
  AppNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const String _channelId = 'dsh_r_task_done';
  static const String _channelName = '任务完成';

  /// 应用是否在前台（由 main 里的生命周期监听维护）。
  static final ValueNotifier<bool> foreground = ValueNotifier<bool>(true);

  /// 启动时调用一次；失败不抛，最坏情况就是没有通知。
  static Future<void> init() async {
    if (_ready || !Platform.isAndroid) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings);

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      try {
        await android?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: '对话任务结束后的提醒',
          importance: Importance.high,
        ));
      } catch (_) {}
      try {
        await android?.requestNotificationsPermission();
      } catch (_) {}
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// 任务完成提醒。[title] 会话名，[body] 简述。
  static Future<void> taskDone({required String title, required String body}) async {
    if (!_ready || !Platform.isAndroid) return;
    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: '对话任务结束后的提醒',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
      );
    } catch (_) {}
  }
}