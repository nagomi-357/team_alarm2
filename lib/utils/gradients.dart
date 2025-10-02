import 'package:flutter/material.dart';
import 'package:team_alarm1_2/core/wake_cell_status.dart'; // enum WakeCellStatus をここで import

/// 状態ごとのグラデーション色を返す関数
List<Color> getGradientColors(WakeCellStatus status) {
  switch (status) {
    case WakeCellStatus.noAlarm: // 未設定（グレー）
      return [Color(0xFF9E9E9E), Color(0xFF424242)];
    case WakeCellStatus.waiting: // 就寝中（青系）
      return [Color(0xFF42A5F5), Color(0xFF1E3A8A)];
    case WakeCellStatus.posted: // 起床（緑系）
      return [Color(0xFF66BB6A), Color(0xFF00897B)];
    case WakeCellStatus.snoozing: // スヌーズ（黄系）
      return [Color(0xFFFFEB3B), Color(0xFFF57C00)];
    case WakeCellStatus.lateSuspicious: // 猶予超過（赤系）
      return [Color(0xFFEF5350), Color(0xFF8E24AA)];
    case WakeCellStatus.due: // 鳴動中（アンバー系）
      return [Color(0xFFFFB300), Color(0xFFD32F2F)];
  }
  return [Color(0xFF9E9E9E), Color(0xFF424242)]; // fallback (未設定と同じ)
}