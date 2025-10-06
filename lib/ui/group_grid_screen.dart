//(必要)ui/group_grid_screen.dart（グリッド＋アラーム＋他人枠制限＋ボトムバー）
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../core/wake_logic.dart';
import '../models/models.dart';
import '../data/group_repo.dart';
import '../data/storage_repo.dart' as data_storage;
import '../data/timeline_repo.dart';
import '../ui/timeline_screen.dart';
import '../ui/pickers/image_pick.dart';
import '../notifications/notification_service.dart';
import 'invite/invite_screen.dart';
import '../data/user_repo.dart';
import 'group_settings_screen.dart';
import '../models/grid_post.dart';
import 'photo_gallery_screen.dart';
import 'dart:math' as math;
import 'sleep_lock_screen.dart';
import 'group_settings_screen.dart';
import 'package:team_alarm1_2/utils/gradients.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import '../data/calendar_repo.dart';
import '../models/group_summary.dart';
import '../models/group_calendar_event.dart';
import 'group_calendar_screen.dart';
import 'widgets/group_bottom_nav.dart';


enum _WakeChoice { wakeNow, reschedule }
enum _WakeChoicePhoto { photo, reschedule }
enum _DueAction { wake, snooze }


class GroupGridScreen extends StatefulWidget {
  final String groupId;
  final List<String> memberUids;
  final String myUid;
  final List<GroupSummary> availableGroups;
  const GroupGridScreen({
    super.key,
    required this.groupId,
    required this.memberUids,
    required this.myUid,
    required this.availableGroups,
  });
  @override State<GroupGridScreen> createState() => _GroupGridScreenState();
}

class _GroupGridScreenState extends State<GroupGridScreen> {
  final repo = GroupRepo();
  final store = data_storage.StorageRepo();
  final tl = TimelineRepo();
  final _calendarRepo = CalendarRepo();

  DateTime _now = DateTime.now();
  GroupSettings _settings = const GroupSettings(
      graceMins: 10,
      snoozeStepMins: 5,
      snoozeWarnThreshold: 2,
      resetHour: 4,
      resetMinute: 0,
  );
  bool _isAdmin = false;

  bool _autoResetChecked = false;
  Future<void> _maybeAutoReset() async {
    try {
      final did = await repo.ensureDailyResetIfNeeded(widget.groupId);
      if (did && mounted) {
        await tl.log(widget.groupId, {'type': 'autoReset'});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('日次リセットを実行しました')),
        );
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    if (!_autoResetChecked) {
      _autoResetChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoReset());
    }
    _syncNow();
  }

  Future<void> _syncNow() async {
    _now = await repo.serverNow();
    if (mounted) setState(() {});
  }


  Future<void> _pickTargetAndSchedule(BuildContext context,
      {DateTime? initial}) async {
    final now = DateTime.now();
    final initialTod = (initial != null)
        ? TimeOfDay(hour: initial.hour, minute: initial.minute)
        : TimeOfDay.fromDateTime(now);

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTod,
      helpText: '起床目標時間を選択',
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            timePickerTheme: const TimePickerThemeData(
              backgroundColor: Color(0xFF12171E),
              dialBackgroundColor: Color(0xFF0E1B2A),
              dialHandColor: Color(0xFF12D6DF),
              hourMinuteTextColor: Color(0xFFDBF7FF),
              dayPeriodTextColor: Color(0xFFBDEBFF),
              helpTextStyle: TextStyle(color: Color(0xFF9BE7FF), fontWeight: FontWeight.w600),
              entryModeIconColor: Color(0xFF9BE7FF),
              dialTextColor: Colors.white,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFBDEBFF)),
            ),
            dialogBackgroundColor: const Color(0xFF12171E),
            colorScheme: const ColorScheme.dark(
              surface: Color(0xFF12171E),
              primary: Color(0xFF12D6DF),
              onSurface: Color(0xFFDBF7FF),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;

    // 「今日」のその時刻を作る
    var candidate = DateTime(
        now.year, now.month, now.day, picked.hour, picked.minute);

    // いまより前の時刻を選んだ＝翌日に回す（ユーザーに確認）
    if (candidate.isBefore(now)) {
      final tomorrow = candidate.add(const Duration(days: 1));
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) =>
            AlertDialog(
              title: const Text('翌日として設定しますか？'),
              content: Text(
                  '選んだ時刻は現在時刻より前です。\n'
                      '起床目標を「${tomorrow.year}/${tomorrow.month}/${tomorrow
                      .day} ${picked.format(context)}」に設定します。'
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false),
                    child: const Text('キャンセル')),
                FilledButton(onPressed: () => Navigator.pop(context, true),
                    child: const Text('OK')),
              ],
            ),
      );
      if (ok != true) return;
      candidate = tomorrow;
    }

    // ここまで来たら candidate は「未来の日時」＝目標時刻
    await repo.setAlarmAt(
      groupId: widget.groupId,
      uid: widget.myUid,
      alarmAt: candidate,
    );
    // ★ Reset snooze flags on (re)setting target time
    try {
      await FirebaseFirestore.instance
          .collection('groups').doc(widget.groupId)
          .collection('todayAlarms').doc(widget.myUid)
          .set({'snoozing': false, 'snoozeCount': 0}, SetOptions(merge: true));
    } catch (_) {}

    // 通知を上書き
    final notifId = (widget.groupId.hashCode ^ widget.myUid.hashCode) & 0x7fffffff;
    await NotificationService.instance.cancel(notifId);
    await NotificationService.instance.scheduleAlarm(
      id: notifId,
      at: candidate,
      title: '起床時間です',
      body: 'おはようを投稿しましょう',
    );

    await tl.log(widget.groupId, {
      'type': 'set_alarm',
      'by': widget.myUid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    final label = TimeOfDay.fromDateTime(candidate).format(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('目標 $label で設定しました')),
    );
    // ★ ロックフラグON & 画面遷移
    await UserRepo().setSleepLocked(uid: widget.myUid, locked: true, groupId: widget.groupId);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SleepLockScreen(
          groupId: widget.groupId,
          myUid: widget.myUid,
          memberUids: widget.memberUids,
          settings: _settings,
        ),
      ),
    );
  }


  DateTime? _extractAlarmDateTime(TodayAlarm? alarm) {
    if (alarm == null) return null;
    try {
      final dynamic v = (alarm as dynamic).alarmAt ?? (alarm as dynamic).wakeAt;
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is Timestamp) return v.toDate();
    } catch (_) {}
    return null;
  }

