import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_slot.dart';
import '../models/scene.dart';

class AppSettings {
  const AppSettings({
    this.theme = ThemeMode.system,
    this.demo = false,
    this.slots = DeviceSlot.defaults,
    this.customScenes = const [],
  });
  final ThemeMode theme;
  final bool demo;
  final List<DeviceSlot> slots;
  final List<LightScene> customScenes;
  AppSettings copyWith({
    ThemeMode? theme,
    bool? demo,
    List<DeviceSlot>? slots,
    List<LightScene>? customScenes,
  }) => AppSettings(
    theme: theme ?? this.theme,
    demo: demo ?? this.demo,
    slots: slots ?? this.slots,
    customScenes: customScenes ?? this.customScenes,
  );
  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'demo': demo,
    'slots': slots.map((s) => s.toJson()).toList(),
    'customScenes': customScenes.map((s) => s.toJson()).toList(),
  };
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final raw = json['slots'];
    final slots = DeviceSlot.defaults.map((slot) {
      final matches = raw is List
          ? raw.whereType<Map>().where((s) => s['id'] == slot.id)
          : <Map>[];
      if (matches.isEmpty) return slot;
      final item = matches.first;
      return DeviceSlot(
        id: slot.id,
        name:
            item['name'] is String && (item['name'] as String).trim().isNotEmpty
            ? item['name'] as String
            : slot.name,
        entityId:
            item['entityId'] is String &&
                RegExp(r'^light\.[a-z0-9_]+$').hasMatch(item['entityId'])
            ? item['entityId'] as String
            : null,
      );
    }).toList();
    final scenes = <LightScene>[];
    final rawScenes = json['customScenes'];
    if (rawScenes is List) {
      for (final rawScene in rawScenes.take(LightScene.maxCustomScenes)) {
        try {
          if (rawScene is! Map<String, dynamic>) continue;
          final scene = LightScene.fromJson(rawScene);
          if (!scenes.any((s) => s.id == scene.id)) scenes.add(scene);
        } on FormatException {
          // A damaged scene must not discard the user's other preferences.
        }
      }
    }
    return AppSettings(
      customScenes: List.unmodifiable(scenes),
      demo: json['demo'] == true,
      theme:
          ThemeMode.values.where((t) => t.name == json['theme']).firstOrNull ??
          ThemeMode.system,
      slots: slots,
    );
  }
}

abstract interface class SettingsStore {
  Future<AppSettings> read();
  Future<void> write(AppSettings settings);
}

class SettingsRepository implements SettingsStore {
  final _preferences = SharedPreferencesAsync();
  static const _key = 'smartlight.settings';
  @override
  Future<AppSettings> read() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return const AppSettings();
    } on TypeError {
      return const AppSettings();
    }
  }

  @override
  Future<void> write(AppSettings settings) =>
      _preferences.setString(_key, jsonEncode(settings.toJson()));
}
