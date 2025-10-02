// lib/core/wake_cell_status.dart
enum WakeCellStatus {
  noAlarm,         // 未設定
  waiting,         // 目標前/就寝中
  posted,          // 起床
  snoozing,        // スヌーズ
  lateSuspicious,  // 猶予超過/遅刻疑い
  due,             // 鳴動中
}