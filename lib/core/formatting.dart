import 'dart:math' as math;

String formatShelfDate(int millis) {
  if (millis <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${date.month}/${date.day}/${date.year}';
}

String formatShortDate(int millis) {
  if (millis <= 0) return '—';
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return '$diff days ago';
  return formatShelfDate(millis);
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String formatPercent(double value) =>
    '${(value.clamp(0.0, 1.0) * 100).round()}%';

String formatMinutes(int seconds) {
  if (seconds < 60) return 'less than a minute';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

/// Turns "the_psychology_of_money (1).pdf" into "The Psychology Of Money".
String titleFromFileName(String fileName) {
  var name = fileName;
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  name = name.replaceAll(RegExp(r'[_\s]+'), ' ').trim();
  name = name.replaceAll(RegExp(r'\s*\((?:pdfdrive|z-lib|libgen|1|copy)[^)]*\)',
      caseSensitive: false), '');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.isEmpty) return 'Untitled';
  if (name.length > 120) name = name.substring(0, 120).trim();
  return name.split(' ').map((word) {
    if (word.isEmpty) return word;
    if (word.toUpperCase() == word && word.length <= 4) return word;
    return '${word[0].toUpperCase()}${word.substring(1)}';
  }).join(' ');
}

String initialsFor(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(2)
      .toList();
  if (words.isEmpty) return '?';
  return words.map((w) => w[0].toUpperCase()).join();
}

String truncate(String value, int max) {
  if (value.length <= max) return value;
  return '${value.substring(0, math.max(0, max - 1)).trimRight()}…';
}

String stripHtml(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
