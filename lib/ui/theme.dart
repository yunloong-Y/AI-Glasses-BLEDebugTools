import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ============================================================
/// iOS 风格主题系统
/// 模拟 SF Pro 字体、iOS 配色、圆角卡片、毛玻璃质感
/// ============================================================

class AppTheme {
  // iOS system blue
  static const Color iosBlue = Color(0xFF007AFF);
  static const Color iosGreen = Color(0xFF34C759);
  static const Color iosRed = Color(0xFFFF3B30);
  static const Color iosOrange = Color(0xFFFF9500);
  static const Color iosPurple = Color(0xFF5856D6);
  static const Color iosTeal = Color(0xFF30B0C7);
  static const Color iosGray = Color(0xFF8E8E93);
  static const Color iosGray2 = Color(0xFFAEAEB2);
  static const Color iosGray3 = Color(0xFFC7C7CC);
  static const Color iosGray4 = Color(0xFFD1D1D6);
  static const Color iosGray5 = Color(0xFFE5E5EA);
  static const Color iosGray6 = Color(0xFFF2F2F7);

  // Card / background colors
  static const Color lightBg = Color(0xFFF2F2F7); // iOS grouped background
  static const Color lightCard = Colors.white;
  static const Color darkBg = Color(0xFF000000);
  static const Color darkCard = Color(0xFF1C1C1E);

  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        scaffoldBackgroundColor: lightBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: iosBlue,
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).copyWith(
          headlineLarge: GoogleFonts.inter(
              fontWeight: FontWeight.w700, fontSize: 32, letterSpacing: -0.5),
          headlineMedium: GoogleFonts.inter(
              fontWeight: FontWeight.w700, fontSize: 24, letterSpacing: -0.3),
          titleLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 17),
          titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
          bodyLarge: GoogleFonts.inter(fontSize: 16, height: 1.4),
          bodyMedium: GoogleFonts.inter(fontSize: 14, height: 1.4),
          labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
          labelSmall: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 12),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: lightBg.withOpacity(0.9),
          foregroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: false,
          titleTextStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 30,
            color: Colors.black,
            letterSpacing: -0.5,
          ),
          toolbarHeight: 44,
        ),
        cardTheme: CardThemeData(
          color: lightCard,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: iosGray6,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: iosBlue, width: 1.5),
          ),
          labelStyle: GoogleFonts.inter(fontSize: 14, color: iosGray),
          hintStyle: GoogleFonts.inter(fontSize: 14, color: iosGray2),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: iosBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: iosBlue,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            side: const BorderSide(color: iosGray4),
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 15),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: iosBlue,
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 15),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1C1C1E),
          contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: lightBg,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white.withOpacity(0.95),
          indicatorColor: iosBlue.withOpacity(0.12),
          indicatorShape: const StadiumBorder(),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? iosBlue
                  : iosGray,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            return IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected) ? iosBlue : iosGray,
            );
          }),
          height: 56,
          elevation: 0,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return Colors.white;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return iosGreen;
            return iosGray4;
          }),
          trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        ),
        dividerTheme: DividerThemeData(
          color: iosGray5,
          thickness: 0.5,
          space: 0.5,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: iosBlue,
        ),
      );

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: darkBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: iosBlue,
          brightness: Brightness.dark,
          surface: darkCard,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
          headlineLarge: GoogleFonts.inter(
              fontWeight: FontWeight.w700, fontSize: 32, letterSpacing: -0.5),
          headlineMedium: GoogleFonts.inter(
              fontWeight: FontWeight.w700, fontSize: 24, letterSpacing: -0.3),
          titleLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 17),
          titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
          bodyLarge: GoogleFonts.inter(fontSize: 16, height: 1.4),
          bodyMedium: GoogleFonts.inter(fontSize: 14, height: 1.4),
          labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
          labelSmall: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 12),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: darkBg.withOpacity(0.9),
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: false,
          titleTextStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 30,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
          toolbarHeight: 44,
        ),
        cardTheme: CardThemeData(
          color: darkCard,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2C2C2E),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: iosBlue, width: 1.5),
          ),
          labelStyle: GoogleFonts.inter(fontSize: 14, color: iosGray2),
          hintStyle: GoogleFonts.inter(fontSize: 14, color: iosGray),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: iosBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: iosBlue,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            side: const BorderSide(color: Color(0xFF3A3A3C)),
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 15),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: iosBlue,
            textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 15),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2C2C2E),
          contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: darkCard,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: darkCard.withOpacity(0.95),
          indicatorColor: iosBlue.withOpacity(0.12),
          indicatorShape: const StadiumBorder(),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? iosBlue
                  : iosGray,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            return IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected) ? iosBlue : iosGray,
            );
          }),
          height: 56,
          elevation: 0,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.all(Colors.white),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return iosGreen;
            return const Color(0xFF3A3A3C);
          }),
          trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        ),
        dividerTheme: DividerThemeData(
          color: const Color(0xFF3A3A3C),
          thickness: 0.5,
          space: 0.5,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: iosBlue,
        ),
      );
}

/// iOS 风格 inset grouped 卡片容器
class IosCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? margin;
  final EdgeInsets padding;

  const IosCard({
    super.key,
    required this.child,
    this.margin,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

/// iOS 风格空状态占位组件
class IosEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final double iconSize;

  const IosEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconSize = 56,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final grayColor = isDark ? AppTheme.iosGray : AppTheme.iosGray2;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.iosGray6.withOpacity(isDark ? 0.3 : 1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: iconSize, color: grayColor),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: grayColor,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 14, color: grayColor),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// iOS 风格 Section Header (分组标题)
class IosSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const IosSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, right: 16, top: 24, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.iosGray,
                letterSpacing: 0.5,
            ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
