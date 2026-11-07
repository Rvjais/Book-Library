import 'package:flutter/material.dart';

import '../core/app_theme.dart';

enum ReaderTheme { light, sepia, dark, black }

enum PageTurnStyle { curl, flip, slide, fade, none }

extension ReaderThemeLabel on ReaderTheme {
  String get label {
    switch (this) {
      case ReaderTheme.light:
        return 'Paper';
      case ReaderTheme.sepia:
        return 'Sepia';
      case ReaderTheme.dark:
        return 'Night';
      case ReaderTheme.black:
        return 'Black';
    }
  }
}

extension PageTurnStyleLabel on PageTurnStyle {
  String get label {
    switch (this) {
      case PageTurnStyle.curl:
        return 'Page curl';
      case PageTurnStyle.flip:
        return 'Book flip';
      case PageTurnStyle.slide:
        return 'Slide';
      case PageTurnStyle.fade:
        return 'Fade';
      case PageTurnStyle.none:
        return 'Instant';
    }
  }

  String get description {
    switch (this) {
      case PageTurnStyle.curl:
        return 'Drag the corner and the paper peels over.';
      case PageTurnStyle.flip:
        return 'The page swings across the spine like a real leaf.';
      case PageTurnStyle.slide:
        return 'The page glides away.';
      case PageTurnStyle.fade:
        return 'Cross-fade between pages.';
      case PageTurnStyle.none:
        return 'No animation, fastest.';
    }
  }
}

class ReaderPalette {
  const ReaderPalette({
    required this.page,
    required this.text,
    required this.muted,
    required this.accent,
    required this.rule,
  });

  final Color page;
  final Color text;
  final Color muted;
  final Color accent;
  final Color rule;

  bool get isDark => page.computeLuminance() < 0.35;
}

ReaderPalette paletteFor(ReaderTheme theme) {
  switch (theme) {
    case ReaderTheme.light:
      return const ReaderPalette(
        page: Color(0xFFFCFAF4),
        text: Color(0xFF241C14),
        muted: Color(0xFF7C6A56),
        accent: Color(0xFF8A5A2B),
        rule: Color(0xFFD8CCB8),
      );
    case ReaderTheme.sepia:
      return const ReaderPalette(
        page: Color(0xFFF2E5CB),
        text: Color(0xFF40301C),
        muted: Color(0xFF7C6647),
        accent: Color(0xFF8A5A2B),
        rule: Color(0xFFCBB58F),
      );
    case ReaderTheme.dark:
      return const ReaderPalette(
        page: Color(0xFF171513),
        text: Color(0xFFD7CDBE),
        muted: Color(0xFF8C8377),
        accent: Color(0xFFC9A87C),
        rule: Color(0xFF3A342C),
      );
    case ReaderTheme.black:
      return const ReaderPalette(
        page: Color(0xFF000000),
        text: Color(0xFFC8C1B6),
        muted: Color(0xFF7A746B),
        accent: Color(0xFFC9A87C),
        rule: Color(0xFF2A251F),
      );
  }
}

@immutable
class ReaderSettings {
  const ReaderSettings({
    this.theme = ReaderTheme.sepia,
    this.fontSize = 19,
    this.lineHeight = 1.55,
    this.margins = 24,
    this.justify = true,
    this.serif = true,
    this.turnStyle = PageTurnStyle.curl,
    this.brightness = 0,
    this.showPageNumber = true,
  });

  final ReaderTheme theme;
  final double fontSize;
  final double lineHeight;
  final double margins;
  final bool justify;
  final bool serif;
  final PageTurnStyle turnStyle;
  final double brightness;
  final bool showPageNumber;

  ReaderPalette get palette => paletteFor(theme);

  String? get fontFamily => serif ? kSerif : null;

  List<String>? get fontFamilyFallback => serif ? kSerifFallback : null;

  TextAlign get textAlign => justify ? TextAlign.justify : TextAlign.start;

  TextStyle textStyle({double scale = 1, FontWeight? weight, Color? color}) {
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      fontSize: fontSize * scale,
      height: lineHeight,
      color: color ?? palette.text,
      fontWeight: weight,
    );
  }

  ReaderSettings copyWith({
    ReaderTheme? theme,
    double? fontSize,
    double? lineHeight,
    double? margins,
    bool? justify,
    bool? serif,
    PageTurnStyle? turnStyle,
    double? brightness,
    bool? showPageNumber,
  }) {
    return ReaderSettings(
      theme: theme ?? this.theme,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      margins: margins ?? this.margins,
      justify: justify ?? this.justify,
      serif: serif ?? this.serif,
      turnStyle: turnStyle ?? this.turnStyle,
      brightness: brightness ?? this.brightness,
      showPageNumber: showPageNumber ?? this.showPageNumber,
    );
  }
}
