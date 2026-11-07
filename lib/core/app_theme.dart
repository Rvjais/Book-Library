import 'package:flutter/material.dart';

/// The warm, paper-and-leather palette used across LibReady.
class AppColors {
  const AppColors._();

  static const Color ink = Color(0xFF2A2118);
  static const Color inkSoft = Color(0xFF5C4B39);
  static const Color parchment = Color(0xFFF6EFE0);
  static const Color paper = Color(0xFFFFFAF0);
  static const Color leather = Color(0xFF7A5230);
  static const Color leatherDeep = Color(0xFF4B2F18);
  static const Color brass = Color(0xFFC39A5F);
  static const Color forest = Color(0xFF3E5C4A);
  static const Color woodLight = Color(0xFF9A6738);
  static const Color woodMid = Color(0xFF74492A);
  static const Color woodDark = Color(0xFF402613);
  static const Color cream = Color(0xFFF3E8D2);
  static const Color creamDim = Color(0xFFD9C6A6);
}

/// Serif stack. Georgia exists on iOS/macOS, Noto Serif on Android; the
/// generic `serif` fallback covers everything else.
const String kSerif = 'Georgia';
const List<String> kSerifFallback = <String>[
  'Noto Serif',
  'Times New Roman',
  'serif',
];

TextStyle serifStyle({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: kSerif,
    fontFamilyFallback: kSerifFallback,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: Color(0xFF6B4525),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFEAD9C2),
      onPrimaryContainer: AppColors.ink,
      secondary: AppColors.forest,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFDCE7DD),
      onSecondaryContainer: Color(0xFF1C2C22),
      surface: AppColors.paper,
      onSurface: AppColors.ink,
      surfaceContainerHighest: Color(0xFFEDE1CC),
      outline: Color(0xFFCFC0A8),
      error: Color(0xFF8C2F2F),
    );
    return _base(scheme, AppColors.parchment);
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: Color(0xFFD8B98C),
      onPrimary: Color(0xFF2A1B0C),
      primaryContainer: Color(0xFF4A3520),
      onPrimaryContainer: Color(0xFFF5E4C9),
      secondary: Color(0xFF9DBFA8),
      onSecondary: Color(0xFF102016),
      surface: Color(0xFF1C1813),
      onSurface: Color(0xFFEDE3D4),
      surfaceContainerHighest: Color(0xFF2A241D),
      outline: Color(0xFF4B4136),
      error: Color(0xFFE7A9A0),
    );
    return _base(scheme, const Color(0xFF14110D));
  }

  static ThemeData _base(ColorScheme scheme, Color background) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
    );
  }
}

/// Small helper so we never touch the deprecated `withOpacity`.
Color fade(Color color, double alpha) => color.withValues(alpha: alpha);
