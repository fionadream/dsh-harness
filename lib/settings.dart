import 'package:flutter/material.dart';

import 'main.dart' show account, kAppVersion, kFontScale, GatePage;
import 'theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bgGray,
      appBar: AppBar(
        backgroundColor: T.bgGray,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          const TGroupLabel('应用'),
          TCard(
            child: Column(
              children: [
                TRow(
                  icon: Icons.format_size_rounded,
                  label: '字体大小',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const FontSizePage()),
                  ),
                ),
              ],
            ),
          ),
          const TGroupLabel('账户'),
          TCard(
            child: TRow(
              icon: Icons.logout_rounded,
              label: '退出登录',
              color: T.danger,
              showChevron: false,
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
          const SizedBox(height: 24),
          const Center(
            child: Text('DSH Harness',
                style: TextStyle(fontSize: 12, color: T.textTertiary)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('版本 $kAppVersion',
                style: const TextStyle(fontSize: 12, color: T.textTertiary)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
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
      backgroundColor: T.bgGray,
      appBar: AppBar(
        backgroundColor: T.bgGray,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('字体大小'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TGroupLabel('预览'),
          Expanded(
            child: TCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: ListView(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: T.bubble,
                          borderRadius: BorderRadius.circular(T.rBubble),
                        ),
                        child: Text('预览文字大小',
                            style: TextStyle(fontSize: T.body * _scale, color: T.text)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '你可以拖动滑块来调整字体大小。',
                      style: TextStyle(fontSize: T.body * _scale, height: T.bodyH, color: T.text),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '当前 ${(_scale * 100).round()}%',
                      style: TextStyle(
                          fontSize: T.tiny * _scale, color: T.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('A', style: TextStyle(fontSize: 13, color: T.textSecondary)),
                      Text('${(_scale * 100).round()}%',
                          style: const TextStyle(fontSize: 13, color: T.text)),
                      const Text('A', style: TextStyle(fontSize: 22, color: T.textSecondary)),
                    ],
                  ),
                  SliderTheme(
                    data: const SliderThemeData(
                      activeTrackColor: T.brand,
                      thumbColor: T.brand,
                      inactiveTrackColor: T.divider,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _scale,
                      min: 0.85,
                      max: 1.6,
                      divisions: 15,
                      onChanged: (value) {
                        setState(() => _scale = value);
                        kFontScale.value = value;
                      },
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