Widget _buildTimelineScreen(NavigatorState navigator) {
  return TimelineScreen(groupId: widget.groupId);
}

  GroupCalendarScreen _buildCalendarScreen(NavigatorState navigator) {
    return GroupCalendarScreen(
      currentGroupId: widget.groupId,
      myUid: widget.myUid,
      availableGroups: widget.availableGroups,
      onOpenTimeline: () {
        navigator.popUntil((route) => route.settings.name == null || route.settings.name == 'grid');
        navigator.push(MaterialPageRoute(
          settings: const RouteSettings(name: 'timeline'),
          builder: (_) => _buildTimelineScreen(navigator),
        ));
      },
    );
  }

  void _openTimeline() {
    final navigator = Navigator.of(context);
    navigator.push(MaterialPageRoute(
      settings: const RouteSettings(name: 'timeline'),
      builder: (_) => _buildTimelineScreen(navigator),
    ));
  }

  void _openCalendar() {
    final navigator = Navigator.of(context);
    navigator.push(MaterialPageRoute(
      settings: const RouteSettings(name: 'calendar'),
      builder: (_) => _buildCalendarScreen(navigator),
    ));
  }



  @override
  Widget build(BuildContext context) {
    final gref = FirebaseFirestore.instance.collection('groups').doc(
        widget.groupId);
    final uref = FirebaseFirestore.instance.collection('users').doc(widget.myUid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: uref.snapshots(),
        builder: (context, usnap) {
          final ud = usnap.data?.data() ?? {};
          final locked = ud['sleepLocked'] == true;
          final lockGid = ud['sleepLockGroupId'] as String?;

          // ★ 自分がロック中 かつ このグループのロックなら即ロック画面を出す
          if (locked && lockGid == widget.groupId) {
            return SleepLockScreen(
              groupId: widget.groupId,
              myUid: widget.myUid,
              memberUids: widget.memberUids,
              settings: _settings,
            );
          }


          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: gref.snapshots(),
            builder: (context, gsnap) {
              final g = gsnap.data?.data() ?? {};
              _settings = GroupSettings.fromMap(g);
              final admins = List<String>.from(
                  (g['admins'] as List?) ?? const[]);
              _isAdmin = admins.contains(widget.myUid);
              final groupMap = {for (final g in widget.availableGroups) g.id: g};


              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0B0F12), Color(0xFF0E1B2A)],
                  ),
                ),
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(
                      g['name'] ?? 'グループ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    foregroundColor: Colors.white,
                    flexibleSpace: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF0B0F12), Color(0xFF0E1B2A)],
                        ),
                      ),
                    ),
                    actions: [
                      IconButton(
                          icon: const Icon(Icons.group_add), onPressed: () {
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) =>
                                InviteScreen(
                                    myUid: widget.myUid,
                                    groupId: widget.groupId)));
                      }),
                      IconButton(
                        icon: const Icon(Icons.settings),
                        onPressed: () async {
                          final updated = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  GroupSettingsScreen(
                                    groupId: widget.groupId,
                                    myUid: widget.myUid,
                                  ),
                            ),
                          );
                          if (updated == true && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('保存しました')),
                            );
                          }
                        },
                      ),


                      IconButton(icon: const Icon(Icons.refresh),
                          onPressed: _isAdmin ? () async {
                            final ok = await showDialog<bool>(
                                context: context, builder: (_) =>
                                AlertDialog(
                                  title: const Text('リセットしますか？'),
                                  content: const Text(
                                      '今日の投稿・アラーム・タイムラインをリセットします。'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('キャンセル')),
                                    FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('リセット')),
                                  ],
                                ));
                            if (ok == true) {
                              await repo.manualReset(widget.groupId);
                              await tl.log(widget.groupId,
                                  {'type': 'reset', 'by': widget.myUid});
                            }
                          } : null),

                      // ♪ 即時テスト（showNowTestはID固定の可能性があるので、1秒後のスケジュールで代用）
                      IconButton(
                        icon: const Icon(Icons.music_note),
                        tooltip: '即時テスト',
                        onPressed: () async {
                          final id = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
                          await NotificationService.instance.scheduleAfterSeconds(
                            id: id,
                            seconds: 1,
                          );
                        },
                      ),

