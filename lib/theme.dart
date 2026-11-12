import 'package:flutter/material.dart';

/// 设计令牌：全部样式只从这里取，四个页面共用。
class T {
  T._();

  // 颜色
  static const bg = Color(0xFFFFFFFF);
  static const bgGray = Color(0xFFF5F6F7);
  static const text = Color(0xFF111111);
  static const textSecondary = Color(0xFF8A8A8E);
  static const textTertiary = Color(0xFFB0B0B4);
  static const brand = Color(0xFF4D6BFE);
  static const bubble = Color(0xFFEEF3FF);
  static const divider = Color(0xFFEFEFEF);
  static const codeBg = Color(0xFFF7F7F8);
  static const selected = Color(0xFFEDF1FF);
  static const chipBg = Color(0xFFEEF2FF);
  static const danger = Color(0xFFE5484D);
  static const warnBg = Color(0xFFFFFBEB);

  // 圆角
  static const rCard = 16.0;
  static const rBubble = 18.0;
  static const rInput = 26.0;
  static const rCode = 12.0;
  static const rChip = 18.0;

  // 间距
  static const pad = 20.0;
  static const gapS = 8.0;
  static const gapM = 12.0;
  static const gapL = 16.0;
  static const rowH = 56.0;

  // 字体
  static const body = 17.0;
  static const bodyH = 1.75;
  static const letter = 0.2;
  static const title = 22.0;
  static const appbar = 17.0;
  static const secondary = 15.0;
  static const tiny = 13.0;

  static const bodyStyle = TextStyle(
    fontSize: body,
    height: bodyH,
    letterSpacing: letter,
    color: text,
  );

  static const secondaryStyle = TextStyle(
    fontSize: secondary,
    height: 1.5,
    color: textSecondary,
  );

  static ThemeData theme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.light),
      splashFactory: InkRipple.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: text, size: 24),
        titleTextStyle: TextStyle(
          fontSize: appbar,
          fontWeight: FontWeight.w600,
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
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: body, height: bodyH, letterSpacing: letter, color: text),
        bodyMedium: TextStyle(fontSize: secondary, height: 1.5, color: text),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: text),
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
      child: Text(text, style: const TextStyle(fontSize: T.secondary, color: T.textSecondary)),
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
                child: Text(label, style: TextStyle(fontSize: T.body, color: fg)),
              ),
              if (trailing != null) ...[
                DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: T.body, color: T.textSecondary),
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
