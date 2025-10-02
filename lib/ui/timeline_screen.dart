// lib/ui/timeline_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/user_repo.dart';
import 'package:team_alarm1_2/core/wake_cell_status.dart';
import 'package:team_alarm1_2/utils/gradients.dart';

class TimelineScreen extends StatefulWidget {
  final String groupId;
  const TimelineScreen({super.key, required this.groupId});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  // 種別→WakeCellStatus
  WakeCellStatus _statusForType(String t) {
    switch (t) {
      case 'wake':   return WakeCellStatus.posted;         // 起床
      case 'sleep':  return WakeCellStatus.waiting;        // 就寝（目標前）
      case 'snooze': return WakeCellStatus.snoozing;       // スヌーズ
      case 'nudge':  return WakeCellStatus.lateSuspicious; // まだ起きてない（猶予超過に近い扱い）
      case 'reset':  return WakeCellStatus.noAlarm;        // リセットはニュートラル
      case 'cheer':  return WakeCellStatus.posted;         // エールは前向き＝緑系に寄せる
      default:       return WakeCellStatus.noAlarm;
    }
  }

  // 種別名を正規化（Firestoreのtype値をまとめる）
  String _normalizeType(String t) {
    final s = (t).toLowerCase().trim();

    switch (s) {
    // 起床系
      case 'wake':
      case 'posted':
      case 'wake_up':
      case 'woke':
        return 'wake';

    // 就寝系（厳密一致）
      case 'sleep':
      case 'sleep_start':
      case 'sleeping':
      case 'go_to_bed':
      case 'went_to_bed':
      case 'slept':
        return 'sleep';

    // スヌーズ系（厳密一致）
      case 'snooze':
      case 'snooz':
      case 'snoozed':
      case 'snoozing':
      case 'snooze_start':
        return 'snooze';

    // つつき/リマインド系
      case 'nudge':
      case 'poke':
      case 'remind':
      case 'reminder':
        return 'nudge';

    // エール系
      case 'cheer':
      case 'cheers':
      case 'cheering':
      case 'encourage':
        return 'cheer';

    // リセット系
      case 'reset':
      case 'cycle_reset':
        return 'reset';
    }

    // ---- ここから部分一致のフォールバック ----
    if (s.contains('sleep')) return 'sleep';
    if (s.contains('snooz')) return 'snooze';
    if (s.contains('wake')) return 'wake';
    if (s.contains('cheer') || s.contains('encour')) return 'cheer';
    if (s.contains('nudge') || s.contains('poke') || s.contains('remind')) return 'nudge';

    return 'event';
  }
  final _sc = ScrollController();

  bool _didInitialAutoScroll = false;

  void _scrollToBottom({bool animate = true}) {
    if (!_sc.hasClients) return;
    final pos = _sc.position.maxScrollExtent;
    if (animate) {
      _sc.animateTo(pos, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _sc.jumpTo(pos);
    }
  }

  // === Aramo & latest state ===
  String? _aramoPhrase;      // 最新イベントのコメント文（コメントのみ）
  String? _latestEventId;    // 最新イベントID（ハイライト/バブル追従）
  Timestamp? _latestEventTs; // 最新イベントの createdAt

  int _newBadgeCount = 0;    // 画面が最下部でない時の新着件数
  bool _atBottom = true;     // 今、最下部付近かどうか

  @override
  void initState() {
    super.initState();
    _sc.addListener(() {
      if (!_sc.hasClients) return;
      final distanceFromBottom = _sc.position.maxScrollExtent - _sc.position.pixels;
      final nowAtBottom = distanceFromBottom < 24.0;
      if (nowAtBottom != _atBottom) {
        setState(() => _atBottom = nowAtBottom);
        if (nowAtBottom) setState(() => _newBadgeCount = 0);
      }
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    // グループDocをlisten（リセット連動のため cycle.startedAt を参照）
    final groupStream = db.collection('groups').doc(widget.groupId).snapshots();

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
          automaticallyImplyLeading: false,

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
        ),
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // うっすら背景
            const IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: 0.06,
                  child: Icon(Icons.arrow_downward, size: 220, color: Colors.white),
                ),
              ),
            ),