// 🔔 5秒後アラームテスト（毎回ユニークID）
                      IconButton(
                        icon: const Icon(Icons.alarm_add),
                        tooltip: '5秒後にアラーム',
                        onPressed: () async {
                          final id = DateTime.now().millisecondsSinceEpoch & 0x7fffffff; // ユニーク
                          final at = DateTime.now().add(const Duration(seconds: 5));
                          await NotificationService.instance.scheduleAlarm(
                            id: id,
                            at: at,
                            title: 'テストアラーム',
                            body: '5秒後に鳴りました',
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('5秒後にアラームをセットしました')),
                            );
                          }
                        },
                      ),

// ⏹ アラーム取り消し（直前の固定IDが無いので、必要なら個別にIDを覚えてcancelしてください）
                      IconButton(
                        icon: const Icon(Icons.notifications_off),
                        tooltip: '（例）固定ID999の取消',
                        onPressed: () async {
                          await NotificationService.instance.cancel(999); // 例：固定IDを使っている箇所があれば消せます
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('テストアラームを取り消しました')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  backgroundColor: Colors.transparent,
                  body: _streams(),
                  bottomNavigationBar: BottomNavigationBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    selectedItemColor: Colors.white,
                    unselectedItemColor: Colors.white70,
                    items: const [
                      BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: ''),
                      BottomNavigationBarItem(icon: Icon(Icons.horizontal_split), label: ''),
                      BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: ''),
                    ],
                    currentIndex: 0,
                    onTap: (i) {
                      if (i == 1) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TimelineScreen(groupId: widget.groupId),
                          ),
                        );
                      } else if (i == 2) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GroupCalendarScreen(
                              currentGroupId: widget.groupId,
                              myUid: widget.myUid,
                              availableGroups: widget.availableGroups,
                              onOpenTimeline: () {},
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),

              );
            },

          );

        },
    );
  }

  Future<void> _handleRemovePhotoOnly() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('写真を取り下げますか？'),
        content: const Text('投稿済みの写真のみ削除します（起床状態や時刻は維持されます）。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除する')),
        ],
      ),
    );
    if (ok != true) return;

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      // 写真URLのみ null にする（post を残したまま画像だけ取り下げ）
      await repo.postOhayo(widget.groupId, widget.myUid, photoUrl: null);
      await tl.log(widget.groupId, {'type': 'remove_photo', 'uid': widget.myUid});
    } finally {
      if (mounted) Navigator.pop(context); // ローディング閉じる
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('写真を取り下げました')));
  }

  Widget _streams() {
    return StreamBuilder<Map<String, Map<String, dynamic>>>(
      stream: repo.todayAlarms(widget.groupId),
      builder: (_, as) {
        return StreamBuilder<Map<String, Map<String, dynamic>>>(
          stream: repo.gridPosts(widget.groupId),
          builder: (_, ps) {
            // ★ プロフィール購読（uids→Map<uid, profile>）
            return StreamBuilder<Map<String, Map<String, dynamic>>>(
              stream: UserRepo().profilesByUids(widget.memberUids),
              builder: (_, us) {
                final profiles = us.data ?? {};
                final alarms = as.data ?? {};
                final posts = ps.data ?? {};

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: (widget.memberUids.length <= 6) ? 2 : 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: widget.memberUids.length,
                  itemBuilder: (_, i) {
                    final uid = widget.memberUids[i];
                    final alarm = alarms[uid] != null
                        ? TodayAlarm.fromMap(
                            uid,
                            {
                              ...alarms[uid]!,
                              'graceMins': (alarms[uid]?['graceMins'] ?? _settings.graceMins),
                            },
                          )
                        : null;
                    final post = posts[uid] != null ? GridPost.fromMap(uid, posts[uid]!) : null;
                    final status = computeStatus(now: _now, alarm: alarm, post: post);
                    final isMe = uid == widget.myUid;

                    return _Cell(
                      uid: uid,
                      isMe: isMe,
                      status: status,
                      alarm: alarm,
                      post: post,
                      settings: _settings,
                      profile: profiles[uid],
                      onTap: () async {
                        final hasPhoto = post?.photoUrl != null;

                        if (hasPhoto) {
                          // 画像ポップアップ + ボタン群（縦並び、画像と重ならない）
                          await showDialog(
                            context: context,
                            barrierColor: Colors.black87,
                            builder: (dCtx) => Dialog(
                              backgroundColor: Colors.transparent,
                              insetPadding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 画像本体（拡大縮小可）
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: InteractiveViewer(
                                      child: AspectRatio(
                                        aspectRatio: 1,
                                        child: Image.network(post!.photoUrl!, fit: BoxFit.cover),
                                      ),
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(height: 12),
                                    // ボタン群（縦並び / 画面下部に配置、画像と重ならない）
                                    SafeArea(
                                      top: false,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: () async {
                                              Navigator.of(dCtx).pop(); // 先に閉じる
                                              await _handlePhotoFlow(post); // 再投稿
                                            },
                                            icon: const Icon(Icons.photo_camera_back),
                                            label: const Text('再投稿'),
                                          ),
                                          const SizedBox(height: 8),
                                          OutlinedButton.icon(
                                            onPressed: () async {
                                              Navigator.of(dCtx).pop(); // 先に閉じる
                                              await _handleRemovePhotoOnly(); // 写真削除（wakeAt等は維持）
                                            },
                                            icon: const Icon(Icons.hide_image),
                                            label: const Text('写真削除'),
                                          ),
                                          const SizedBox(height: 8),
                                          FilledButton.icon(
                                            onPressed: () async {
                                              Navigator.of(dCtx).pop(); // 先に閉じる
                                              final picked = await _pickAlarmAt(
                                                context,
                                                initial: _extractAlarmDateTime(alarm),
                                              );
                                              if (picked != null) {
                                                await _handleRescheduleFlow(picked);
                                                await UserRepo().setSleepLocked(
                                                  uid: widget.myUid,
                                                  locked: true,
                                                  groupId: widget.groupId,
                                                );
                                                if (!mounted) return;
                                                Navigator.of(context).pushReplacement(
                                                  MaterialPageRoute(
                                                    builder: (_) => SleepLockScreen(
                                                      groupId: widget.groupId,
                                                      myUid: widget.myUid,
                                                      memberUids: widget.memberUids,
                                                      settings: _settings,
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            icon: const Icon(Icons.schedule),
                                            label: const Text('起床時間を再設定'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                          return; // 画像があるケースはここで終了
                        }

                        // 画像がない場合は従来どおり
                        if (isMe) {
                          await _tapMe(alarm, post);
                        } else {
                          await _tapOther(uid, alarm, post, status);
                        }
                      },
                      onWake: (uid != widget.myUid && status == WakeCellStatus.lateSuspicious)
                          ? () => _wake(uid)
                          : null,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<DateTime?> _pickAlarmAt(BuildContext context,
      {DateTime? initial}) async {
    final now = DateTime.now();
    final base = initial ?? now;
    final initialTod = TimeOfDay.fromDateTime(base);

    final tod = await showTimePicker(
      context: context,
      initialTime: initialTod,
      helpText: '起床目標時間を設定',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: Theme(
          data: Theme.of(ctx).copyWith(
            timePickerTheme: const TimePickerThemeData(
              backgroundColor: Color(0xFF12171E),
              dialBackgroundColor: Color(0xFF0E1B2A),
              dialHandColor: Color(0xFF12D6DF),
              hourMinuteTextColor: Color(0xFFDBF7FF),
              dayPeriodTextColor: Color(0xFFBDEBFF),
              helpTextStyle: TextStyle(color: Color(0xFF9BE7FF), fontWeight: FontWeight.w600),
              entryModeIconColor: Color(0xFF9BE7FF),
              dialTextColor: Colors.white,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFBDEBFF)),
            ),
            dialogBackgroundColor: const Color(0xFF12171E),
            colorScheme: const ColorScheme.dark(
              surface: Color(0xFF12171E),
              primary: Color(0xFF12D6DF),
              onSurface: Color(0xFFDBF7FF),
            ),
          ),
          child: child!,
        ),
      ),
    );
    if (tod == null) return null;

    // 今日の日付で合成
    var candidate = DateTime(
        now.year, now.month, now.day, tod.hour, tod.minute);

    // すでに過去 → 翌日に回すか確認
    if (candidate.isBefore(now)) {
      final tomorrow = candidate.add(const Duration(days: 1));
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) =>
            AlertDialog(
              title: const Text('翌日として設定しますか？'),
              content: Text(
                      '起床目標を「${tomorrow.year}/${tomorrow
                      .month}/${tomorrow.day} '
                      '${tod.format(context)}」に設定します。'
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false),
                    child: const Text('キャンセル')),
                FilledButton(onPressed: () => Navigator.pop(context, true),
                    child: const Text('OK')),
              ],
            ),
      );
      if (ok != true) return null; // ユーザーが拒否したら中断
      candidate = tomorrow; // 承認なら翌日に繰り上げ
    }

    return candidate; // 未来の日時を返す（当日 or 翌日）
  }

  Future<void> _handleSnooze(TodayAlarm alarm) async {
    // 1) Firestore: スヌーズ回数 +1 / snoozing=true
    await repo.incrementSnooze(widget.groupId, widget.myUid, _settings.snoozeStepMins);

    // 2) ローカル通知: 現在 + スヌーズ間隔 で再スケジュール
    final nid = (widget.groupId.hashCode ^ widget.myUid.hashCode) & 0x7fffffff;
    final next = DateTime.now().add(Duration(minutes: _settings.snoozeStepMins));
    await NotificationService.instance.cancel(nid);
    await NotificationService.instance.scheduleAlarm(id: nid, at: next, title: 'スヌーズ', body: 'そろそろ起きる時間です');

    // 3) タイムライン
    await tl.log(widget.groupId, {'type': 'snooze', 'by': widget.myUid});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('スヌーズ: ${_settings.snoozeStepMins}分後に再通知します')),
    );
  }



  Future<void> _tapMe(TodayAlarm? alarm, GridPost? post) async {
    final hasAlarm = alarm?.alarmAt != null;
    final hasWake = alarm?.wakeAt != null;

    if (!hasAlarm) {
      // 未設定 → 目標時間の初回設定（時計ピッカー）
      await _pickTargetAndSchedule(context);
      return;
    }

    if (!hasWake) {
      final alarmAt = alarm?.alarmAt;
      final now = DateTime.now();
      final isDue = (alarmAt != null) && !now.isBefore(alarmAt); // alarmAt <= now

      if (isDue) {
        // ★ 鳴り始め：起床 or スヌーズ（再設定は不可）
        final act = await _showWakeOrSnoozeDialog(context);
        if (act == _DueAction.wake) {
          await _handleWakeNowFlow();
        } else if (act == _DueAction.snooze && alarm != null) {
          await _handleSnooze(alarm);
        }
      } else {
        // ★ アラーム前：起床 or 再設定（従来）
        final choice = await _showWakeOrRescheduleDialog(context);
        if (choice == _WakeChoice.wakeNow) {
          await _handleWakeNowFlow();
        } else if (choice == _WakeChoice.reschedule) {
          await _pickTargetAndSchedule(context, initial: _extractAlarmDateTime(alarm));
        }
      }
      return;
    }


    // ★ 起床済み → 写真投稿/更新 or 目標時間再設定
    final photoChoice = await _showPhotoOrRescheduleDialog(
      context,
      hasPhoto: post?.photoUrl != null,
    );
    if (photoChoice == _WakeChoicePhoto.photo) {
      await _handlePhotoFlow(post); // 写真投稿/更新
    } else if (photoChoice == _WakeChoicePhoto.reschedule) {
      // ⬇︎ ここを変更：picker → _handleRescheduleFlow
      final picked = await _pickAlarmAt(
          context, initial: _extractAlarmDateTime(alarm));
      if (picked != null) {
        await _handleRescheduleFlow(picked); // ★ wakeAt クリア + 投稿削除 まで実施
        // ★ 再設定後もスリープロックへ遷移（起床状態でも同様）
        await UserRepo().setSleepLocked(uid: widget.myUid, locked: true, groupId: widget.groupId);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SleepLockScreen(
              groupId: widget.groupId,
              myUid: widget.myUid,
              memberUids: widget.memberUids,
              settings: _settings,
            ),
          ),
        );
      }
    }
  }

  Future<_DueAction?> _showWakeOrSnoozeDialog(BuildContext context) {
    return showDialog<_DueAction>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('アラーム中'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _DueAction.wake),
                child: const Text('起床する'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, _DueAction.snooze),
                child: Text('スヌーズ（${_settings.snoozeStepMins}分）'),
              ),
            ),
          ],
        ),
      ),
    );
  }

    Future<_WakeChoice?> _showWakeOrRescheduleDialog(BuildContext context) {
      return showDialog<_WakeChoice>(
        context: context,
        builder: (_) =>
            AlertDialog(
              title: const Text('どうしますか？'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, _WakeChoice.wakeNow),
                      child: const Text('起床する'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () =>
                          Navigator.pop(context, _WakeChoice.reschedule),
                      child: const Text(
                        '起床目標時間を再設定する',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      );
    }


    Future<void> _handleRescheduleFlow(DateTime newAlarmAt) async {
      // 1) 目標（alarmAt）を更新
      await repo.setAlarmAt(
        groupId: widget.groupId,
        uid: widget.myUid,
        alarmAt: newAlarmAt,
      );
      // ★ Reset snooze flags when rescheduling
      try {
        await FirebaseFirestore.instance
            .collection('groups').doc(widget.groupId)
            .collection('todayAlarms').doc(widget.myUid)
            .set({'snoozing': false, 'snoozeCount': 0}, SetOptions(merge: true));
      } catch (_) {}

      // 2) 起床状態を解除：wakeAt と投稿を削除（写真もストレージから削除）
      await repo.clearWakeAndPost(
        groupId: widget.groupId,
        uid: widget.myUid,
      );

      // 3) タイムラインに記録（既存仕様どおり）
      await tl.log(widget.groupId, {
        'type': 'set_alarm',
        'by': widget.myUid,
        'at': DateFormat('HH:mm').format(newAlarmAt),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('目標 ${DateFormat('HH:mm').format(
            newAlarmAt)} に再設定しました（投稿・起床時刻をリセット）')),
      );

      final notifId = (widget.groupId.hashCode ^ widget.myUid.hashCode) & 0x7fffffff;
      await NotificationService.instance.cancel(notifId);
      await NotificationService.instance.scheduleAlarm(
        id: notifId,
        at: newAlarmAt,
        title: '起床時間です',
        body: 'おはようを投稿しましょう',
      );
    }


    Future<Map<String, Map<String, dynamic>>> _fetchProfiles(
        List<String> uids) async {
      final snapshots = await Future.wait(
        uids.map((uid) =>
            FirebaseFirestore.instance.collection('users').doc(uid).get()
        ),
      );

      final map = <String, Map<String, dynamic>>{};
      for (final snap in snapshots) {
        if (snap.exists) {
          map[snap.id] = snap.data()!;
        }
      }
      return map;
    }


    Future<void> _tapOther(String uid, TodayAlarm? alarm, GridPost? post,
        WakeCellStatus status) async {
      // 他人枠は、起床目標時刻（alarmAt）前は応援/起こす不可
      final alarmAt = alarm?.alarmAt;
      if (alarmAt != null && DateTime.now().isBefore(alarmAt)) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('起床目標時刻までは操作できません')));
        return;
      }
      if (status == WakeCellStatus.lateSuspicious) {
        final ok = await showDialog<bool>(context: context, builder: (_) =>
            AlertDialog(
              title: const Text('起こしますか？'),
              content: const Text('相手に通知を送ります'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false),
                    child: const Text('キャンセル')),
                FilledButton(onPressed: () => Navigator.pop(context, true),
                    child: const Text('起こす'))
              ],
            ));
        if (ok == true) _wake(uid);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('エールを送りました！')));
        await tl.log(
            widget.groupId, {'type': 'cheer', 'from': widget.myUid, 'to': uid});
      }
    }

    Future<_WakeChoicePhoto?> _showPhotoOrRescheduleDialog(BuildContext context,
        {
          required bool hasPhoto,
        }) {
      return showDialog<_WakeChoicePhoto>(
        context: context,
        builder: (_) =>
            AlertDialog(
              title: const Text('どうしますか？'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, _WakeChoicePhoto.photo),
                      child: Text(
                          hasPhoto ? '写真を更新する' : '写真を投稿する'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () =>
                          Navigator.pop(context, _WakeChoicePhoto.reschedule),
                      child: const Text('起床目標時間を再設定する',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
      );
    }


    Future<void> _handleWakeNowFlow() async {
      // おはよう（投稿）→ wakeAt=Now
      await repo.postOhayo(widget.groupId, widget.myUid);
      await repo.setWakeAt(
        groupId: widget.groupId,
        uid: widget.myUid,
        wakeAt: DateTime.now(),
      );
      // ★ Reset snooze flags on wake
      try {
        await FirebaseFirestore.instance
            .collection('groups').doc(widget.groupId)
            .collection('todayAlarms').doc(widget.myUid)
            .set({'snoozing': false, 'snoozeCount': 0}, SetOptions(merge: true));
      } catch (_) {}
// ← 位置引数版

      await tl.log(widget.groupId, {'type': 'wake', 'uid': widget.myUid});

      // 写真を添付するか聞く
      final add = await showDialog<bool>(
        context: context,
        builder: (_) =>
            AlertDialog(
              title: const Text('写真を添付しますか？'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('しない')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('する')),
              ],
            ),
      );

      if (add == true) {
        final which = await showModalBottomSheet<String>(
          context: context,
          builder: (_) =>
              SafeArea(
                child: Wrap(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.photo),
                      title: const Text('ギャラリー'),
                      onTap: () => Navigator.pop(context, 'gallery'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.camera),
                      title: const Text('カメラ'),
                      onTap: () => Navigator.pop(context, 'camera'),
                    ),
                  ],
                ),
              ),
        );

        final file = which == 'gallery'
            ? await ImagePick.pickFromGallery()
            : (which == 'camera'
            ? await ImagePick.pickFromCamera()
            : null);

        if (file != null) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: CircularProgressIndicator()),
          );
          try {
            final url = await store.uploadGroupPhoto(
              groupId: widget.groupId,
              uid: widget.myUid,
              file: file,
            );
            await repo.postOhayo(widget.groupId, widget.myUid, photoUrl: url);
            await tl.log(
                widget.groupId, {'type': 'photo', 'uid': widget.myUid});
          } finally {
            if (mounted) Navigator.pop(context);
          }
        }
      }

      // アラーム通知を停止（起きたので）
      final nid = (widget.myUid.hashCode ^ widget.groupId.hashCode) & 0x7fffffff;
      await NotificationService.instance.cancel(nid);

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(
          const SnackBar(content: Text('おはよう！起床を記録しました')));
    }


    Future<void> _wake(String uid) async {
      // MVP: ここではタイムラインに記録、実際のFCM通知は Functions で（後日）
      await tl.log(
          widget.groupId, {'type': 'nudge', 'from': widget.myUid, 'to': uid});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📣 $uid に起こすを送りました')));
    }

    Future<void> _handlePhotoFlow(GridPost? post) async {
      bool proceed = true;

      // 既に写真あり → 更新確認
      if (post?.photoUrl != null) {
        proceed = await showDialog<bool>(
          context: context,
          builder: (_) =>
              AlertDialog(
                title: const Text('写真を更新しますか？'),
                content: const Text('既存の写真を上書きします。よろしいですか？'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('キャンセル')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('更新する')),
                ],
              ),
        ) ??
            false;
      }
      if (!proceed) return;

      // 画像選択
      final which = await showModalBottomSheet<String>(
        context: context,
        builder: (_) =>
            SafeArea(
              child: Wrap(children: [
                ListTile(
                    leading: const Icon(Icons.photo),
                    title: const Text('ギャラリー'),
                    onTap: () => Navigator.pop(context, 'gallery')),
                ListTile(
                    leading: const Icon(Icons.camera),
                    title: const Text('カメラ'),
                    onTap: () => Navigator.pop(context, 'camera')),
              ]),
            ),
      );

      final file = which == 'gallery'
          ? await ImagePick.pickFromGallery()
          : (which == 'camera' ? await ImagePick.pickFromCamera() : null);
      if (file == null) return;

      // アップロード → post を保存（photoUrl上書き）
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      try {
        final url = await store.uploadGroupPhoto(
          groupId: widget.groupId,
          uid: widget.myUid,
          file: file,
        );

        // ★ 写真URLを Firestore に保存（post 上書き）
        await repo.postOhayo(widget.groupId, widget.myUid, photoUrl: url);
        await tl.log(widget.groupId, {'type': 'photo', 'uid': widget.myUid});
      } finally {
        if (mounted) Navigator.pop(context); // ローディング閉じる
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(post?.photoUrl == null
            ? '写真を投稿しました'
            : '写真を更新しました')),
      );
    }
  }



