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
    this.presetScenes = const [],
    this.deletedPresetIds = const [],
    this.roomSceneIds,
    this.swapPreviewTubes = false,
    this.genericRoomPreview = true,
  });
  final ThemeMode theme;
  final bool demo;
  final List<DeviceSlot> slots;
  final List<LightScene> customScenes;
  final List<LightScene> presetScenes;
  final List<String> deletedPresetIds;

  /// Null keeps the existing first-four default; an empty list hides all.
  final List<String>? roomSceneIds;
  final bool swapPreviewTubes;
  final bool genericRoomPreview;
  AppSettings copyWith({
    ThemeMode? theme,
    bool? demo,
    List<DeviceSlot>? slots,
    List<LightScene>? customScenes,
    List<LightScene>? presetScenes,
    List<String>? deletedPresetIds,
    List<String>? roomSceneIds,
    bool? swapPreviewTubes,
    bool? genericRoomPreview,
  }) => AppSettings(
    theme: theme ?? this.theme,
    demo: demo ?? this.demo,
    slots: slots ?? this.slots,
    customScenes: customScenes ?? this.customScenes,
    presetScenes: presetScenes ?? this.presetScenes,
    deletedPresetIds: deletedPresetIds ?? this.deletedPresetIds,
    roomSceneIds: roomSceneIds ?? this.roomSceneIds,
    swapPreviewTubes: swapPreviewTubes ?? this.swapPreviewTubes,
    genericRoomPreview: genericRoomPreview ?? this.genericRoomPreview,
  );
  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'demo': demo,
    'slots': slots.map((s) => s.toJson()).toList(),
    'customScenes': customScenes.map((s) => s.toJson()).toList(),
    'presetScenes': presetScenes.map((s) => s.toJson()).toList(),
    'deletedPresetIds': deletedPresetIds,
    if (roomSceneIds != null) 'roomSceneIds': roomSceneIds,
    'swapPreviewTubes': swapPreviewTubes,
    'genericRoomPreview': genericRoomPreview,
  };
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final raw = json['slots'];
    final ids = raw is List
        ? raw
              .whereType<Map>()
              .map((item) => item['id'])
              .whereType<String>()
              .where((id) => DeviceSlot.defaults.any((s) => s.id == id))
              .toSet()
        : DeviceSlot.defaults.map((s) => s.id);
    final slots = ids.map((id) {
      final slot = DeviceSlot.defaults.singleWhere((s) => s.id == id);
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
          if (!scene.isCustom) continue;
          if (!scenes.any((s) => s.id == scene.id)) scenes.add(scene);
        } on FormatException {
          // A damaged scene must not discard the user's other preferences.
        }
      }
    }
    final presets = <LightScene>[];
    final rawPresets = json['presetScenes'];
    if (rawPresets is List) {
      for (final rawPreset in rawPresets) {
        try {
          if (rawPreset is! Map<String, dynamic>) continue;
          final preset = LightScene.fromJson(rawPreset);
          if (LightScene.presetIds.contains(preset.id) &&
              !presets.any((s) => s.id == preset.id)) {
            presets.add(preset);
          }
        } on FormatException {
          // A damaged override falls back to its original preset.
        }
      }
    }
    return AppSettings(
      customScenes: List.unmodifiable(scenes),
      presetScenes: List.unmodifiable(presets),
      deletedPresetIds: json['deletedPresetIds'] is List
          ? List.unmodifiable(
              (json['deletedPresetIds'] as List)
                  .whereType<String>()
                  .where(LightScene.presetIds.contains)
                  .toSet(),
            )
          : const [],
      swapPreviewTubes: json['swapPreviewTubes'] == true,
      // Keep the personal preview for existing installations; new installs
      // use the original generic illustration unless explicitly changed.
      genericRoomPreview: json['genericRoomPreview'] == true,
      roomSceneIds: json['roomSceneIds'] is List
          ? List.unmodifiable(
              (json['roomSceneIds'] as List)
                  .whereType<String>()
                  .where(
                    (id) =>
                        LightScene.defaults.any((s) => s.id == id) ||
                        RegExp(r'^custom-[a-zA-Z0-9-]{1,80}$').hasMatch(id),
                  )
                  .toSet()
                  .take(
                    LightScene.maxCustomScenes + LightScene.defaults.length,
                  ),
            )
          : null,
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
