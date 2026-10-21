import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ReadingProgress {
  const ReadingProgress({
    this.currentSection = 0,
    this.totalSections = 0,
    this.epubCfi,
    this.fraction = 0,
  });

  final int currentSection;
  final int totalSections;
  final String? epubCfi;
  final double fraction;

      double get value => totalSections > 0
        ? ((currentSection - 1 + fraction) / totalSections).clamp(0.0, 1.0)
      : fraction.clamp(0.0, 1.0);

  bool get hasStarted => currentSection > 0 || fraction > 0 || epubCfi != null;

  Map<String, Object?> toJson() => {
        'currentSection': currentSection,
        'totalSections': totalSections,
        'epubCfi': epubCfi,
        'fraction': fraction,
      };

  factory ReadingProgress.fromJson(Map<String, dynamic> json) => ReadingProgress(
        currentSection: json['currentSection'] as int? ?? 0,
        totalSections: json['totalSections'] as int? ?? 0,
        epubCfi: json['epubCfi'] as String?,
        fraction: (json['fraction'] as num?)?.toDouble() ?? 0,
      );
}

class ReadingProgressStore {
  static const _key = 'reading_progress_v1';

  SharedPreferencesAsync? _preferences;
  Map<String, ReadingProgress>? _cache;

  SharedPreferencesAsync get _store => _preferences ??= SharedPreferencesAsync();

  Future<Map<String, ReadingProgress>> loadAll() async {
    if (_cache != null) return Map.of(_cache!);
    final value = await _store.getString(_key);
    if (value == null) return _cache = {};

    final decoded = jsonDecode(value) as Map<String, dynamic>;
    return _cache = decoded.map((key, value) => MapEntry(
          key,
          ReadingProgress.fromJson(value as Map<String, dynamic>),
        ));
  }

  Future<void> save(String bookId, ReadingProgress progress) async {
    final progressByBook = await loadAll();
    progressByBook[bookId] = progress;
    _cache = progressByBook;
    await _store.setString(
      _key,
      jsonEncode(progressByBook.map((key, value) => MapEntry(key, value.toJson()))),
    );
  }
}