class _Cell extends StatefulWidget {
  final String uid;
  final bool isMe;
  final WakeCellStatus status;
  final TodayAlarm? alarm;
  final GridPost? post;
  final GroupSettings settings;
  final Map<String, dynamic>? profile;
  final VoidCallback onTap;
  final VoidCallback? onWake;

  const _Cell({
    super.key,
    required this.uid,
    required this.isMe,
    required this.status,
    required this.alarm,
    required this.post,
    required this.settings,
    required this.onTap,
    this.onWake,
    this.profile,
  });

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        final displayName = (widget.profile?['displayName'] as String?) ?? widget.uid;
        final userIconUrl = widget.profile?['photoUrl'] as String?;
        final photoUrl = widget.post?.photoUrl;

        // snoozeCount を安全に抽出
        int snoozeCount = 0;
        try {
          final sc = (widget.alarm as dynamic).snoozeCount;
          if (sc is int) snoozeCount = sc;
        } catch (_) {}

        final status = widget.status;
        final isDue  = status == WakeCellStatus.due;             // アラーム鳴動中
        final isLate = status == WakeCellStatus.lateSuspicious;  // 遅刻扱い

        // ハロー点滅は鳴動中のみ、サイズ脈動は「鳴動中 or 遅刻」
        final bool haloPulsing   = isDue;              // 枠のふわっと
        final bool scalePulsing  = isDue || isLate;    // タイルの拡大縮小（ご要望）