            // 本体
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: groupStream,
              builder: (context, gSnap) {
                if (!gSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // サイクル境界（未設定なら当日0:00）
                final now = DateTime.now();
                final startFromGroup = (gSnap.data!.data()?['cycle']?['startedAt'] as Timestamp?)?.toDate();
                final start = startFromGroup ?? DateTime(now.year, now.month, now.day);
                final end = start.add(const Duration(days: 1));

                final tlStream = db
                    .collection('groups')
                    .doc(widget.groupId)
                    .collection('timeline')
                    .orderBy('createdAt', descending: false)
                    .snapshots();

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: tlStream,
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final allDocs = snap.data!.docs;
                    // サーバ側フィルタで取りこぼすケース対策：クライアントで当日範囲のみフィルタ
                    final docs = allDocs.where((d) {
                      final e = d.data();
                      final ts = e['createdAt'];
                      if (ts is Timestamp) {
                        final dt = ts.toDate();
                        return !dt.isBefore(start) && dt.isBefore(end);
                      }
                      // createdAt が無い/不正なら表示しない
                      return false;
                    }).toList();
                    if (!_didInitialAutoScroll) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _didInitialAutoScroll = true;
                        _scrollToBottom(animate: false);
                      });
                    }

                    if (docs.isEmpty) {
                      return const Center(
                        child: Text('今日はまだログがありません 🌙',
                            style: TextStyle(color: Colors.white70)),
                      );
                    }

                    // === 新着イベント検出：最新ID/TSとアラモ文面を更新（常時保持）
                    final latest = docs.last; // createdAt 昇順の最後尾
                    final data = latest.data();
                    final ts = data['createdAt'];
                    final type = _normalizeType((data['type'] as String?) ?? 'event');
                    if (ts is Timestamp) {
                      final isNewer = (_latestEventTs == null) || ts.compareTo(_latestEventTs!) > 0;
                      if (isNewer) {
                        _latestEventTs = ts;
                        _latestEventId = latest.id;

                        // コメントのみ（アイコン/時刻なし）
                        final p = _pickPhraseForEvent(type, latest.id, ts.toDate()) ?? '';
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() {
                            _aramoPhrase = p; // 次の新着まで残す
                          });
                        });

                        // 追従スクロール：最下部付近にいるときだけ自動で末尾へ
                        if (_atBottom) {
                          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                        }

                        if (!_atBottom) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _newBadgeCount += 1);
                          });
                        }
                      }
                    }

                    // UIリスト
                    return Stack(
                      children: [
                        ListView.separated(
                          controller: _sc,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 132),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final e = docs[i].data();
                            final type = _normalizeType(((e['type'] as String?) ?? 'event'));
                            // reset はタイムラインには表示しない（通知は別途発火）
                            if (type == 'reset') {
                              return const SizedBox.shrink();
                            }
                            final ts = e['createdAt'];
                            final timeLabel = (ts is Timestamp)
                                ? DateFormat('HH:mm').format(ts.toDate())
                                : '';

                            final by = _actorId(e);
                            final to = _targetId(e);

                            final profilesStream = UserRepo().profilesByUids(
                              [if (by != null) by!, if (to != null) to!],
                            );

                            return StreamBuilder<Map<String, Map<String, dynamic>>>(
                              stream: profilesStream,
                              builder: (context, profSnap) {
                                final profiles = profSnap.data ?? const {};
                                final profBy = (by != null) ? profiles[by] : null;
                                final displayName = (profBy?['displayName'] as String?) ?? (by ?? 'someone');
                                final icon = _compactIcon(type);
                                final text = _compactText(
                                  type,
                                  displayName,
                                  toName: (to != null)
                                      ? ((profiles[to]?['displayName'] as String?) ?? to)
                                      : null,
                                );

                                final isLatest = (docs[i].id == _latestEventId);
                                final tsDate = (ts is Timestamp) ? ts.toDate() : null;
                                final fallback = _pickPhraseForEvent(type, docs[i].id, tsDate) ?? '';
                                final bubbleText = _aramoPhrase ?? fallback; // コメントのみ

                                // ===== 非最新：灰色背景 + 小アラモ（偶数=左／奇数=右） =====
                                if (!isLatest) {
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        if (i % 2 == 0) _userSideIcon(profBy, size: 40), // カード外・左
                                        if (i % 2 == 0) const SizedBox(width: 8),

                                        // カード本体（灰色のはっきり背景）
                                        Flexible(
                                          fit: FlexFit.loose,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: MediaQuery.of(context).size.width * 0.73,
                                            ),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1F2730),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: Colors.white12),
                                              ),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              child: ListTile(
                                                leading: icon,
                                                title: Text(
                                                  text,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(color: Colors.white),
                                                ),
                                                trailing: Text(timeLabel, style: const TextStyle(color: Colors.white70)),
                                                dense: true,
                                                visualDensity: VisualDensity(horizontal: 0, vertical: -4),
                                                minLeadingWidth: 28,
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                                tileColor: Colors.transparent,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                            ),
                                          ),
                                        ),

                                        if (i % 2 == 1) const SizedBox(width: 8),
                                        if (i % 2 == 1) _userSideIcon(profBy, size: 40), // カード外・右
                                      ],
                                    ),
                                  );
                                }

                                // ===== 最新：イベント色のはっきり背景 + 太枠 + NEW + 右詰めバブル + 大アラモ =====
                                // ===== 最新：基本は他と同じカード（はっきり背景）＋NEW/でかアラモ/バブルをまとめる枠 =====
                                final acc   = _accentColor(type);
                                final gradColors = getGradientColors(_statusForType(type));

