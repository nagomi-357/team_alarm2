// lib/ui/sleep_lock_screen.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/wake_logic.dart';
import '../models/models.dart';
import '../models/grid_post.dart';
import '../data/group_repo.dart';
import '../data/timeline_repo.dart';
import '../data/user_repo.dart';
import '../notifications/notification_service.dart';
import 'group_grid_screen.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class SleepLockScreen extends StatefulWidget {
  const SleepLockScreen({
    super.key,
    required this.groupId,
    required this.myUid,
    required this.memberUids,
    required this.settings,
  });

  final String groupId;
  final String myUid;
  final List<String> memberUids;
  final GroupSettings settings;

  @override
  State<SleepLockScreen> createState() => _SleepLockScreenState();
}

class _SleepLockScreenState extends State<SleepLockScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // --- Alarm audio (loop while on this screen) ---
  late final AudioPlayer _alarmPlayer;
  // 重複ナビゲーション抑止用フラグ
  bool _navigatedBack = false;
  final repo = GroupRepo();
  final tl = TimelineRepo();
  DateTime _now = DateTime.now();
  Timer? _ticker;
  // Snooze multi-tap guard
  bool _localSnoozing = false; // true right after user taps snooze
  bool _wasDue = false;        // last frame's due state

  // 背景/リング/パルス
  late final AnimationController bgCtrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  late AnimationController ringCtrl;
  late final AnimationController pulseCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  // 背景粒子
  late final AnimationController particlesCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
    // 回転リング用コントローラ（デフォルト10秒周期で確実に回す）
    ringCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..repeat();
    WidgetsBinding.instance.addObserver(this);
    // Alarm player: initialize only (do NOT start here)
    _alarmPlayer = AudioPlayer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try { _alarmPlayer.dispose(); } catch (_) {}
    _ticker?.cancel();
    bgCtrl.dispose();
    ringCtrl.dispose();
    pulseCtrl.dispose();
    particlesCtrl.dispose();
    super.dispose();
  }

  Future<void> _startAlarmLoop() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    try {
      await _alarmPlayer.setAsset('assets/audio/alarm_elegant.caf');
      await _alarmPlayer.setLoopMode(LoopMode.one);
      await _alarmPlayer.play();
    } catch (e) {
      // ignore: avoid_print
      print('alarm loop error: $e');
    }
  }

  Future<void> _stopAlarmLoop() async {
    try { await _alarmPlayer.stop(); } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      // App came to foreground; if due and not snoozing, ensure loop is running
      if (_wasDue && !_localSnoozing) {
        // If player is not already playing, (re)start
        if (!_alarmPlayer.playing) {
          _startAlarmLoop();
        }
      }
    }
  }

  Future<void> _handleWake() async {
    await _stopAlarmLoop(); // stop continuous alarm sound
    // 既存起床フローの呼び出し
    await repo.postOhayo(widget.groupId, widget.myUid);
    await repo.setWakeAt(groupId: widget.groupId, uid: widget.myUid, wakeAt: DateTime.now());
    final _nid = (widget.myUid.hashCode ^ widget.groupId.hashCode) & 0x7fffffff;
    await NotificationService.instance.cancel(_nid);
    await tl.log(widget.groupId, {'type': 'wake', 'uid': widget.myUid});
    // ロック解除
    await UserRepo().setSleepLocked(uid: widget.myUid, locked: false);
    if (!mounted) return;
    // グリッドに戻る（重複防止）
    if (!_navigatedBack) {
      _navigatedBack = true;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => GroupGridScreen(
              groupId: widget.groupId,
              myUid: widget.myUid,
              memberUids: widget.memberUids,
              availableGroups: const [],
            ),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GroupGridScreen(
              groupId: widget.groupId,
              myUid: widget.myUid,
              memberUids: widget.memberUids,
              availableGroups: const [],
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleSnooze() async {
    if (_localSnoozing) return; // already processed
    setState(() => _localSnoozing = true);
    await _stopAlarmLoop(); // stop current loop when user snoozes
    // 既存スヌーズフローの呼び出し
    await repo.incrementSnooze(widget.groupId, widget.myUid, widget.settings.snoozeStepMins);
    final nid = (widget.groupId.hashCode ^ widget.myUid.hashCode) & 0x7fffffff;
    final next = DateTime.now().add(Duration(minutes: widget.settings.snoozeStepMins));
    await NotificationService.instance.cancel(nid);
    await NotificationService.instance.scheduleAlarm(
      id: nid,
      at: next,
      title: 'スヌーズ',
      body: 'そろそろ起きる時間です',
    );
    await tl.log(widget.groupId, {'type': 'snooze', 'by': widget.myUid});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('スヌーズ: ${widget.settings.snoozeStepMins}分後に再通知します')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 自分の alarm/post の状態を監視（wakeAtが付いたら自動解除）
    return WillPopScope(
      onWillPop: () async => false, // 戻る禁止
      child: StreamBuilder<Map<String, Map<String, dynamic>>>(
        stream: repo.todayAlarms(widget.groupId),
        builder: (_, as) {
          return StreamBuilder<Map<String, Map<String, dynamic>>>(
            stream: repo.gridPosts(widget.groupId),
            builder: (_, ps) {
              final alarms = as.data ?? {};
              final posts = ps.data ?? {};
              final myAlarm = alarms[widget.myUid] != null
                  ? TodayAlarm.fromMap(widget.myUid, {
                ...alarms[widget.myUid]!,
                'graceMins': (alarms[widget.myUid]?['graceMins'] ?? widget.settings.graceMins),
              })
                  : null;
              final myPost = posts[widget.myUid] != null
                  ? GridPost.fromMap(widget.myUid, posts[widget.myUid]!)
                  : null;

              // wakeAt が付いたらロックを解除（ナビゲーションはここでは行わない）
              if (myAlarm?.wakeAt != null) {
                UserRepo().setSleepLocked(uid: widget.myUid, locked: false);
              }

              final myAlarmAt = myAlarm?.alarmAt;
              final isDue = (myAlarmAt != null) && !_now.isBefore(myAlarmAt) && myAlarm?.wakeAt == null;
              if (_wasDue != isDue) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  // Start/stop in-app alarm loop on due-state transitions
                  if (!_wasDue && isDue) {
                    // Entered due: begin continuous loop playback
                    _startAlarmLoop(); // fire-and-forget for responsiveness
                  } else if (_wasDue && !isDue) {
                    // Left due: stop playback
                    _stopAlarmLoop();
                  }
                  setState(() {
                    _wasDue = isDue;
                    if (!isDue) _localSnoozing = false; // left due: allow future snooze on next alarm
                  });
                });
              }

              // Safety: if currently due but player is not running (and not in a snooze press), start it.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (isDue && !_localSnoozing) {
                  if (!_alarmPlayer.playing) {
                    _startAlarmLoop();
                  }
                } else {
                  // Not due: ensure stopped
                  if (_alarmPlayer.playing) {
                    _stopAlarmLoop();
                  }
                }
              });

              // リングの速度（近づくほど加速）
              final mins = (myAlarmAt != null) ? myAlarmAt.difference(_now).inMinutes : 9999;
              Duration period;
              if (mins >= 60)       { period = const Duration(seconds: 12); }
              else if (mins >= 15)  { period = const Duration(seconds: 8); }
              else if (mins >= 5)   { period = const Duration(seconds: 4); }
              else if (mins >= 1)   { period = const Duration(seconds: 2); }
              else                  { period = const Duration(seconds: 1); }
              void _applyPeriod(Duration period) {
                if (ringCtrl.duration == period) return;
                final v = ringCtrl.value; // 現在進捗を保持
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  ringCtrl.stop();
                  ringCtrl.duration = period; // 期間を直接設定
                  ringCtrl.forward(from: v);  // 途中進捗から再始動
                  ringCtrl.repeat();          // 繰り返し継続
                });
              }
              _applyPeriod(period);

              final remainText = (myAlarmAt == null)
                  ? '--:--'
                  : _fmtRemain(Duration(seconds: math.max(0, myAlarmAt.difference(_now).inSeconds)));

              return Scaffold(
                backgroundColor: Colors.transparent,
                body: AnimatedBuilder(
                  animation: bgCtrl,
                  builder: (_, __) {
                    final t = bgCtrl.value * 2 * math.pi;
                    final a = 0.6 * math.sin(t);
                    return Stack(
                      children: [
                        // 背景グラデーション
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(-a, -0.9),
                              end: Alignment(a, 0.9),
                              colors: const [Color(0xFF0B0F12), Color(0xFF0E1B2A)],
                            ),
                          ),
                        ),
                        // 背景粒子（デモと同じ雰囲気）
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: particlesCtrl,
                            builder: (context, _) => CustomPaint(
                              painter: ParticleFieldPainter(
                                progress: particlesCtrl.value,
                                accent: const Color(0xFF68D0F0),
                              ),
                            ),
                          ),
                        ),
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // ヘッダ：現在時刻と目標・残り
                                Row(
                                  children: [
                                    const Icon(Icons.bolt, size: 22, color: Color(0xFF8DEBFF)),
                                    const SizedBox(width: 8),
                                    const Text('sleep lock', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                    const Spacer(),
                                    Text(DateFormat('HH:mm').format(_now),
                                        style: const TextStyle(color: Colors.white70)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Expanded section for central clock
                                Expanded(
                                  child: Center(
                                    child: SizedBox(
                                      width: 260, height: 260,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          AnimatedBuilder(
                                            animation: pulseCtrl,
                                            builder: (context, _) {
                                              final pulse = isDue ? (0.5 + 0.5 * math.sin(pulseCtrl.value * 2 * math.pi)) : 0.0;
                                              return RotatingRing(
                                                controller: ringCtrl,
                                                ringAccent: isDue ? const Color(0xFFFFC36A) : const Color(0xFF12D6DF),
                                                pulse: pulse,
                                              );
                                            },
                                          ),
                                          NeonTimeText(
                                            text: DateFormat('HH:mm').format(_now),
                                            gradient: LinearGradient(colors: [
                                              isDue ? const Color(0xFFFFC36A) : const Color(0xFF12D6DF),
                                              Colors.white,
                                            ]),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Alarm label below the ring with extra spacing
                                Center(
                                  child: Text(
                                    (myAlarmAt != null)
                                        ? 'Alarm set • ${DateFormat('HH:mm').format(myAlarmAt)}'
                                        : 'Alarm set',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 25,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      shadows: [Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black45)],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 140),
                                // メンバー簡易ステータス
                                _MemberStrip(
                                  groupId: widget.groupId,
                                  memberUids: widget.memberUids,
                                  now: _now,
                                ),
                                const SizedBox(height: 16),
                                // ボタン群：起床 / スヌーズ（due以外は無効）
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.wb_sunny_rounded),
                                        label: const Text('起床'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF173248),
                                          foregroundColor: const Color(0xFFDBF7FF),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                        ),
                                        onPressed: _handleWake,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.snooze_rounded),
                                        label: const Text('スヌーズ'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: (isDue && !_localSnoozing) ? const Color(0xFF0E1B2A) : const Color(0xFF0E1B2A).withOpacity(0.6),
                                          foregroundColor: const Color(0xFF9BE7FF),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                        ),
                                        onPressed: (isDue && !_localSnoozing) ? _handleSnooze : null,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _fmtRemain(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}時間${m}分';
    if (m > 0) return '${m}分${s}秒';
    return '${s}秒';
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.accent, required this.pulse});
  final double progress;
  final Color accent;
  final double pulse;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 + 2 * pulse
      ..color = accent.withOpacity(0.2 + 0.15 * pulse);
    canvas.drawArc(rect.deflate(6), 0, 2 * math.pi, false, base);

    final sweep = math.pi * (0.55 + 0.15 * pulse);
    final start = progress * 2 * math.pi;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 + 2 * pulse
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: start,
        endAngle: start + sweep,
        colors: [accent.withOpacity(0.5 + 0.3 * pulse), accent],
      ).createShader(rect);
    canvas.drawArc(rect.deflate(6), start, sweep, false, glow);
  }
  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.accent != accent || old.pulse != pulse;
}

class _MemberStrip extends StatelessWidget {
  const _MemberStrip({required this.groupId, required this.memberUids, required this.now});
  final String groupId;
  final List<String> memberUids;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final repo = GroupRepo();
    return StreamBuilder<Map<String, Map<String, dynamic>>>(
      stream: repo.todayAlarms(groupId),
      builder: (_, as) {
        return StreamBuilder<Map<String, Map<String, dynamic>>>(
          stream: repo.gridPosts(groupId),
          builder: (_, ps) {
            final alarms = as.data ?? {};
            final posts = ps.data ?? {};
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where(FieldPath.documentId, whereIn: memberUids.take(10).toList())
                  .snapshots(),
              builder: (_, us) {
                final Map<String, String> names = {
                  for (final d in (us.data?.docs ?? const [])) d.id: ((d.data()['displayName'] as String?) ?? d.id)
                };
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: memberUids.asMap().entries.map((e) {
                      final i = e.key; final uid = e.value;
                      final a = alarms[uid] != null ? TodayAlarm.fromMap(uid, alarms[uid]!) : null;
                      final p = posts[uid] != null ? GridPost.fromMap(uid, posts[uid]!) : null;
                      final st = computeStatus(now: now, alarm: a, post: p);
                      final isAwake = p?.photoUrl != null || a?.wakeAt != null || st == WakeCellStatus.posted;
                      final label = names[uid] ?? uid;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: PulsingBorderChip(
                          controller: (context.findAncestorStateOfType<_SleepLockScreenState>()!).pulseCtrl,
                          phase: (memberUids.isEmpty ? 0.0 : (i / memberUids.length)),
                          label: label,
                          isAwake: isAwake,
                          activeAccent: const Color(0xFF12D6DF),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({required this.name, required this.isAwake});
  final String name;
  final bool isAwake;
  @override
  Widget build(BuildContext context) {
    final accent = isAwake ? const Color(0xFF7EE2A8) : const Color(0xFF3D90A1);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      width: 72, height: 72,
      decoration: BoxDecoration(
        color: const Color(0xFF12171E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.8), width: 1),
        boxShadow: [
          BoxShadow(color: accent.withOpacity(isAwake ? 0.55 : 0.25), blurRadius: isAwake ? 24 : 12, spreadRadius: isAwake ? 2 : 1),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

// --- Demo UI widgets ---
class NeonTimeText extends StatelessWidget {
  const NeonTimeText({super.key, required this.text, this.gradient = const LinearGradient(colors: [Color(0xFF9BE7FF), Color(0xFF68D0F0)])});
  final String text; final Gradient gradient;
  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      const Text(
        '', // shadow carrier
        style: TextStyle(
          fontSize: 72, fontWeight: FontWeight.w800, color: Colors.transparent,
          shadows: [Shadow(color: Color(0x4426C6FF), blurRadius: 18), Shadow(color: Color(0x2212D6DF), blurRadius: 38)],
        ),
      ),
      ShaderMask(
        shaderCallback: (rect) => gradient.createShader(rect),
        child: Text(text, style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w800, color: Colors.white)),
      ),
    ]);
  }
}

class RotatingRing extends StatelessWidget {
  const RotatingRing({super.key, required this.controller, required this.ringAccent, this.pulse = 0.0});
  final AnimationController controller; final Color ringAccent; final double pulse;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Transform.scale(
          scale: 1.0 + 0.03 * pulse,
          child: Transform.rotate(
            angle: controller.value * 2 * math.pi,
            child: CustomPaint(painter: RingPainter(progress: controller.value, accent: ringAccent, pulse: pulse), size: const Size.square(240)),
          ),
        );
      },
    );
  }
}

class RingPainter extends CustomPainter {
  RingPainter({required this.progress, required this.accent, required this.pulse});
  final double progress; final Color accent; final double pulse;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 + 2 * pulse
      ..color = accent.withOpacity(0.2 + 0.15 * pulse);
    canvas.drawArc(rect.deflate(6), 0, 2 * math.pi, false, base);
    final sweep = math.pi * (0.55 + 0.15 * pulse);
    final start = progress * 2 * math.pi;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 + 2 * pulse
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: start, endAngle: start + sweep,
        colors: [accent.withOpacity(0.5 + 0.3 * pulse), accent],
      ).createShader(rect);
    canvas.drawArc(rect.deflate(6), start, sweep, false, glow);
  }
  @override
  bool shouldRepaint(covariant RingPainter old) => old.progress != progress || old.accent != accent || old.pulse != pulse;
}

class PulsingBorderChip extends StatelessWidget {
  const PulsingBorderChip({super.key, required this.controller, required this.phase, required this.label, required this.isAwake, this.activeAccent = const Color(0xFF12D6DF)});
  final AnimationController controller; final double phase; final String label; final bool isAwake; final Color activeAccent;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final p = (controller.value + phase) % 1.0;
        final minV = isAwake ? 0.75 : 0.25; final maxV = isAwake ? 1.00 : 0.60;
        final s = minV + (maxV - minV) * (0.5 + 0.5 * math.sin(2 * math.pi * p));
        final borderW = isAwake ? 2.2 : 1.2;
        final borderColor = Color.lerp(const Color(0xFF2B3C4B), activeAccent, s)!;
        final glowColor = activeAccent.withOpacity(isAwake ? 0.55 * s : 0.25 * s);
        final labelColor = isAwake ? const Color(0xFFDBF7FF) : const Color(0xFF9FB8C8);
        return Container(
          width: 68, height: 68,
          decoration: BoxDecoration(
            color: const Color(0xFF12171E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: borderW),
            boxShadow: [BoxShadow(color: glowColor, blurRadius: (isAwake ? 28 : 18) * s + 4, spreadRadius: (isAwake ? 2.0 : 1.0) * s)],
          ),
          child: Stack(
            children: [
              Center(child: Text(label, style: TextStyle(color: labelColor, fontSize: 14, fontWeight: FontWeight.w700))),
              if (isAwake) const Positioned(right: 6, top: 6, child: Icon(Icons.wb_sunny_rounded, size: 16, color: Color(0xFFBDF3FF))),
            ],
          ),
        );
      },
    );
  }
}

