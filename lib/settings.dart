import 'package:flutter/material.dart';

import 'main.dart' show account, kFontScale, GatePage;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _card(
            child: ListTile(
              leading: const Icon(Icons.format_size_rounded, size: 20),
              title: const Text('字体大小', style: TextStyle(fontSize: 15)),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const FontSizePage()),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _card(
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
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: child,
        ),
      );
}

/// 字号子页面：滑块 + 实时预览。
class FontSizePage extends StatefulWidget {
  const FontSizePage({super.key});

  @override
  State<FontSizePage> createState() => _FontSizePageState();
}

class _FontSizePageState extends State<FontSizePage> {
  late double _scale = kFontScale.value;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('字体大小', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text('预览', style: TextStyle(fontSize: 12, color: Colors.black45)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: ListView(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F0FE),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text('预览文字大小', style: TextStyle(fontSize: 15 * _scale)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '你可以拖动滑块来调整字体大小。',
                    style: TextStyle(fontSize: 15 * _scale, height: 1.55),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '当前：${(_scale * 100).round()}%',
                    style: TextStyle(fontSize: 13 * _scale, color: Colors.black45),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('A', style: TextStyle(fontSize: 13, color: Colors.black54)),
                      Text('${(_scale * 100).round()}%', style: const TextStyle(fontSize: 13)),
                      const Text('A', style: TextStyle(fontSize: 22, color: Colors.black54)),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}