// まとめ枠（薄く色づけ・境界と影）：イベントカード＋バブル＋でかアラモ＋NEWを一括り
                                return Padding(
                                    padding: const EdgeInsets.only(top: 12), // ← 最新の“直前”だけ余白を追加
                                    child: Container(
                                  decoration: BoxDecoration(
                                    color: acc.withOpacity(0.10),                 // 薄い色づけ（まとめ枠）
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: acc.withOpacity(0.35), width: 1.4),
                                    boxShadow: [BoxShadow(color: acc.withOpacity(0.22), blurRadius: 10, offset: const Offset(0, 3))],
                                  ),
                                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      // 本文：イベントカード（はっきり背景）→ 右詰めの［バブル→でかアラモ］
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // 1) イベントカード（はっきりしたイベント色の背景）※横潰れ回避：カードはフル幅、ユーザーアイコンは重ねる
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              // 左に固定幅のユーザーアイコン（重ならない）
                                              SizedBox(width: 48, child: Center(child: _userSideIcon(profBy, size: 40))),
                                              const SizedBox(width: 8),
                                              // 右側はカードを Expanded でフルに使う（横潰れ防止）
                                              Expanded(
                                                child: Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: gradColors,
                                                ),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.0),
                                              ),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  child: ListTile(
                                                    leading: icon,
                                                    title: Text(
                                                      text,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(color: Colors.white),
                                                    ),
                                                    trailing: Text(timeLabel, style: const TextStyle(color: Colors.white)),
                                                    dense: true,
                                                    visualDensity: VisualDensity.compact,
                                                    minLeadingWidth: 28,
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                                    tileColor: Colors.transparent,
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),

                                          // 2) 右詰め：バブル（右向きしっぽ）→ でかアラモ（最右）
                                          if (bubbleText.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.end,
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  // バブル：必ず右詰め＆アラモ直左に配置
                                                  ConstrainedBox(
                                                    constraints: BoxConstraints(
                                                      maxWidth: MediaQuery.of(context).size.width * 0.62,
                                                    ),
                                                    child: _aramoBubble(bubbleText, tailOnRight: true), // 右向きしっぽ=アラモへ
                                                  ),
                                                  const SizedBox(width: 30),
                                                  // でかアラモ（最右）※ 枠からはみ出さないように左へ平行移動
                                                  Transform.translate(
                                                    offset: const Offset(-6, 0),
                                                    child: Container(
                                                      width: 104,
                                                      height: 104,
                                                      decoration: BoxDecoration(
                                                        color: Colors.white.withOpacity(0.18),
                                                        shape: BoxShape.circle,
                                                        border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.8),
                                                        boxShadow: const [
                                                          BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 3)),
                                                        ],
                                                      ),
                                                      child: Center(
                                                        child: Builder(
                                                          builder: (_) {
                                                            final photo = _profilePhotoUrl(profBy);
                                                            if (photo != null && photo.isNotEmpty) {
                                                              return ClipOval(
                                                                child: Image.network(
                                                                  photo,
                                                                  width: 96,
                                                                  height: 96,
                                                                  fit: BoxFit.cover,
                                                                ),
                                                              );
                                                            }
                                                            return const Icon(Icons.alarm, color: Colors.white, size: 60);
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),

                                      // NEW バッジ（左上角に大きく） — 常に最前面になるように最後に配置
                                      Positioned(
                                        left: -20,
                                        top: -35,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: acc, // 状態に合わせたアクセント色を背景に
                                            borderRadius: BorderRadius.circular(8),
                                            boxShadow: [BoxShadow(color: acc.withOpacity(0.45), blurRadius: 6)],
                                          ),
                                          child: Text(
                                            'NEW',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 18,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                 ),
                                );
                              },
                            );
                          },
                        ),

                        // === 「新着」バッジ（最下部でない時に新規イベント到着） ===
                        if (_newBadgeCount > 0 && !_atBottom)
                          Positioned(
                            bottom: 24 + MediaQuery.of(context).padding.bottom,
                            right: 16,
                            child: GestureDetector(
                              onTap: () {
                                if (_sc.hasClients) {
                                  _sc.animateTo(_sc.position.maxScrollExtent,
                                      duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                                }
                                setState(() => _newBadgeCount = 0);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Text('新着 $_newBadgeCount',
                                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: const Color(0xFF0E1B2A),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white54,
          currentIndex: 1, // 0=グリット, 1=タイムライン(現在)
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: ''),
            BottomNavigationBarItem(icon: Icon(Icons.horizontal_split), label: ''),
          ],
          onTap: (idx) {
            if (idx == 0) {
              // グリットへ戻る：前の画面（GroupGridScreen）に戻すだけ
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            }
            // idx == 1 は現在のタブ（タイムライン）なので何もしない
          },
        ),
      ),
    );
  }

  // 操作者を推論: by ?? uid ?? from
  static String? _actorId(Map<String, dynamic> e) {
    final by = e['by'];
    if (by is String && by.isNotEmpty) return by;
    final uid = e['uid'];
    if (uid is String && uid.isNotEmpty) return uid;
    final from = e['from'];
    if (from is String && from.isNotEmpty) return from;
    return null;
  }

  /// 相手（応援・起こす）を推論
  static String? _targetId(Map<String, dynamic> e) {
    final to = e['to'];
    if (to is String && to.isNotEmpty) return to;
    return null;
  }

  // === コメントのみの吹き出し（しっぽの向きを切替できる） ===
  Widget _aramoBubble(String text, {bool tailOnRight = false}) {
    const bubbleColor = Color(0xFFFFB74D); // オレンジ（見やすい）
    const bodyFg = Colors.black87;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 本体
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: bodyFg, fontSize: 13, height: 1.25),
          ),
        ),
        // しっぽ：左右端・縦中央に配置してアラモ側へ向ける
        Positioned(
          right: tailOnRight ? -7 : null,
          left: tailOnRight ? null : -7,
          top: 0,
          bottom: 0,
          child: const Center(
            child: _AramoTail(color: bubbleColor),
          ),
        ),
      ],
    );
  }

  // ==== サイドに出すユーザーアイコン（Aramo から置き換え） ====
  String? _profilePhotoUrl(Map<String, dynamic>? p) {
    if (p == null) return null;
    final candidates = [
      p['photoUrl'], p['photoURL'], p['avatarUrl'], p['iconUrl'], p['photo'], p['imageUrl'],
    ];
    for (final c in candidates) {
      if (c is String && c.isNotEmpty) return c;
    }
    return null;
  }

  Widget _userSideIcon(Map<String, dynamic>? profile, {double size = 40}) {
    final url = _profilePhotoUrl(profile);
    final border = Border.all(color: Colors.white24, width: (size / 24) * 1.0);

    if (url != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: border,
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
          image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
        ),
      );
    }

    // ← フォールバックは必ず person
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        shape: BoxShape.circle,
        border: border,
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.person, size: 18, color: Colors.white70),
    );
  }


  // === 最新イベントの強調用カラー ===
  // 枠色（明るめ）
  Color _accentColor(String t) => switch (t) {
    'wake'  => const Color(0xFFFFB300), // Amber
    'sleep' => const Color(0xFF64B5F6), // Light Blue
    'cheer' => const Color(0xFF81C784), // Light Green
    'snooze'=> const Color(0xFFFFA726), // Orange
    'nudge' => const Color(0xFFE57373), // Red-ish
    'reset' => const Color(0xFFBCAAA4), // Brown/Greige
    _       => const Color(0xFF90A4AE), // BlueGrey
  };

  // 背景色（はっきりしたイベント色。白文字が読める濃さを選定）
  Color _accentBgColor(String t) => switch (t) {
    'wake'  => const Color(0xFFFF8F00), // Dark Amber
    'sleep' => const Color(0xFF1976D2), // Strong Blue
    'cheer' => const Color(0xFF2E7D32), // Strong Green
    'snooze'=> const Color(0xFFF57C00), // Deep Orange
    'nudge' => const Color(0xFFD32F2F), // Strong Red
    'reset' => const Color(0xFF6D4C41), // Brown
    _       => const Color(0xFF37474F), // BlueGrey
  };

  // 小アラモ（過去イベント用）
  // 小アラモ（過去イベント用）— サイズ指定対応
  Widget _smallAramoIcon({double size = 24}) {
    final iconSize = (size * 0.58).clamp(10.0, 28.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: (size / 24) * 1.0),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Center(
        child: Icon(Icons.alarm, size: iconSize, color: Colors.white70),
      ),
    );
  }

  // ===== 読みやすい前景色を背景色から推定 =====
  Color _onColor(Color bg, {bool muted = false}) {
    final isLight = bg.computeLuminance() > 0.45; // 0(暗)〜1(明)
    if (muted) {
      return isLight ? Colors.black54 : Colors.white70;
    }
    return isLight ? Colors.black87 : Colors.white;
  }

