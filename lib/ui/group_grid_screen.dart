//group_grid_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/wake_status.dart';
import '../data/group_repo.dart';
import '../data/storage_repo.dart';
import '../ui/pickers/image_pick.dart';
import '../models/group_settings.dart';
import '../notifications/notification_service.dart';
import 'group_settings_screen.dart';

class GroupGridScreen extends StatefulWidget {
  final String groupId;
  final List<String> memberUids;
  final String myUid;
  const GroupGridScreen({super.key, required this.groupId, required this.memberUids, required this.myUid});
  @override State<GroupGridScreen> createState() => _GroupGridScreenState();
}

class _GroupGridScreenState extends State<GroupGridScreen> {
  final repo = GroupRepo();
  final store = StorageRepo();
  DateTime _now = DateTime.now();
  bool _isAdmin = false;
  GroupSettings _settings = const GroupSettings(graceMins: 10, snoozeStepMins: 5, snoozeWarnThreshold: 2);

  @override
  void initState() { super.initState(); _syncNow(); }
  Future<void> _syncNow() async { _now = await repo.serverNow(); if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final groupRef = FirebaseFirestore.instance.collection('groups').doc(widget.groupId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: groupRef.snapshots(),
      builder: (context, gsnap) {
        final data = gsnap.data?.data() ?? {};
        final admins = List<String>.from((data['admins'] as List?) ?? const []);
        _isAdmin = admins.contains(widget.myUid);
        _settings = GroupSettings.fromMap(data);

        return Scaffold(
          appBar: AppBar(
            title: Text(data['name'] ?? 'グループ'),
            actions: [
              IconButton(
                icon: const Icon(Icons.alarm_add),
                tooltip: 'アラーム設定',
                onPressed: _setAlarm,
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () async {
                  // 設定画面へ
                  await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => GroupSettingsScreen(groupId: widget.groupId),
                  ));
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: _isAdmin ? 'リセット' : '管理者のみ',
                onPressed: _isAdmin ? () => repo.manualReset(widget.groupId) : null,
              ),
            ],
          ),
          body: _buildStreams(),
          bottomNavigationBar: BottomAppBar(
            child: Row(
              children: [
                const SizedBox(width: 12),
                Text('残り時間表示は任意（gridExpiresAt から計算）', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStreams() {
    return StreamBuilder<Map<String, Map<String, dynamic>>>(
      stream: repo.todayAlarmsStream(widget.groupId),
      builder: (_, asnap) {
        return StreamBuilder<Map<String, Map<String, dynamic>>>(
          stream: repo.gridPostsStream(widget.groupId),
          builder: (_, psnap) {
            final alarms = asnap.data ?? {};
            final posts  = psnap.data ?? {};
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1,
              ),
              itemCount: widget.memberUids.length,
              itemBuilder: (_, i) {
                final uid = widget.memberUids[i];
                final alarm = alarms[uid] != null ? TodayAlarm.fromMap(uid, {
                  ...alarms[uid]!, 'graceMins': (alarms[uid]?['graceMins'] as int?) ?? _settings.graceMins
                }) : null;
                final post  = posts[uid]  != null ? GridPost.fromMap(uid, posts[uid]!)  : null;
                final status = computeStatus(now: _now, alarm: alarm, post: post);
                final snoozeCount = (alarms[uid]?['snoozeCount'] as int?) ?? 0;
                final isMe = uid == widget.myUid;
                final isRed = status == WakeCellStatus.lateSuspicious;
                return _WakeCell(
                  uid: uid, isMe: isMe, status: status, post: post, snoozeCount: snoozeCount,
                  warn: snoozeCount >= _settings.snoozeWarnThreshold,
                  onTap: () => isMe ? _onTapMe(post) : _onTapOther(uid, post, status),
                  onWake: (!isMe && isRed) ? () => _wake(uid) : null,
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _setAlarm() async {
    final now = DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (picked == null) return;
    var alarm = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    if (alarm.isBefore(now)) {
      alarm = alarm.add(const Duration(days: 1));
    }
    final nid = widget.myUid.hashCode ^ widget.groupId.hashCode;
    await NotificationService.instance.scheduleAlarm(
      id: nid,
      alarmAtLocal: alarm,
    );
    await repo.setTodayAlarm(
      widget.groupId,
      widget.myUid,
      alarmAt: alarm,
      graceMins: _settings.graceMins,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('アラームをセットしました')));
  }

  Future<void> _wake(String uid) async {
    await repo.sendWakeNudge(widget.groupId, targetUid: uid, senderUid: widget.myUid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('📣 $uid に起こすを送りました')));
  }

  Future<void> _onTapMe(GridPost? post) async {
    if (post == null) {
      await repo.postOhayo(widget.groupId, widget.myUid);
      if (!mounted) return;

      final addPhoto = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('写真を添付しますか？'),
          content: const Text('ギャラリーまたはカメラを選べます。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('しない')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('する')),
          ],
        ),
      );

      if (addPhoto == true) {
        final which = await showModalBottomSheet<String>(
          context: context, builder: (_) => SafeArea(child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo),  title: const Text('ギャラリーから選ぶ'), onTap: () => Navigator.pop(context, 'gallery')),
          ListTile(leading: const Icon(Icons.camera), title: const Text('カメラで撮影'),     onTap: () => Navigator.pop(context, 'camera')),
        ])),
        );
        File? file;
        if (which == 'gallery') file = await ImagePick.pickFromGallery();
        if (which == 'camera')  file = await ImagePick.pickFromCamera();

        if (file != null) {
          showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
          try {
            final url = await store.uploadGroupTodayPhoto(groupId: widget.groupId, uid: widget.myUid, file: file);
            await repo.attachPhoto(widget.groupId, widget.myUid, photoUrl: url);
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('アップロード失敗: $e')));
          } finally {
            if (mounted) Navigator.of(context).pop();
          }
        }
      }

      // 投稿できたらローカル通知を止める（通知IDはgroupIdとuidから）
      final nid = widget.myUid.hashCode ^ widget.groupId.hashCode;
      await NotificationService.instance.cancel(nid);
    } else {
      // 自分の投稿詳細を出したい場合はここに実装
    }
  }

  Future<void> _onTapOther(String uid, GridPost? post, WakeCellStatus status) async {
    final isRed = status == WakeCellStatus.lateSuspicious;
    if (isRed) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('起こしますか？'),
          content: Text('$uid に「起こす」を送ります'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('起こす')),
          ],
        ),
      );
      if (ok == true) _wake(uid);
      return;
    }

