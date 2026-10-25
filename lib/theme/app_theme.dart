import 'package:flutter/material.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.sidebar,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.onAccent,
  });

  final Color bg;
  final Color sidebar;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceSunken;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color muted;
  final Color faint;
  final Color accent;
  final Color accentSoft;
  final Color success;
  final Color warning;
  final Color danger;
  final Color onAccent;

  static const dark = AppPalette(
    bg: Color(0xFF080B10),
    sidebar: Color(0xFF0B0F15),
    surface: Color(0xFF10151D),
    surfaceAlt: Color(0xFF151C26),
    surfaceSunken: Color(0xFF0B1016),
    border: Color(0x14FFFFFF),
    borderStrong: Color(0x26FFFFFF),
    text: Color(0xFFE9EEF7),
    muted: Color(0xFF94A2B6),
    faint: Color(0xFF5F6B7C),
    accent: Color(0xFFF6821F),
    accentSoft: Color(0x1FF6821F),
    success: Color(0xFF37D399),
    warning: Color(0xFFF5B544),
    danger: Color(0xFFFF6B81),
    onAccent: Color(0xFF231204),
  );

  static const light = AppPalette(
    bg: Color(0xFFF2F5F9),
    sidebar: Color(0xFFFAFBFD),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF6F8FB),
    surfaceSunken: Color(0xFFEDF1F6),
    border: Color(0x140B1220),
    borderStrong: Color(0x1F0B1220),
    text: Color(0xFF101725),
    muted: Color(0xFF5B6879),
    faint: Color(0xFF8996A7),
    accent: Color(0xFFEE7112),
    accentSoft: Color(0x1AEE7112),
    success: Color(0xFF0E9F6E),
    warning: Color(0xFFB45309),
    danger: Color(0xFFD92D46),
    onAccent: Color(0xFFFFFFFF),
  );

  static const monoTracking = 0.1;

  @override
  AppPalette copyWith({
    Color? bg,
    Color? sidebar,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceSunken,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? muted,
    Color? faint,
    Color? accent,
    Color? accentSoft,
    Color? success,
    Color? warning,
    Color? danger,
    Color? onAccent,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      sidebar: sidebar ?? this.sidebar,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      faint: faint ?? this.faint,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      onAccent: onAccent ?? this.onAccent,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    );
  }
}

extension AppContext on BuildContext {
  AppPalette get colors => Theme.of(this).extension<AppPalette>()!;
  TextTheme get texts => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

ThemeData buildAppTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Segoe UI',
  );
  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: brightness,
  ).copyWith(
    primary: c.accent,
    onPrimary: c.onAccent,
    surface: c.surface,
    onSurface: c.text,
    error: c.danger,
    outline: c.border,
  );

  final textTheme = base.textTheme
      .apply(
        fontFamily: 'Segoe UI',
        bodyColor: c.text,
        displayColor: c.text,
      )
      .copyWith(
        displaySmall: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: c.text,
          height: 1.12,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: c.text,
          height: 1.18,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: c.text,
          height: 1.3,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: c.text,
          height: 1.35,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: c.text,
          height: 1.35,
        ),
        bodyLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: c.text,
          height: 1.55,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: c.muted,
          height: 1.55,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: c.faint,
          height: 1.5,
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: c.text,
        ),
        labelMedium: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: c.muted,
        ),
        labelSmall: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: c.faint,
        ),
      );

  OutlineInputBorder inputBorder(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.surface,
    dividerColor: c.border,
    extensions: [c],
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceSunken,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: c.faint, fontSize: 13.5),
      labelStyle: TextStyle(color: c.muted, fontSize: 13),
      floatingLabelStyle: TextStyle(color: c.accent, fontSize: 12),
      helperStyle: TextStyle(color: c.faint, fontSize: 11.5, height: 1.5),
      errorStyle: TextStyle(color: c.danger, fontSize: 11.5),
      prefixIconColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.focused) ? c.accent : c.faint,
      ),
      suffixIconColor: c.faint,
      border: inputBorder(c.border),
      enabledBorder: inputBorder(c.border),
      focusedBorder: inputBorder(c.accent, 1.4),
      errorBorder: inputBorder(c.danger, 1.2),
      focusedErrorBorder: inputBorder(c.danger, 1.4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return c.surfaceAlt;
          }
          if (states.contains(WidgetState.pressed)) {
            return Color.lerp(c.accent, Colors.black, 0.15)!;
          }
          if (states.contains(WidgetState.hovered)) {
            return Color.lerp(c.accent, Colors.white, 0.08)!;
          }
          return c.accent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.disabled) ? c.faint : c.onAccent;
        }),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        elevation: WidgetStateProperty.all(0),
        minimumSize: WidgetStateProperty.all(const Size(0, 40)),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) return c.surfaceAlt;
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.disabled) ? c.faint : c.text;
        }),
        side: WidgetStateProperty.all(BorderSide(color: c.borderStrong)),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        minimumSize: WidgetStateProperty.all(const Size(0, 40)),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.hovered) ? c.text : c.muted;
        }),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        minimumSize: WidgetStateProperty.all(const Size(0, 36)),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.hovered) ? c.text : c.muted;
        }),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.hovered) ? c.surfaceAlt : Colors.transparent;
        }),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return c.onAccent;
        return c.muted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return c.accent;
        return c.surfaceSunken;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        return c.borderStrong;
      }),
      trackOutlineWidth: WidgetStateProperty.all(1),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? c.accent : Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(c.onAccent),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(color: c.borderStrong, width: 1.4),
      visualDensity: VisualDensity.compact,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: c.border),
      ),
      textStyle: TextStyle(color: c.text, fontSize: 11.5),
      waitDuration: const Duration(milliseconds: 500),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surfaceAlt,
      elevation: 12,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
      textStyle: TextStyle(color: c.text, fontSize: 13),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 24,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surfaceAlt,
      contentTextStyle: TextStyle(color: c.text, fontSize: 13),
      actionTextColor: c.accent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.surfaceSunken,
      linearMinHeight: 6,
      circularTrackColor: c.border,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(7),
      radius: const Radius.circular(8),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.hovered) ? c.faint : c.borderStrong;
      }),
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: c.muted,
      textColor: c.text,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    ),
  );
}