// 最新カードだけ：種別→アイコンData（色は _onColor で塗る）
  IconData _iconData(String t) => switch (t) {
    'wake'   => Icons.wb_sunny,
    'sleep'  => Icons.nightlight_round,
    'cheer'  => Icons.emoji_emotions,
    'snooze' => Icons.snooze,
    'nudge'  => Icons.notifications_active,
    'reset'  => Icons.refresh,
    _        => Icons.event,
  };

  // ==== 表示ヘルパ ====
  Icon _compactIcon(String t) => switch (t) {
    'wake'  => const Icon(Icons.wb_sunny, size: 20, color: Color(0xFFFFB300)),
    'sleep' => const Icon(Icons.nightlight_round, size: 20, color: Color(0xFF64B5F6)),
    'cheer' => const Icon(Icons.emoji_emotions, size: 20, color: Color(0xFF81C784)),
    'snooze'=> const Icon(Icons.snooze, size: 20, color: Color(0xFFFFA726)),
    'nudge' => const Icon(Icons.notifications_active, size: 20, color: Color(0xFFE57373)),
    'reset' => const Icon(Icons.refresh, size: 20, color: Color(0xFFBCAAA4)),
    _       => const Icon(Icons.event, size: 20, color: Color(0xFF90A4AE)),
  };

  String _compactText(String type, String name, {String? toName}) {
    return switch (type) {
      'wake'  => '$name が起床！',
      'sleep' => '$name が就寝！',
      'snooze'=> '$name がスヌーズ！',
      'cheer' => (toName != null) ? '$name が $toName にエール！' : '$name がエール！',
      _       => '$name のイベント',
    };
  }

  // === フレーズ定義（安定選択用） ===
  static const Map<String, List<Map<String, String>>> _phrases = {
    'wake': [
      {'id': 'wake_1', 'text': '起きられたね,いい感じ！'},
      {'id': 'wake_2', 'text': '今日も頑張ろう！'},
      {'id': 'wake_3', 'text': '目覚めはどう？'}
    ],
    'sleep': [
      {'id': 'sleep_1', 'text': 'おやすみ〜'},
      {'id': 'sleep_2', 'text': 'いい夢みてね'},
      {'id': 'sleep_3', 'text': 'また明日ね'}
    ],
    'snooze': [
      {'id': 'snooze_1', 'text': '気持ちはわかる…'},
      {'id': 'snooze_2', 'text': 'もうちょっと寝たいよね...'},
      {'id': 'snooze_3', 'text': '布団の魔力はつよい...'},
      {'id': 'snooze_3', 'text': 'スヌーズバッチひとつ追加ね...'}
    ],
    'cheer': [
      {'id': 'cheer_1', 'text': 'いいチームだね'},
      {'id': 'cheer_2', 'text': 'ぼくもエールを送るよ'},
      {'id': 'cheer_3', 'text': 'ナイスアシスト！'}
    ],
    'nudge': [
      {'id': 'nudge_1', 'text': '時間だよ〜おきて!'},
      {'id': 'nudge_2', 'text': 'そろそろ起きよう〜'},
      {'id': 'nudge_3', 'text': 'ファイトだよ'}
    ],
    'reset': [
      {'id': 'reset_1', 'text': '新しいサイクルが始まったよ！'},
      {'id': 'reset_2', 'text': 'みんな頑張ったね〜'},
      {'id': 'reset_3', 'text': 'また明日ね'}
    ],
  };

  // イベントIDと時刻から安定的にフレーズを選ぶ（再描画でも変わらない）
  String? _pickPhraseForEvent(String type, String eventId, DateTime? at) {
    final list = _phrases[type];
    if (list == null || list.isEmpty) return null;
    // 簡易ハッシュ（eventId + 分単位の時刻）
    final seed = eventId.codeUnits.fold<int>(0, (p, c) => p + c) + (at != null ? at.millisecondsSinceEpoch ~/ 60000 : 0);
    final idx = seed.abs() % list.length;
    return list[idx]['text'];
  }
}

// しっぽ（菱形）・色指定可
class _AramoTail extends StatelessWidget {
  final Color color;
  const _AramoTail({required this.color});
  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398, // 45°
      child: Container(
        width: 14,
        height: 14,
        color: color,
      ),
    );
  }
}