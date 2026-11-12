import 'package:flutter/material.dart';

import 'files.dart';
import 'main.dart' show account, kAppVersion, kFontScale, GatePage, secureStoreRead, secureStoreWrite;
import 'theme.dart';

const String kSaveDirKey = 'files.saveDir';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _saveDir;

  @override
  void initState() {
    super.initState();
    _loadSaveDir();
  }

  Future<void> _loadSaveDir() async {
    final raw = await secureStoreRead(kSaveDirKey);
    if (!mounted) return;
    setState(() => _saveDir = (raw == null || raw.isEmpty) ? null : raw);
  }

  Future<void> _pickSaveDir() async {
    final dir = await pickSaveDirectory();
    if (dir == null || dir.isEmpty) return;
    final writable = await directoryWritable(dir);
    if (!mounted) return;
    if (!writable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个目录不可写，请换一个（或使用「每次询问」）')),
      );
      return;
    }
    await secureStoreWrite(kSaveDirKey, dir);
    if (!mounted) return;
    setState(() => _saveDir = dir);
  }

  Future<void> _resetSaveDir() async {
    await secureStoreWrite(kSaveDirKey, '');
    if (!mounted) return;
    setState(() => _saveDir = null);
  }

  String get _saveDirLabel {
    final dir = _saveDir;
    if (dir == null || dir.isEmpty) return '每次询问';
    final parts = dir.replaceAll('\\', '/').split('/').where((e) => e.isNotEmpty).toList();
    if (parts.length <= 2) return dir;
    return '…/${parts.sublist(parts.length - 2).join('/')}';
  }

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
                  icon: Icons.text_fields_rounded,
                  label: '字体',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const FontPage()),
                  ),
                ),
                const Divider(height: 0.8, color: T.divider, indent: 48),
                TRow(
                  icon: Icons.download_rounded,
                  label: '文件保存目录',
                  trailing: Text(_saveDirLabel,
                      style: const TextStyle(fontSize: T.tiny, color: T.textSecondary)),
                  onTap: _pickSaveDir,
                ),
                if (_saveDir != null) ...[
                  const Divider(height: 0.8, color: T.divider, indent: 48),
                  TRow(
                    icon: Icons.restart_alt_rounded,
                    label: '重置为「每次询问」',
                    showChevron: false,
                    onTap: _resetSaveDir,
                  ),
                ],
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
            child: Text('DSH R',
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

/// 字体子页面：字号 + 粗细 + 实时预览。
class FontPage extends StatefulWidget {
  const FontPage({super.key});

  @override
  State<FontPage> createState() => _FontPageState();
}

class _FontPageState extends State<FontPage> {
  late double _scale = kFontScale.value;
  late double _weight = kWeight.value;

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
        title: const Text('字体'),
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
                            style: TextStyle(
                              fontSize: T.body * _scale,
                              fontWeight: weightOf(_weight),
                              color: T.text,
                            )),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '你可以拖动滑块来调整字体大小和粗细。',
                      style: TextStyle(
                        fontSize: T.body * _scale,
                        height: T.bodyH,
                        fontWeight: weightOf(_weight),
                        color: T.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '当前 ${(_scale * 100).round()}% · ${_weightLabel(_weight)}',
                      style: TextStyle(fontSize: T.tiny * _scale, color: T.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _row('字号', '${(_scale * 100).round()}%'),
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
                  const SizedBox(height: 6),
                  _row('粗细', _weightLabel(_weight)),
                  SliderTheme(
                    data: const SliderThemeData(
                      activeTrackColor: T.brand,
                      thumbColor: T.brand,
                      inactiveTrackColor: T.divider,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _weight,
                      min: 300,
                      max: 700,
                      divisions: 8,
                      onChanged: (value) {
                        setState(() => _weight = value);
                        kWeight.value = value;
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

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: T.textSecondary)),
        Text(value, style: const TextStyle(fontSize: 13, color: T.text)),
      ],
    );
  }

  String _weightLabel(double value) {
    if (value <= 350) return '细';
    if (value <= 450) return '标准';
    if (value <= 550) return '中等';
    if (value <= 650) return '偏粗';
    return '粗';
  }
}