    if (post != null && post.photoUrl != null) {
      await showDialog(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(post.photoUrl!))));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('👍 応援を送りました！')));
    }
  }
}

class _WakeCell extends StatefulWidget {
  final String uid; final bool isMe; final WakeCellStatus status;
  final GridPost? post; final int snoozeCount; final bool warn;
  final VoidCallback onTap; final VoidCallback? onWake;
  const _WakeCell({super.key, required this.uid, required this.isMe, required this.status,
    required this.post, required this.snoozeCount, required this.warn, required this.onTap, this.onWake});

  @override State<_WakeCell> createState() => _WakeCellState();
}

class _WakeCellState extends State<_WakeCell> with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  late final Animation<double> _a = Tween(begin: 0.95, end: 1.05).animate(CurvedAnimation(parent: _ac, curve: Curves.easeInOut));
  @override void dispose() { _ac.dispose(); super.dispose(); }

  Color _bg() {
    switch (widget.status) {
      case WakeCellStatus.noAlarm:        return Colors.grey.shade300;
      case WakeCellStatus.waiting:        return Colors.blueGrey.shade100;
      case WakeCellStatus.due:            return Colors.amber.shade200;
      case WakeCellStatus.lateSuspicious: return Colors.red.shade300;
      case WakeCellStatus.posted:         return Colors.green.shade200;
    }
  }

  Icon _overlayIcon() {
    switch (widget.status) {
      case WakeCellStatus.noAlarm:        return const Icon(Icons.timer_off);
      case WakeCellStatus.waiting:        return const Icon(Icons.hourglass_bottom);
      case WakeCellStatus.due:            return const Icon(Icons.warning_amber);
      case WakeCellStatus.lateSuspicious: return const Icon(Icons.priority_high);
      case WakeCellStatus.posted:         return const Icon(Icons.check_circle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRed = widget.status == WakeCellStatus.lateSuspicious;
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: _bg(),
          borderRadius: BorderRadius.circular(12),
          border: widget.warn ? Border.all(color: Colors.redAccent, width: 2) : null,
        ),
        padding: const EdgeInsets.all(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.post?.photoUrl != null)
              ClipRRect(borderRadius: BorderRadius.circular(10),
                  child: Image.network(widget.post!.photoUrl!, fit: BoxFit.cover)),
            Align(alignment: Alignment.topLeft,
                child: Row(children: [
                  if (widget.isMe) const Icon(Icons.person, size: 14),
                  const SizedBox(width: 4),
                  Text(widget.uid, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                ])),
            Align(alignment: Alignment.bottomRight, child: _overlayIcon()),
            if (widget.snoozeCount > 0)
              Positioned(top: 4, right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.warn ? Colors.redAccent : Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.snooze, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('×${widget.snoozeCount}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ]),
                  )),
            if (isRed && widget.onWake != null)
              Positioned(right: 6, bottom: 6,
                  child: ScaleTransition(scale: _a,
                    child: FloatingActionButton.small(
                      heroTag: null, onPressed: widget.onWake,
                      child: const Icon(Icons.notifications_active),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
