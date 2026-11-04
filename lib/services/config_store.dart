import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_config.dart';

/// 配置持久化：整份配置以 JSON 字符串存在 shared_preferences 里。
class ConfigStore {
  static const String _key = 'notes_app_config_v1';

  AppConfig? _cached;

  AppConfig? get current => _cached;

  Future<AppConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      final config = AppConfig.fromJson(
        decoded is Map<String, Object?> ? decoded : null,
      );
      _cached = config;
      return config;
    } on FormatException {
      return null;
    }
  }

  Future<void> save(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
    _cached = config;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _cached = null;
  }
}