        // ② 周波数係数で速さを変える
        final double freq = isDue ? 1.5 : isLate ? 1.0 : 0.0; // 鳴動中は速め
        final double pulse = (freq > 0)
            ? (0.5 + 0.5 * math.sin(2 * math.pi * _pulseCtrl.value * freq))
            : 0.0;
        final bool isPulsing = haloPulsing || scalePulsing;

        final statusIcon = switch (status) {
          WakeCellStatus.noAlarm        => const Icon(Icons.timer_off,         color: Colors.white, size: 30),
          WakeCellStatus.waiting        => const Icon(Icons.hourglass_bottom,  color: Colors.white, size: 30),
          WakeCellStatus.due            => const Icon(Icons.warning_amber,     color: Colors.white, size: 30),
          WakeCellStatus.lateSuspicious => const Icon(Icons.priority_high,     color: Colors.white, size: 30),
          WakeCellStatus.snoozing       => const Icon(Icons.snooze,            color: Colors.white, size: 30),
          WakeCellStatus.posted         => const Icon(Icons.check_circle,      color: Colors.white, size: 30),
        };

        final accent = switch (status) {
          // 目標時間未設定 → 灰
          WakeCellStatus.noAlarm        => const Color(0xFF737B87),
          // 目標時間設定(目標前) → 青
          WakeCellStatus.waiting        => const Color(0xFF5BA7FF),
          // 鳴動中（仕様外だが既存維持）→ アンバー系（枠のふわっと演出に使用）
          WakeCellStatus.due            => const Color(0xFFFFC63A),
          // 遅刻猶予以降 → 赤
          WakeCellStatus.lateSuspicious => const Color(0xFFFF6B6B),
          // スヌーズ中 → 黄
          WakeCellStatus.snoozing       => const Color(0xFFFFC63A),
          // 起床後 → 緑
          WakeCellStatus.posted         => const Color(0xFF7EE2A8),
        };

