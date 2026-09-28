class DeviceSlot {
  const DeviceSlot({required this.id, required this.name, this.entityId});
  final String id;
  final String name;
  final String? entityId;
  DeviceSlot copyWith({String? name, String? entityId}) => DeviceSlot(
    id: id,
    name: name ?? this.name,
    entityId: entityId ?? this.entityId,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'entityId': entityId,
  };

  static const defaults = [
    DeviceSlot(id: 'tube1', name: 'Wipro Tube 1'),
    DeviceSlot(id: 'tube2', name: 'Wipro Tube 2'),
    DeviceSlot(id: 'strip', name: 'Tapo Strip'),
  ];
  static const demo = [
    DeviceSlot(
      id: 'tube1',
      name: 'Wipro Tube 1',
      entityId: 'light.wipro_tube_1',
    ),
    DeviceSlot(
      id: 'tube2',
      name: 'Wipro Tube 2',
      entityId: 'light.wipro_tube_2',
    ),
    DeviceSlot(id: 'strip', name: 'Tapo Strip', entityId: 'light.tapo_strip'),
  ];

  static String? validate(List<DeviceSlot> slots) {
    if (slots.length != 3 ||
        slots
            .map((s) => s.id)
            .toSet()
            .difference(defaults.map((s) => s.id).toSet())
            .isNotEmpty ||
        slots.map((s) => s.id).toSet().length != 3) {
      return 'Map all three device slots.';
    }
    if (slots.any((s) => s.name.trim().isEmpty)) {
      return 'Give every device a name.';
    }
    if (slots.any(
      (s) => !RegExp(r'^light\.[a-z0-9_]+$').hasMatch(s.entityId ?? ''),
    )) {
      return 'Select a light entity for each device.';
    }
    if (slots.map((s) => s.entityId).toSet().length != slots.length) {
      return 'Each slot must use a different light entity.';
    }
    return null;
  }
}