class ParticleFieldPainter extends CustomPainter {
  ParticleFieldPainter({required this.progress, required this.accent}) { _initIfNeeded(); }
  static final math.Random _rng = math.Random();
  static const int _count = 70; static bool _initialized = false; static late List<_Particle> _ps;
  final double progress; final Color accent;
  void _initIfNeeded() {
    if (_initialized) return; _initialized = true;
    _ps = List.generate(_count, (i) { final x=_rng.nextDouble(); final y=_rng.nextDouble();
      final s=0.4+_rng.nextDouble()*1.6; final vy=0.02+_rng.nextDouble()*0.08; final vx=(_rng.nextDouble()-0.5)*0.02; final life=0.4+_rng.nextDouble()*0.6;
      return _Particle(x,y,vx,-vy,s,life,_rng.nextDouble()); });
  }
  @override
  void paint(Canvas canvas, Size size) {
    final w=size.width, h=size.height;
    for (var p in _ps) {
      final t=(progress + p.offset)%1.0; final px=(p.x+p.vx*t)*w; final py=(p.y+p.vy*t)*h; double y=py; if (y<0) y=h + y%h;
      final sz=2.0*p.size; final alpha=(0.2+0.8*(1 - (t/p.life).clamp(0.0,1.0))).clamp(0.0,1.0);
      final glow=Paint()..color=accent.withOpacity(alpha*0.35)..maskFilter=const MaskFilter.blur(BlurStyle.normal,4);
      canvas.drawCircle(Offset(px,y), sz, glow);
      final core=Paint()..color=Colors.white.withOpacity(alpha*0.25);
      canvas.drawCircle(Offset(px,y), sz*0.35, core);
    }
  }
  @override
  bool shouldRepaint(covariant ParticleFieldPainter old) => old.progress!=progress || old.accent!=accent;
}

class _Particle { _Particle(this.x,this.y,this.vx,this.vy,this.size,this.life,this.offset);
  double x,y; double vx,vy; double size; double life; double offset; }