        // --- Tint controls (濃淡の調整) ---
        const base = Color(0xFF12171E); // ダーク基調
        // ステータス別のベース濃度（0.0=透明, 1.0=不透明）
        final Map<WakeCellStatus, double> _strengthByStatus = const {
          WakeCellStatus.noAlarm:        0.70,
          WakeCellStatus.waiting:        0.70,
          WakeCellStatus.due:            0.70,
          WakeCellStatus.lateSuspicious: 0.70,
          WakeCellStatus.snoozing:       0.70,
          WakeCellStatus.posted:         0.70,
        };
        // 現状の脈動を濃淡に反映したい場合は下の + を活かす（不要なら + 部分を 0 に）
        final double _pulseBoost = ((haloPulsing || scalePulsing) && (widget.post?.photoUrl == null))
            ? (isDue ? 0.12 : 0.08) * pulse
            : 0.0;
        final double _strength = (_strengthByStatus[status] ?? 0.18) + _pulseBoost;
        final Color? tileColor = (photoUrl == null)
            ? Color.alphaBlend(accent.withOpacity(_strength.clamp(0.0, 1.0)), base)
            : null;

        final alarmText = widget.alarm?.alarmAt != null
            ? DateFormat('HH:mm').format(widget.alarm!.alarmAt!)
            : '--:--';
        final wakeText = widget.alarm?.wakeAt != null
            ? DateFormat('HH:mm').format(widget.alarm!.wakeAt!)
            : null;

