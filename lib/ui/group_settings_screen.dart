//group_settings_screen.dart（設定＋正確アラーム導線）

import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/group_repo.dart';
import '../models/group_settings.dart';
import '../android/exact_alarm.dart';

class GroupSettingsScreen extends StatefulWidget {
  final String groupId;
  const GroupSettingsScreen({super.key, required this.groupId});
  @override State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final _repo = GroupRepo();
  late int _graceMins; late int _snoozeStepMins; late int _snoozeWarnThreshold;
  bool _dirty = false; bool _checking = false; bool? _exactOk; bool _isAdmin = false;

  @override void initState() { super.initState(); _checkExactAlarm(); }
  Future<void> _checkExactAlarm() async {
    if (!Platform.isAndroid) { setState(() => _exactOk = true); return; }
    setState(() => _checking = true);
    final ok = await ExactAlarm.canSchedule();
    if (!mounted) return; setState(() { _exactOk = ok; _checking = false; });
  }
  Future<void> _openExactAlarmSettings() async { await ExactAlarm.openSettings(); await Future.delayed(const Duration(milliseconds: 500)); await _checkExactAlarm(); }

  @override
  Widget build(BuildContext context) {
    final groupDoc = FirebaseFirestore.instance.collection('groups').doc(widget.groupId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: groupDoc.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final settings = GroupSettings.fromMap(data);
        final admins = List<String>.from((data['admins'] as List?) ?? const []);
        // ★ 本番はFirebaseAuthでuidを取得して判定してください
        _isAdmin = admins.contains('user_a');

        _graceMins           = _dirty ? _graceMins           : settings.graceMins;
        _snoozeStepMins      = _dirty ? _snoozeStepMins      : settings.snoozeStepMins;
        _snoozeWarnThreshold = _dirty ? _snoozeWarnThreshold : settings.snoozeWarnThreshold;

        return Scaffold(
          appBar: AppBar(
            title: const Text('グループ設定'),
            actions: [
              TextButton(
                onPressed: _dirty && _isAdmin ? () async {
                  await _repo.updateGroupSettings(widget.groupId,
                      graceMins: _graceMins, snoozeStepMins: _snoozeStepMins, snoozeWarnThreshold: _snoozeWarnThreshold);
                  if (mounted) { setState(() => _dirty = false);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存しました'))); }
                } : null,
                child: const Text('保存', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (Platform.isAndroid) _ExactAlarmSection(
                  checking: _checking, ok: _exactOk,
                  onOpenSettings: _openExactAlarmSettings, onRecheck: _checkExactAlarm),
              const SizedBox(height: 12),
              Card(child: Padding(padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.admin_panel_settings), const SizedBox(width: 8), const Text('管理者'),
                    const Spacer(),
                    if (!_isAdmin) const Text('（閲覧のみ）', style: TextStyle(color: Colors.grey)),
                  ]),
                  const SizedBox(height: 8),
                  for (final m in List<String>.from((data['members'] as List?) ?? const []))
                    SwitchListTile(
                      title: Text(m, overflow: TextOverflow.ellipsis),
                      value: admins.contains(m),
                      onChanged: (!_isAdmin) ? null : (val) async {
                        if (!val && admins.length == 1 && admins.first == m) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('最後の管理者は外せません'))); return;
                        }
                        try {
                          if (val) await _repo.updateGroupSettings(widget.groupId); // no-op
                          await FirebaseFirestore.instance.collection('groups').doc(widget.groupId)
                              .update({'admins': val
                              ? FieldValue.arrayUnion([m])
                              : FieldValue.arrayRemove([m])});
                        } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失敗: $e'))); }
                      },
                    ),
                ]),
              )),
              const SizedBox(height: 12),
              _Section(
                title: '遅刻判定の猶予（分）',
                subtitle: 'アラーム時刻を過ぎてから何分間は「⚠️到来」扱いにするか',
                value: _graceMins, min: 0, max: 30, step: 1,
                onChanged: _isAdmin ? (v) => setState(() { _graceMins = v; _dirty = true; }) : null,
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'スヌーズ間隔（分）',
                subtitle: 'スヌーズを押したとき何分後に再通知するか',
                value: _snoozeStepMins, min: 1, max: 30, step: 1,
                onChanged: _isAdmin ? (v) => setState(() { _snoozeStepMins = v; _dirty = true; }) : null,
              ),
              const SizedBox(height: 12),
              _Section(
                title: '警告しきい値（スヌーズ回数）',
                subtitle: 'この回数以上でバッジを赤にして注意喚起',
                value: _snoozeWarnThreshold, min: 1, max: 10, step: 1,
                onChanged: _isAdmin ? (v) => setState(() { _snoozeWarnThreshold = v; _dirty = true; }) : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String title, subtitle; final int value, min, max, step; final ValueChanged<int>? onChanged;
  const _Section({super.key, required this.title, required this.subtitle, required this.value, required this.min, required this.max, required this.step, required this.onChanged});
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0.5,
    child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6), Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Slider(value: value.toDouble(), min: min.toDouble(), max: max.toDouble(),
          divisions: ((max - min) / step).round(), label: '$value',
          onChanged: onChanged == null ? null : (d) => onChanged!(d.round()),
        )),
        SizedBox(width: 64, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
      ]),
    ],
    )),
  );
}

class _ExactAlarmSection extends StatelessWidget {
  final bool checking; final bool? ok;
  final VoidCallback onOpenSettings, onRecheck;
  const _ExactAlarmSection({super.key, required this.checking, required this.ok, required this.onOpenSettings, required this.onRecheck});
  @override
  Widget build(BuildContext context) {
    final statusText = checking ? '確認中…' : (ok == true ? '許可されています（時間ぴったりに鳴ります）' : '未許可です（省電力中に遅れる可能性）');
    final statusColor = (ok == true) ? Colors.green.shade600 : Colors.orange.shade700;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.alarm, size: 20), const SizedBox(width: 8),
        const Text('正確なアラーム', style: TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        TextButton.icon(onPressed: checking ? null : onRecheck, icon: const Icon(Icons.refresh, size: 18), label: const Text('再チェック')),
      ]),
      const SizedBox(height: 8),
      Text('目覚ましを設定した時間ちょうどに通知を出すには、この端末で「正確なアラーム」の許可が必要です（Android 12以降）。',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 10),
      Row(children: [
        Icon(ok == true ? Icons.check_circle : Icons.warning_amber, color: statusColor, size: 18),
        const SizedBox(width: 6), Text(statusText, style: TextStyle(color: statusColor)),
      ]),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: (ok == true || checking) ? null : onOpenSettings,
          icon: const Icon(Icons.open_in_new), label: const Text('正確アラームの設定を開く')),
    ])));
  }
}
