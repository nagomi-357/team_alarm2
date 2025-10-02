//models/models.dart（モデル共通）

class GroupSettings {
  final int graceMins;
  final int snoozeStepMins;
  final int snoozeWarnThreshold;
  const GroupSettings({required this.graceMins, required this.snoozeStepMins, required this.snoozeWarnThreshold});
  factory GroupSettings.fromMap(Map<String, dynamic>? m) {
    final s = (m?['settings'] as Map<String, dynamic>?) ?? m ?? {};
    return GroupSettings(
      graceMins: (s['graceMins'] as int?) ?? 10,
      snoozeStepMins: (s['snoozeStepMins'] as int?) ?? 5,
      snoozeWarnThreshold: (s['snoozeWarnThreshold'] as int?) ?? 2,
    );
  }
  Map<String, dynamic> toMap() => {'settings': {
    'graceMins': graceMins, 'snoozeStepMins': snoozeStepMins, 'snoozeWarnThreshold': snoozeWarnThreshold }};
}

