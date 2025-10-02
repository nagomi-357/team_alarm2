//models/models.dart（モデル共通）

class GroupSettings {
  final int graceMins;
  final int snoozeStepMins;
  final int snoozeWarnThreshold;
  /// 毎日のデータをクリアするリセット時刻（ローカル時刻）
  final int resetHour;   // 0-23
  final int resetMinute; // 0-59

  const GroupSettings({
    required this.graceMins,
    required this.snoozeStepMins,
    required this.snoozeWarnThreshold,
    required this.resetHour,
    required this.resetMinute,
  });

  factory GroupSettings.fromMap(Map<String, dynamic> g) {
    final s = (g['settings'] as Map<String, dynamic>?) ?? {};
    return GroupSettings(
      graceMins: (s['graceMins'] as int?) ?? 10,
      snoozeStepMins: (s['snoozeStepMins'] as int?) ?? 5,
      snoozeWarnThreshold: (s['snoozeWarnThreshold'] as int?) ?? 2,
      // ↓ 新規: 既定は 04:00
      resetHour: (s['resetHour'] as int?) ?? 4,
      resetMinute: (s['resetMinute'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'settings': {
      'graceMins': graceMins,
      'snoozeStepMins': snoozeStepMins,
      'snoozeWarnThreshold': snoozeWarnThreshold,
      // ↓ 新規
      'resetHour': resetHour,
      'resetMinute': resetMinute,
    }
  };
}

