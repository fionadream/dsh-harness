import 'package:flutter/material.dart';

import 'main.dart' show account, kFontScale, GatePage;

/// 设置：字号调节 + 退出登录。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double _scale = kFontScale.value;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 6),
            child: Text('字体大小', style: TextStyle(fontSize: 13, color: Colors.black54)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('A', style: TextStyle(fontSize: 13, color: Colors.black54)),
                      Text('${(_scale * 100).round()}%', style: const TextStyle(fontSize: 13)),
                      const Text('A', style: TextStyle(fontSize: 20, color: Colors.black54)),
                    ],
                  ),
                  Slider(
                    value: _scale,
                    min: 0.85,
                    max: 1.6,
                    divisions: 15,
                    onChanged: (value) {
                      setState(() => _scale = value);
                      kFontScale.value = value;
                    },
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('预览：你可以在设置里调整整个应用的字体大小。',
                        style: TextStyle(fontSize: 15, height: 1.5)),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: const Icon(Icons.logout_rounded, size: 20, color: Colors.red),
                title: const Text('退出登录', style: TextStyle(fontSize: 15, color: Colors.red)),
                onTap: () async {
                  await account.logout();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(builder: (_) => const GatePage()),
                    (_) => false,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}