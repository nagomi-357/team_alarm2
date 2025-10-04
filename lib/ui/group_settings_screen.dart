import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/group_repo.dart';
import '../data/storage_repo.dart';
import 'pickers/image_pick.dart';
// Android の正確なアラーム設定カードを使う場合は有効化
import '../android/exact_alarm.dart';

class GroupSettingsScreen extends StatefulWidget {
  final String groupId;
  final String myUid;
  const GroupSettingsScreen({super.key, required this.groupId, required this.myUid});

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final _repo = GroupRepo();
  final _store = StorageRepo();

  final _nameCtl = TextEditingController();
  File? _iconFile;        // 変更中のローカル画像
  String? _avatarUrl;     // 表示用の現行URL
  bool _saving = false;
  bool _dirty = false;

  // 設定値
  int _grace = 10;
  int _snooze = 5;
  int _warn = 2;

  // デイリーリセット時刻（ローカル時刻）
  int _resetHour = 4;   // 0-23
  int _resetMinute = 0; // 0-59

  // Android: 正確なアラーム許可の確認（任意）
  bool? _exactOk;
  bool _checkingExact = false;

  @override
  void initState() {
    super.initState();
    _checkExact(); // Androidだけ意味あり
  }

  Future<void> _checkExact() async {
    if (!Platform.isAndroid) {
      setState(() => _exactOk = true);
      return;
    }
    setState(() => _checkingExact = true);
    final ok = await ExactAlarm.canSchedule(); // 実装がないなら一旦 true を返すダミーでもOK
    if (!mounted) return;
    setState(() {
      _exactOk = ok;
      _checkingExact = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('groups').doc(widget.groupId).snapshots(),
      builder: (context, snap) {
        final g = snap.data?.data() ?? {};

        // ★ 管理者判定（この画面の myUid から）
        final admins = List<String>.from((g['admins'] as List?) ?? const []);
        final bool isAdmin = admins.contains(widget.myUid);

        // 現在値の反映
        final curName = (g['name'] as String?) ?? '';
        final curAvatar = g['avatar'] as String?;
        final curGrace = (g['settings']?['graceMins'] as int?) ?? _grace;
        final curSnooze = (g['settings']?['snoozeStepMins'] as int?) ?? _snooze;
        final curWarn = (g['settings']?['snoozeWarnThreshold'] as int?) ?? _warn;
        final curResetH = (g['settings']?['resetHour'] as int?) ?? _resetHour;
        final curResetM = (g['settings']?['resetMinute'] as int?) ?? _resetMinute;

        if (_nameCtl.text.isEmpty && !_dirty) _nameCtl.text = curName;
        _avatarUrl ??= curAvatar;
        if (!_dirty) {
          _grace = curGrace;
          _snooze = curSnooze;
          _warn = curWarn;
          _resetHour = curResetH;
          _resetMinute = curResetM;
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.blueGrey.shade800,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            title: const Text('グループ設定'),
            actions: [
              TextButton(
                onPressed: (isAdmin && _dirty && !_saving) ? _save : null,
                child: const Text(
                  '保存',
                  style: TextStyle(color: Colors.white), // AppBar 上でも見えるように白文字
                ),
              ),
            ],
          ),
          backgroundColor: Colors.brown.shade300,
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // アイコン + グループ名
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: isAdmin ? () async {
                          final f = await ImagePick.pickFromGallery();
                          if (f != null) {
                            setState(() {
                              _iconFile = f;
                              _dirty = true;
                            });
                          }
                        } : null,
                        child: CircleAvatar(
                          radius: 28,
                          backgroundImage: _iconFile != null
                              ? FileImage(_iconFile!)
                              : (_avatarUrl != null
                              ? NetworkImage(_avatarUrl!) as ImageProvider
                              : null),
                          child: (_iconFile == null && _avatarUrl == null)
                              ? const Icon(Icons.group, size: 28)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _nameCtl,
                          enabled: isAdmin,
                          decoration: const InputDecoration(labelText: 'グループ名'),
                          onChanged: (_) { setState(() { _dirty = true; }); },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Android の正確なアラーム（任意）
              if (Platform.isAndroid)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.alarm),
                    title: const Text('正確なアラーム'),
                    subtitle: Text(
                      _checkingExact
                          ? '確認中…'
                          : (_exactOk == true ? '許可されています' : '未許可（遅れる可能性）'),
                    ),
                    trailing: TextButton(
                      onPressed: _checkingExact ? null : () async {
                        await ExactAlarm.openSettings();
                        await _checkExact();
                      },
                      child: const Text('設定を開く'),
                    ),
                  ),
                ),

              const SizedBox(height: 12),
              _slider(
                title: '遅刻猶予（分）',
                value: _grace,
                min: 0,
                max: 30,
                onChanged: isAdmin ? (v) { setState(() { _grace = v; _dirty = true; }); } : null,
              ),
              _slider(
                title: 'スヌーズ間隔（分）',
                value: _snooze,
                min: 1,
                max: 30,
                onChanged: isAdmin ? (v) { setState(() { _snooze = v; _dirty = true; }); } : null,
              ),
              _slider(
                title: '警告しきい値（スヌーズ回）',
                value: _warn,
                min: 1,
                max: 10,
                onChanged: isAdmin ? (v) { setState(() { _warn = v; _dirty = true; }); } : null,
              ),

              // デイリーリセット時刻
              Card(
                child: ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('デイリーリセット時刻'),
                  subtitle: const Text('この時刻にグリッド（目標・起床・投稿）とタイムライン・アラームを初期化'),
                  trailing: Text('${_resetHour.toString().padLeft(2, '0')}:${_resetMinute.toString().padLeft(2, '0')}'),
                  onTap: isAdmin ? () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: _resetHour, minute: _resetMinute),
                      helpText: 'リセット時刻を選択',
                    );
                    if (picked != null && mounted) {
                      setState(() {
                        _resetHour = picked.hour;
                        _resetMinute = picked.minute;
                        _dirty = true;
                      });
                    }
                  } : null,
                ),
              ),
              const SizedBox(height: 12),

              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _slider({
    required String title,
    required int value,
    required int min,
    required int max,
    ValueChanged<int>? onChanged,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: value.toDouble(),
                    min: min.toDouble(),
                    max: max.toDouble(),
                    divisions: max - min,
                    label: '$value',
                    onChanged: onChanged == null ? null : (d) => onChanged(d.round()),
                  ),
                ),
                SizedBox(width: 56, child: Text('$value', textAlign: TextAlign.center)),
              ],
            ),
          ],
        ),
      ),
    );
  }



  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      String? url = _avatarUrl;
      if (_iconFile != null) {
        url = await _store.uploadGroupIcon(groupId: widget.groupId, file: _iconFile!);
      }

      // 基本情報（name / avatar）
      await _repo.updateGroupBasics(
        widget.groupId,
        name: _nameCtl.text.trim().isEmpty ? null : _nameCtl.text.trim(),
        avatarUrl: url,
      );

      // 設定（猶予・スヌーズ等）
      await _repo.updateSettings(
        widget.groupId,
        graceMins: _grace,
        snoozeStepMins: _snooze,
        snoozeWarnThreshold: _warn,
        resetHour: _resetHour,
        resetMinute: _resetMinute,
      );

      if (!mounted) return;
      setState(() {
        _dirty = false;
        _avatarUrl = url;
        _iconFile = null;
      });

      // 前画面（グリッド）に「更新あり」を返して戻る
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