        // 脈動スケール（鳴動/遅刻で大きく/小さく）
        final double amp = isDue ? 0.06 : 0.04; // 鳴動は少し大きめに揺らす
        final scale = 1.0 + (scalePulsing ? amp * pulse : 0.0);

        return InkWell(
          onTap: widget.onTap,
          child: Transform.scale(
            scale: scale,
            child: Container(
              decoration: BoxDecoration(
                gradient: (photoUrl == null)
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: getGradientColors(status),
                      )
                    : null,
                borderRadius: BorderRadius.circular(32),
                // border removed
                boxShadow: photoUrl == null
                    ? [
                        BoxShadow(
                          color: accent.withOpacity(0.18 + (isPulsing ? 0.12 * pulse : 0.0)),
                          blurRadius: 12 + (isPulsing ? 6 * pulse : 0.0),
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
                image: photoUrl != null
                    ? DecorationImage(
                        image: NetworkImage(photoUrl!),
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                      )
                    : null,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(32),
                ),
                padding: const EdgeInsets.all(8),
                child: Stack(
                  children: [
                    // ★ 鳴動中のみ：枠をふわっと発光させるハロー
                    if (haloPulsing)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(32),
                              // ふわっと変化する枠線
                              border: Border.all(
                                color: accent.withOpacity(0.55 + 0.35 * pulse),
                                width: 2.0 + 1.0 * pulse,
                              ),
                              // 外側へ柔らかく滲むグロー
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withOpacity(0.35 * (0.5 + 0.5 * pulse)),
                                  blurRadius: 24 + 12 * pulse,
                                  spreadRadius: 2 + 2 * pulse,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // 写真ありタイルにもアクセント色の薄いオーバーレイ（鳴動/遅刻は強めに脈動）
                    if (photoUrl != null && isPulsing)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: accent.withOpacity((isDue ? 0.16 : 0.08) * pulse),
                            borderRadius: BorderRadius.circular(32),
                          ),
                        ),
                      ),

                    // 上段：アイコン＋名前（位置を固定・上下ずれを解消）
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: accent, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withOpacity(0.35),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 18,
                              backgroundImage: userIconUrl != null ? NetworkImage(userIconUrl) : null,
                              child: userIconUrl == null ? const Icon(Icons.person, size: 20) : null,
                            ),
                          ),
                          const SizedBox(width: 6),
                          // ユーザーネームはアバターと同じ高さ枠で中央寄せ（上下ずれ防止）
                          if (photoUrl != null)
                            Flexible(
                              fit: FlexFit.loose,
                              child: SizedBox(
                                height: 40,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: BlurredText(
                                    displayName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: SizedBox(
                                height: 40,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // 中央：ステータス＋時刻
                    Align(
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          statusIcon,
                          const SizedBox(height: 6),
                          photoUrl != null
                              ? BlurredText(
                                  '目標 $alarmText',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  '目標 $alarmText',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                          if (wakeText != null)
                            (photoUrl != null
                                ? BlurredText(
                                    '起床 $wakeText',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    '起床 $wakeText',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  )),
                        ],
                      ),
                    ),

                    // 右上：スヌーズバッジ（snoozing中のみ表示）
                    if (snoozeCount > 0 && status == WakeCellStatus.snoozing)
                      Positioned(top: 6, right: 6, child: _Badge(text: '😴×$snoozeCount')),

                    // 右下：起こすボタン（遅刻疑い時のみ）
                    if (status == WakeCellStatus.lateSuspicious && widget.onWake != null)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: FloatingActionButton.small(
                          heroTag: null,
                          backgroundColor: const Color(0xFF173248),
                          foregroundColor: const Color(0xFFDBF7FF),
                          elevation: 0,
                          onPressed: widget.onWake,
                          child: const Icon(Icons.notifications_active),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class BlurredText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const BlurredText(
    this.text, {
    super.key,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          color: Colors.black.withOpacity(0.02), // 薄めの背景
          child: Row(
            mainAxisSize: MainAxisSize.min, // テキスト長に合わせる
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  text,
                  style: style,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFF173248),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0xFF3D90A1), width: 1),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFFDBF7FF),
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
    ),
  );
}


