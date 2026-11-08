import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_types.dart';
import 'reader_settings.dart';

/// Persists user preferences (reader typography, theme, sort orders).
class SettingsRepository extends ChangeNotifier {
  SettingsRepository._(
    this._prefs,
    this._reader,
    this._sortMode,
    this._showShelfDates,
    this._shelfDisplay,
    this._themeMode,
  );

  static const _kTheme = 'reader.theme';
  static const _kTexture = 'reader.texture';
  static const _kFontSize = 'reader.fontSize';
  static const _kLineHeight = 'reader.lineHeight';
  static const _kMargins = 'reader.margins';
  static const _kJustify = 'reader.justify';
  static const _kSerif = 'reader.serif';
  static const _kTurn = 'reader.turnStyle';
  static const _kBrightness = 'reader.brightness';
  static const _kPageNumber = 'reader.showPageNumber';
  static const _kSort = 'library.sort';
  static const _kShelfDates = 'library.shelfDates';
  static const _kShelfDisplay = 'library.shelfDisplay';
  static const _kThemeMode = 'app.themeMode';

  final SharedPreferences _prefs;
  ReaderSettings _reader;
  SortMode _sortMode;
  bool _showShelfDates;
  ShelfDisplay _shelfDisplay;
  ThemeMode _themeMode;

  static Future<SettingsRepository> load() async {
    final prefs = await SharedPreferences.getInstance();

    final reader = ReaderSettings(
      theme: _readEnum(ReaderTheme.values, prefs.getString(_kTheme), ReaderTheme.sepia),
      texture: _readEnum(PageTexture.values, prefs.getString(_kTexture), PageTexture.parchment),
      fontSize: (prefs.getDouble(_kFontSize) ?? 19).clamp(13.0, 32.0),
      lineHeight: (prefs.getDouble(_kLineHeight) ?? 1.55).clamp(1.15, 2.4),
      margins: (prefs.getDouble(_kMargins) ?? 24).clamp(8.0, 64.0),
      justify: prefs.getBool(_kJustify) ?? true,
      serif: prefs.getBool(_kSerif) ?? true,
      turnStyle: _readEnum(
        PageTurnStyle.values,
        prefs.getString(_kTurn),
        PageTurnStyle.curl,
      ),
      brightness: (prefs.getDouble(_kBrightness) ?? 0).clamp(0.0, 0.65),
      showPageNumber: prefs.getBool(_kPageNumber) ?? true,
    );

    return SettingsRepository._(
      prefs,
      reader,
      _readEnum(SortMode.values, prefs.getString(_kSort), SortMode.recent),
      prefs.getBool(_kShelfDates) ?? true,
      _readEnum(
        ShelfDisplay.values,
        prefs.getString(_kShelfDisplay),
        ShelfDisplay.covers,
      ),
      _readEnum(ThemeMode.values, prefs.getString(_kThemeMode), ThemeMode.system),
    );
  }

  ReaderSettings get reader => _reader;
  SortMode get sortMode => _sortMode;
  bool get showShelfDates => _showShelfDates;
  ShelfDisplay get shelfDisplay => _shelfDisplay;
  ThemeMode get themeMode => _themeMode;

  Future<void> updateReader(ReaderSettings value) async {
    _reader = value;
    notifyListeners();
    await Future.wait<void>([
      _prefs.setString(_kTheme, value.theme.name),
      _prefs.setString(_kTexture, value.texture.name),
      _prefs.setDouble(_kFontSize, value.fontSize),
      _prefs.setDouble(_kLineHeight, value.lineHeight),
      _prefs.setDouble(_kMargins, value.margins),
      _prefs.setBool(_kJustify, value.justify),
      _prefs.setBool(_kSerif, value.serif),
      _prefs.setString(_kTurn, value.turnStyle.name),
      _prefs.setDouble(_kBrightness, value.brightness),
      _prefs.setBool(_kPageNumber, value.showPageNumber),
    ]);
  }

  Future<void> setSortMode(SortMode mode) async {
    if (_sortMode == mode) return;
    _sortMode = mode;
    notifyListeners();
    await _prefs.setString(_kSort, mode.name);
  }

  Future<void> setShowShelfDates(bool value) async {
    if (_showShelfDates == value) return;
    _showShelfDates = value;
    notifyListeners();
    await _prefs.setBool(_kShelfDates, value);
  }

  Future<void> setShelfDisplay(ShelfDisplay value) async {
    if (_shelfDisplay == value) return;
    _shelfDisplay = value;
    notifyListeners();
    await _prefs.setString(_kShelfDisplay, value.name);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _prefs.setString(_kThemeMode, mode.name);
  }

  static T _readEnum<T extends Enum>(List<T> values, String? name, T fallback) {
    if (name == null) return fallback;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
