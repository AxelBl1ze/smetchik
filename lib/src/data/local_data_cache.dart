import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists a compact, per-user snapshot for read-only offline fallback.
/// Mutations still require the server so signed documents cannot diverge.
class LocalDataCache {
  const LocalDataCache();

  Future<void> write(String key, Object value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(key, jsonEncode(value));
    } catch (_) {
      // A cache miss must never prevent normal online work.
    }
  }

  Future<Map<String, dynamic>?> readMap(String key) async {
    final value = await _read(key);
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Future<List<Map<String, dynamic>>?> readList(String key) async {
    final value = await _read(key);
    if (value is! List) return null;
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<dynamic> _read(String key) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final value = preferences.getString(key);
      if (value == null || value.isEmpty) return null;
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }
}
