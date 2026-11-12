import 'package:flutter/material.dart';

/// 全局字体粗细（300–700，默认 500）。设置页可调。
final ValueNotifier<double> kWeight = ValueNotifier<double>(500);

/// 把 300–700 的数值映射到 Flutter 的 FontWeight。
FontWeight weightOf(double value) {
  final index = ((value - 100) / 100).round().clamp(1, 9) - 1;
  return FontWeight.values[index];
}

/// 设计令牌：全部样式只从这里取，四个页面共用。
class T {
  T._();

  // 颜色
  static const bg = Color(0xFFFFFFFF);
  static const bgGray = Color(0xFFF5F6F7);
  static const text = Color(0xFF1B1B1D);
  static const textSecondary = Color(0xFF8A8A8E);
  static const textTertiary = Color(0xFFB0B0B4);
  static const brand = Color(0xFF4D6BFE);
  static const bubble = Color(0xFFEBF3FE);
  static const divider = Color(0xFFEFEFEF);
  static const codeBg = Color(0xFFF7F7F8);
  static const selected = Color(0xFFEDF1FF);
  static const chipBg = Color(0xFFEEF2FF);
  static const danger = Color(0xFFE5484D);
  static const warnBg = Color(0xFFFFFBEB);
  static const success = Color(0xFF32C48D);
  static const warn = Color(0xFFF5A623);

  // 圆角
  static const rCard = 16.0;
  static const rBubble = 18.0;
  static const rInput = 26.0;
  static const rCode = 12.0;
  static const rChip = 18.0;

  // 间距
  static const pad = 26.0;
  static const gapS = 8.0;
  static const gapM = 12.0;
  static const gapL = 16.0;
  static const rowH = 56.0;
  static const indentSession = 44.0;

  // 字号
  static const body = 17.0;
  static const bodyH = 1.75;
  static const letter = 0.2;
  static const title = 22.0;
  static const appbar = 17.0;
  static const secondary = 15.0;
  static const tiny = 13.0;

  static TextStyle bodyStyle({Color? color}) => TextStyle(
        fontSize: body,
        height: bodyH,
        letterSpacing: letter,
        color: color ?? text,
        fontWeight: weightOf(kWeight.value),
      );

  static TextStyle secondaryStyle() => TextStyle(
        fontSize: secondary,
        height: 1.5,
        color: textSecondary,
        fontWeight: weightOf(kWeight.value),
      );

  static ThemeData theme() {
    final w = weightOf(kWeight.value);
    final strong = weightOf((kWeight.value + 200).clamp(300, 900));
    final soft = weightOf((kWeight.value - 100).clamp(300, 900));

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.light),
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: text, size: 24),
        titleTextStyle: TextStyle(
          fontSize: appbar,
          fontWeight: strong,
          color: text,
          letterSpacing: 0,
        ),
      ),
      dividerTheme: const DividerThemeData(color: divider, thickness: 0.8, space: 0.8),
      listTileTheme: const ListTileThemeData(
        iconColor: text,
        textColor: text,
        horizontalTitleGap: 10,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(fontSize: body, height: bodyH, letterSpacing: letter, color: text, fontWeight: w),
        bodyMedium: TextStyle(fontSize: secondary, height: 1.5, color: text, fontWeight: w),
        bodySmall: TextStyle(fontSize: tiny, color: textSecondary, fontWeight: w),
        titleLarge: TextStyle(fontSize: 20, fontWeight: strong, color: text),
        titleMedium: TextStyle(fontSize: body, fontWeight: strong, color: text),
        labelLarge: TextStyle(fontSize: secondary, fontWeight: strong, color: text),
        labelMedium: TextStyle(fontSize: tiny, fontWeight: soft, color: textSecondary),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF2B2B2E),
      ),
    );
  }
}

/// 页面通用：白底、圆角卡片。
class TCard extends StatelessWidget {
  const TCard({super.key, required this.child, this.margin = const EdgeInsets.symmetric(horizontal: 16)});
  final Widget child;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(color: T.bg, borderRadius: BorderRadius.circular(T.rCard)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 灰色分组标题。
class TGroupLabel extends StatelessWidget {
  const TGroupLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(text, style: TextStyle(fontSize: T.secondary, color: T.textSecondary, fontWeight: weightOf(kWeight.value))),
    );
  }
}

/// 设置/抽屉里的标准行：图标 + 文字 + 可选右侧内容。
class TRow extends StatelessWidget {
  const TRow({
    super.key,
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.color,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? color;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? T.text;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: T.rowH,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: TextStyle(fontSize: T.body, color: fg, fontWeight: weightOf(kWeight.value))),
              ),
              if (trailing != null) ...[
                DefaultTextStyle.merge(
                  style: TextStyle(fontSize: T.body, color: T.textSecondary, fontWeight: weightOf(kWeight.value)),
                  child: trailing!,
                ),
                const SizedBox(width: 4),
              ],
              if (showChevron)
                const Icon(Icons.chevron_right, size: 20, color: T.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
