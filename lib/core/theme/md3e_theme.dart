import 'package:flutter/material.dart';
import 'md3e_colors.dart';
import 'md3e_shapes.dart';
import 'md3e_typography.dart';

/// Complete Material 3 Expressive (MD3E) Theme Provider
class MD3ETheme {
  MD3ETheme._();

  /// 默认品牌色的深 / 浅色主题（含 MiSans TextTheme，只构建一次）。
  /// 全屏播放器等深色沉浸页面在浅色模式下也用 [dark] 包裹，保证白色系控件与深色背景匹配。
  static final ThemeData dark = darkTheme();
  static final ThemeData light = lightTheme();

  static ThemeData darkTheme({Color primary = MD3EColors.spotifyGreen}) =>
      _build(MD3EColors.createColorScheme(primary: primary, brightness: Brightness.dark));

  /// 浅色主题：组件规则与深色完全一致，只替换色板（跟随系统深浅色）。
  static ThemeData lightTheme({Color primary = MD3EColors.spotifyGreen}) =>
      _build(MD3EColors.createColorScheme(primary: primary, brightness: Brightness.light));

  static ThemeData _build(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;
    // englishLike 的样式 inherit=false，ThemeData 合并时不会补颜色；
    // FlexibleSpaceBar 等组件会对 titleLarge.color 做非空断言，必须显式着色。
    final textTheme = MD3ETypography.createTextTheme().apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      // 全局默认字族：未显式指定字族的 TextStyle（按钮、导航标签等）同样使用 MiSans
      fontFamily: MD3ETypography.fontFamily,
      textTheme: textTheme,

      // App Bar Theme
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.bold,
        ),
      ),

      // Expressive Navigation Bar
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer.withAlpha(220),
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
        height: 70,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.primary, size: 24);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
          );
        }),
      ),

      // Navigation Rail for desktop / tablet
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainerLowest,
        indicatorColor: colorScheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.primary),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),

      // Card Theme (MD3E Expressive rounded cards)
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainer,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: MD3EShapes.roundedLarge,
        ),
        margin: EdgeInsets.zero,
      ),

      // Expressive Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // Filled Button (Pill shaped)
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),

      // Outlined Button (Pill shaped)
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: colorScheme.outlineVariant),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),

      // Chip Theme
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: colorScheme.primary,
        labelStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(side: BorderSide.none),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),

      // Expressive Slider Theme
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.onSurfaceVariant.withAlpha(50),
        thumbColor: isDark ? Colors.white : colorScheme.onSurface,
        overlayColor: colorScheme.primary.withAlpha(40),
        trackHeight: 4.0,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
      ),

      // Bottom Sheet Theme
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        modalBackgroundColor: colorScheme.surfaceContainerHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: MD3EShapes.topSheet,
        ),
        elevation: 16,
        showDragHandle: true,
        dragHandleColor: colorScheme.onSurfaceVariant.withAlpha(100),
      ),

      // Input Decoration Theme (Search & Form Fields)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: MD3EShapes.pill,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: MD3EShapes.pill,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: MD3EShapes.pill,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
