// lib/ui/timeline_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/user_repo.dart';
import 'package:team_alarm1_2/core/wake_cell_status.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
      case 'cheer':  return WakeCellStatus.posted;         // エールは緑系扱い（色はラベンダーに上書き）
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

    if (s == 'post' || s == 'posted' || s == 'checkin' || s == 'check-in') return 'wake';
    if (s == 'ring' || s == 'alarm' || s == 'alarm_ring' || s == 'alarmring' || s == 'alarm_start') return 'snooze';

    // 目標/アラーム設定系 → waiting 扱い（= sleep 系色: blue）
    if (s == 'set' || s == 'set_alarm' || s == 'alarm_set' || s == 'settime' || s == 'set_time' || s == 'schedule' || s == 'scheduled' || s == 'goal_set' || s == 'set_goal') return 'sleep';

    // 遅刻/超過検知系 → nudge（= red）
    if (s == 'late' || s == 'overdue' || s == 'delayed') return 'nudge';

    // ---- ここから部分一致のフォールバック ----
    if (s.contains('sleep')) return 'sleep';
    if (s.contains('snooz')) return 'snooze';
    if (s.contains('wake')) return 'wake';
    if (s.contains('cheer') || s.contains('encour')) return 'cheer';
    if (s.contains('nudge') || s.contains('poke') || s.contains('remind')) return 'nudge';
    if (s.contains('set') || s.contains('schedule') || s.contains('goal')) return 'sleep';
    if (s.contains('overdue') || s.contains('late') || s.contains('delay')) return 'nudge';

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

  // === 最新状態管理 ===
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
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(66),
            child: _OverdueStrip(groupId: widget.groupId),
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

                    // === 新着イベント検出（末尾=最新） ===
                    final latest = docs.last; // createdAt 昇順の最後尾
                    final latestData = latest.data();
                    final ts = latestData['createdAt'];
                    if (ts is Timestamp) {
                      final isNewer = (_latestEventTs == null) || ts.compareTo(_latestEventTs!) > 0;
                      if (isNewer) {
                        _latestEventTs = ts;
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

                    // UIリスト（LINE風・左右バブル）
                    return Stack(
                      children: [
                        ListView.separated(
                          controller: _sc,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 132),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final e = docs[i].data();
                            final dynamic _rawAny = (e['type'] ?? e['status'] ?? e['action'] ?? e['eventType'] ?? e['event'] ?? e['name'] ?? e['verb'] ?? e['kind']);
                            final String rawType = (_rawAny is String && _rawAny.isNotEmpty) ? _rawAny : 'event';
                            final type = _normalizeType(rawType);
                            // reset はタイムラインには表示しない（通知は別途発火）
                            if (type == 'reset') {
                              return const SizedBox.shrink();
                            }

                            final ts = e['createdAt'];
                            final dt = (ts is Timestamp) ? ts.toDate() : null;
                            final timeLabel = (dt != null) ? DateFormat('HH:mm').format(dt) : '';

                          final by = _actorId(e);
                          final to = _targetId(e);
                          final myUid = FirebaseAuth.instance.currentUser?.uid;
                          final isMine = (by != null && myUid != null && by == myUid);
                          final isLatest = (docs[i].id == docs.last.id); // 表示範囲の最後尾が最新

                          final toNameFromEvent = (e['toName'] as String?)?.trim();

                          // by が無いイベントでも描画は継続（someone でフォールバック）
                          final bool _hasBy = (by != null && by!.isNotEmpty);

                          // --- 非ブロッキング：まずイベント埋め込みで即表示、到着したプロフィールで追い差し替え ---
                          String _fallbackName() {
                            final embed = (e['byDisplayName'] as String?)?.trim();
                            if (embed != null && embed.isNotEmpty) return embed;
                            if (_hasBy) return by!;
                            return 'someone';
                          }

                          String? _fallbackPhoto() {
                            // イベントに埋め込まれていそうなキーを広めにサポート
                            final keys = ['byPhotoUrl', 'byPhotoURL', 'photoUrl', 'photoURL', 'avatarUrl', 'iconUrl', 'picture'];
                            for (final k in keys) {
                              final v = e[k];
                              if (v is String && v.trim().isNotEmpty) return v.trim();
                            }
                            return null;
                          }

                          final byStream = _hasBy
                              ? UserRepo().userDocStream(by!)
                              : const Stream<Map<String, dynamic>?>.empty();

                            return StreamBuilder<Map<String, dynamic>?>(
                              stream: byStream,
                              builder: (context, snapBy) {
                                final profBy = snapBy.data;
                                final photoFromProf = _profilePhotoUrl(profBy);

                                // --- C案：イベント埋め込み優先 → プロフ → フォールバックの順 ---
                                String displayName = _fallbackName();
                                final fromEventName = (e['byDisplayName'] as String?)?.trim();
                                if (fromEventName != null && fromEventName.isNotEmpty) {
                                  displayName = fromEventName;
                                } else {
                                  final fromProfName = (profBy?['displayName'] as String?)?.trim();
                                  if (fromProfName != null && fromProfName.isNotEmpty) {
                                    displayName = fromProfName;
                                  }
                                }

                                String photo = _fallbackPhoto() ?? '';
                                final fromEventPhoto = ((e['byPhotoUrl'] ?? e['byPhotoURL']) as String?)?.trim();
                                if (fromEventPhoto != null && fromEventPhoto.isNotEmpty) {
                                  photo = fromEventPhoto;
                                } else if (photoFromProf != null && photoFromProf.isNotEmpty) {
                                  photo = photoFromProf;
                                }

                                // cheer 宛先名はイベント埋め込み・プロフ・uidの順で解決（非ブロッキング）
                                String resolvedToName = (e['toName'] as String?)?.trim() ?? (e['toDisplayName'] as String?)?.trim() ?? (to ?? '');

                                // --- ターゲットプロフ（to）の非ブロッキング購読：到着後に宛先名を上書き ---
                                final toStream = (to != null && to!.isNotEmpty)
                                    ? UserRepo().userDocStream(to!)
                                    : const Stream<Map<String, dynamic>?>.empty();

                                return StreamBuilder<Map<String, dynamic>?>(
                                  stream: toStream,
                                  builder: (context, snapTo) {
                                    final profTo = snapTo.data;
                                    final displayTo = (profTo?['displayName'] as String?)?.trim();
                                    if (displayTo != null && displayTo.isNotEmpty) {
                                      resolvedToName = displayTo; // イベント埋め込みよりプロフ優先で上書き
                                    }

                                    // 本文テキスト（to名を最終決定してから生成）
                                    final bubbleText = _compactText(
                                      type,
                                      displayName,
                                      toName: resolvedToName.isNotEmpty ? resolvedToName : null,
                                      rawType: rawType,
                                    );

                                    if (bubbleText.trim().isEmpty) {
                                      return const SizedBox.shrink();
                                    }

                                    // 色とバブル
                                    final borderColor = (type == 'cheer')
                                        ? kAccentCheer
                                        : tileAccentColor(_statusForType(type));
                                    final fillColor = isLatest ? borderColor : Colors.transparent;
                                    final textColor = Colors.white;

                                    final gradient = _bubbleGradientForType(type);
                                    final bubble = _eventBubble(
                                      text: bubbleText,
                                      borderColor: borderColor,
                                      fillColor: fillColor,
                                      textColor: textColor,
                                      showNewBadge: isLatest,
                                      badgeOnRight: isMine,
                                      gradient: gradient,
                                      isLatest: isLatest,
                                    );

                                    if (isMine) {
                                      // 自分：右詰め（名前・アイコンなし）／時刻はバブル左横（下端揃え）
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            if (timeLabel.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(right: 6),
                                                child: Text(
                                                  timeLabel,
                                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                                ),
                                              ),
                                            ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth: MediaQuery.of(context).size.width * 0.78,
                                              ),
                                              child: bubble,
                                            ),
                                          ],
                                        ),
                                      );
                                    } else {
                                      // 他人：左詰め（アイコン → 名前 → バブル＆右横に時刻（下端合わせ））
                                      final avatar = (photo.isNotEmpty)
                                          ? CircleAvatar(radius: 16, backgroundImage: NetworkImage(photo))
                                          : const CircleAvatar(
                                              radius: 16,
                                              backgroundColor: Color(0x33FFFFFF),
                                              child: Icon(Icons.person, size: 16, color: Colors.white70),
                                            );

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            avatar,
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(displayName, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                      ConstrainedBox(
                                                        constraints: BoxConstraints(
                                                          maxWidth: MediaQuery.of(context).size.width * 0.72,
                                                        ),
                                                        child: bubble,
                                                      ),
                                                      if (timeLabel.isNotEmpty)
                                                        Padding(
                                                          padding: const EdgeInsets.only(left: 6),
                                                          child: Text(
                                                            timeLabel,
                                                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  },
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

  // 操作者を推論: by, uid, from, userId, authorId, ownerId
  static String? _actorId(Map<String, dynamic> e) {
    for (final key in ['by', 'uid', 'from', 'userId', 'authorId', 'ownerId']) {
      final v = e[key];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  /// 相手（応援・起こす）を推論
  static String? _targetId(Map<String, dynamic> e) {
    final to = e['to'];
    if (to is String && to.isNotEmpty) return to;
    return null;
  }

  // ==== サイドに出すユーザーアイコン（fallback用・他人のみで使用） ====
  String? _profilePhotoUrl(Map<String, dynamic>? p) {
    if (p == null) return null;
    final candidates = [
      p['photoUrl'], p['photoURL'], p['avatarUrl'], p['iconUrl'],
      p['photo'], p['imageUrl'], p['avatar'], p['icon'], p['picture'],
    ];
    for (final c in candidates) {
      if (c is String && c.isNotEmpty) return c;
    }
    return null;
  }

  // ===== 読みやすい前景色を背景色から推定 =====
  Color _onColor(Color bg, {bool muted = false}) {
    final isLight = bg.computeLuminance() > 0.45; // 0(暗)〜1(明)
    if (muted) {
      return isLight ? Colors.black54 : Colors.white70;
    }
    return isLight ? Colors.black87 : Colors.white;
  }

  // ===== バブル用グラデーション：グリッド基準（gradients.dart）と完全一致 =====
  LinearGradient _bubbleGradientForType(String type) {
    // cheer はアクセント色が独立しているため、ラベンダーを基準に濃淡を作る
    if (type == 'cheer') {
      final hsl = HSLColor.fromColor(kAccentCheer);
      final c1 = hsl.withLightness((hsl.lightness + 0.08).clamp(0.0, 1.0)).toColor();
      final c2 = hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [c1, c2],
      );
    }
    // それ以外は WakeCellStatus によるグリッドのグラデーション配色を使用
    final status = _statusForType(type);
    final colors = getGradientColors(status);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    );
  }

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

  String _compactText(String type, String name, {String? toName, String? rawType}) {
    switch (type) {
      case 'wake':
        return '$name が起床！';
      case 'sleep':
        return '$name が就寝！';
      case 'snooze':
        return '$name がスヌーズ！';
      case 'cheer':
        if (toName != null && toName.isNotEmpty) {
          return '$name が $toName にエール！';
        } else {
          return '$name がエール！';
        }
      case 'nudge':
        return '$name に起床リマインド！';
      default:
        // 未知タイプは rawType を人間可読にして表示（"〇〇のイベント" は避ける）
        final rt = (rawType ?? '').trim();
        if (rt.isEmpty) return '$name のアクション';
        final label = _humanizeRawType(rt);
        return (label.isNotEmpty) ? '$name の$label' : '$name のアクション';
    }
  }

  String _humanizeRawType(String rt) {
    final s = rt.trim();
    final lower = s.toLowerCase();

    // 代表的な別名を先に握りつぶす
    const table = {
      'post': '投稿',
      'posted': '投稿',
      'checkin': 'チェックイン',
      'check-in': 'チェックイン',
      'ring': 'アラーム',
      'alarm': 'アラーム',
      'alarm_ring': 'アラーム',
      'alarmring': 'アラーム',
      'alarm_start': 'アラーム',
      'sleep_start': '就寝',
      'sleepend': '起床',
      'sleep_end': '起床',
      'woke': '起床',
      'wake_up': '起床',
      'nudge': 'リマインド',
      'remind': 'リマインド',
      'reminder': 'リマインド',
      'cheer': 'エール',
      'encourage': 'エール',
      // 追加: 設定・遅刻系
      'set': '設定',
      'set_alarm': '設定',
      'alarm_set': '設定',
      'settime': '設定',
      'set_time': '設定',
      'schedule': '設定',
      'scheduled': '設定',
      'goal_set': '設定',
      'set_goal': '設定',
      'late': '遅刻',
      'overdue': '遅刻',
      'delayed': '遅刻',
    };

    if (table.containsKey(lower)) return table[lower]!;

    // スネーク/キャメルをスペースに分割して日本語っぽく整形
    final snake = lower.replaceAll(RegExp(r'[_\-]+'), ' ');
    final camel = snake.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    final words = camel.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '';

    // よくある語の簡易変換
    final mapped = words.map((w) {
      switch (w) {
        case 'wake':
        case 'woke':
          return '起床';
        case 'sleep':
          return '就寝';
        case 'snooze':
          return 'スヌーズ';
        case 'cheer':
          return 'エール';
        case 'nudge':
        case 'remind':
        case 'reminder':
          return 'リマインド';
        case 'alarm':
        case 'ring':
          return 'アラーム';
        case 'post':
        case 'posted':
          return '投稿';
        case 'checkin':
        case 'check':
        case 'in':
          return 'チェックイン';
        // 追加: 設定・遅刻系
        case 'set':
        case 'schedule':
        case 'scheduled':
        case 'goal':
          return '設定';
        case 'late':
        case 'overdue':
        case 'delayed':
          return '遅刻';
        default:
          return w; // 未知語はそのまま（英語）
      }
    }).toList();

    // 先頭だけ使って短く
    final first = mapped.first;
    // 英単語のままなら先頭大文字化
    if (RegExp(r'^[a-z]+$').hasMatch(first)) {
      return first[0].toUpperCase() + first.substring(1);
    }
    return first;
  }

  // ===（参考）色テーブル：グリッド準拠 + cheerはラベンダー（将来参照用） ===
  Color _accentColor(String t) => switch (t) {
    'wake'  => const Color(0xFF7EE2A8), // Grid posted (green)
    'sleep' => const Color(0xFF5BA7FF), // Grid waiting (blue)
    'cheer' => const Color(0xFFBA68C8), // Lavender (distinct cheer)
    'snooze'=> const Color(0xFFFFC63A), // Grid snoozing/due (amber)
    'nudge' => const Color(0xFFFF6B6B), // Grid lateSuspicious (red)
    'reset' => const Color(0xFF737B87), // Grid noAlarm (grey)
    _       => const Color(0xFF90A4AE), // BlueGrey fallback
  };

  Color _accentBgColor(String t) => switch (t) {
    'wake'  => const Color(0xFF7EE2A8),
    'sleep' => const Color(0xFF5BA7FF),
    'cheer' => const Color(0xFFBA68C8),
    'snooze'=> const Color(0xFFFFC63A),
    'nudge' => const Color(0xFFFF6B6B),
    'reset' => const Color(0xFF737B87),
    _       => const Color(0xFF90A4AE),
  };
  // === バブル（塗り/枠/NEWバッジ） ===
  Widget _eventBubble({
    required String text,
    required Color borderColor,
    required Color fillColor,
    required Color textColor,
    required bool showNewBadge,
    required bool badgeOnRight,
    required LinearGradient gradient,
    required bool isLatest,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (isLatest)
          // 最新: 枠も塗りつぶしもグラデーション
          Container(
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(1.4), // 枠の太さ
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: gradient,        // 最新は中身もグラデ塗り
                borderRadius: BorderRadius.circular(12.6),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: textColor,        // 最新も白字に統一
                  fontSize: 14,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
        else
          // 過去: 枠のみ（単色ボーダー）、中身は透明
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.4),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: textColor,          // 過去は白字
                fontSize: 14,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

        if (showNewBadge)
          Positioned(
            left: -18,
            right: null,
            top: -18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white, // バッジ背景は白
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 1.4),
                boxShadow: [BoxShadow(color: borderColor.withOpacity(0.25), blurRadius: 6)],
              ),
              child: Text(
                'NEW',
                style: TextStyle(color: borderColor, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0),
              ),
            ),
          ),
      ],
    );
  }
}

// === 上部：猶予超過ストリップ（オプショナル） ===
class _OverdueStrip extends StatelessWidget implements PreferredSizeWidget {
  final String groupId;
  const _OverdueStrip({required this.groupId});

  @override
  Size get preferredSize => const Size.fromHeight(66);

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('groups').doc(groupId).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final overdue = (data?['overdueUids'] is List)
            ? List<String>.from(data!['overdueUids'])
            : const <String>[];
        if (overdue.isEmpty) {
          return Container(
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0x161FFFFFF),
              border: Border(
                top: BorderSide(color: Colors.white12, width: 0.0),
                bottom: BorderSide(color: Colors.white12, width: 0.5),
              ),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: const Text(
              '遅刻メンバーなし',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
            ),
          );
        }
        return Container(
          height: 66,
          decoration: const BoxDecoration(
            color: Color(0x161FFFFFF),
            border: Border(
              top: BorderSide(color: Colors.white12, width: 0.0),
              bottom: BorderSide(color: Colors.white12, width: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...overdue.map((uid) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: StreamBuilder<Map<String, Map<String, dynamic>>>(
                          stream: UserRepo().profilesByUids([uid]),
                          builder: (context, profSnap) {
                            final prof = profSnap.data?[uid];
                            final photo = prof?['photoUrl'] ?? prof?['photoURL'] ?? prof?['iconUrl'];
                            return Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.white24,
                                  backgroundImage: (photo is String && photo.isNotEmpty) ? NetworkImage(photo) : null,
                                  child: (photo is String && photo.isNotEmpty) ? null : const Icon(Icons.person, size: 16, color: Colors.white70),
                                ),
                                const SizedBox(width: 6),
                              ],
                            );
                          },
                        ),
                      )),
                    ],
                  ),
                ),
              ),
              // 「◯◯をみんなで起こそう！」（先頭名＋他人数）
              StreamBuilder<Map<String, Map<String, dynamic>>>(
                stream: UserRepo().profilesByUids(overdue),
                builder: (context, profSnap) {
                  final m = profSnap.data ?? {};
                  final names = <String>[];
                  for (final u in overdue) {
                    final n = (m[u]?['displayName'] as String?) ?? '';
                    if (n.isNotEmpty) names.add(n);
                  }
                  if (names.isEmpty) return const SizedBox.shrink();
                  final label = names.length == 1 ? names.first : '${names.first} 他${names.length - 1}名';
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '$label をみんなで起こそう！',
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// （未使用だが残しておく場合）しっぽ（菱形）
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