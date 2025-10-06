//ui/group_calendar_scree.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/calendar_repo.dart';
import '../models/group_calendar_event.dart';
import '../models/group_summary.dart';
import 'widgets/group_bottom_nav.dart';

class GroupCalendarScreen extends StatefulWidget {
  final String currentGroupId;
  final String myUid;
  final List<GroupSummary> availableGroups;
  final VoidCallback onOpenTimeline;

  const GroupCalendarScreen({
    super.key,
    required this.currentGroupId,
    required this.myUid,
    required this.availableGroups,
    required this.onOpenTimeline,
  });

  @override
  State<GroupCalendarScreen> createState() => _GroupCalendarScreenState();
}

class _GroupCalendarScreenState extends State<GroupCalendarScreen> {
  final CalendarRepo _repo = CalendarRepo();
  late DateTime _selectedDate;
  TimeOfDay? _selectedTime;
  late Set<String> _selectedGroupIds;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _selectedGroupIds = {widget.currentGroupId};
  }

  Map<String, GroupSummary> get _groupMap => {for (final g in widget.availableGroups) g.id: g};

  Future<void> _pickTime() async {
    final initial = _selectedTime ?? const TimeOfDay(hour: 6, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _saveEvent() async {
    final time = _selectedTime;
    if (time == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('起床目標時間を選択してください')));
      return;
    }
    final date = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final scheduled = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    try {
      await _repo.saveEvent(
        date: date,
        timeOfDay: time,
        groupIds: _selectedGroupIds.toList(),
        createdByGroupId: widget.currentGroupId,
        createdByUid: widget.myUid,
      );
      if (!mounted) return;
      final formatter = DateFormat('yyyy/MM/dd HH:mm');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('予定を保存しました (${formatter.format(scheduled)})')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final firstDate = DateTime(today.year, today.month, today.day);
    final lastDate = DateTime(today.year + 1, today.month, today.day);
    final groupMap = _groupMap;

    return Scaffold(
      appBar: AppBar(title: const Text('カレンダー')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CalendarDatePicker(
                    initialDate: _selectedDate.isBefore(firstDate) ? firstDate : _selectedDate,
                    firstDate: firstDate,
                    lastDate: lastDate,
                    onDateChanged: (value) => setState(() => _selectedDate = DateTime(value.year, value.month, value.day)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('参加グループ', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: widget.availableGroups.map((group) {
                    final checked = _selectedGroupIds.contains(group.id);
                    return CheckboxListTile(
                      title: Text(group.name),
                      value: checked,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedGroupIds.add(group.id);
                          } else {
                            _selectedGroupIds.remove(group.id);
                            if (_selectedGroupIds.isEmpty) {
                              _selectedGroupIds.add(widget.currentGroupId);
                            }
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.access_time),
                  title: Text(_selectedTime == null
                      ? '起床目標時間を設定'
                      : '起床目標: ${_selectedTime!.format(context)}'),
                  subtitle: Text('アラーム設定の日付: ${DateFormat('yyyy/MM/dd').format(_selectedDate)}'),
                  trailing: FilledButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: const Text('時間を選択'),
                    onPressed: _pickTime,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: (_selectedGroupIds.isNotEmpty && _selectedTime != null) ? _saveEvent : null,
                child: const Text('予定を保存'),
              ),
              const SizedBox(height: 24),
              Text('選択した日の予定', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              StreamBuilder<List<GroupCalendarEvent>>(
                stream: _repo.eventsForGroupOnDate(widget.currentGroupId, _selectedDate),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final events = snapshot.data ?? const <GroupCalendarEvent>[];
                  if (events.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('この日に登録された予定はありません。'),
                    );
                  }
                  return Column(
                    children: events.map((event) {
                      final timeText = DateFormat('HH:mm').format(event.alarmDateTime);
                      final fullDate = DateFormat('yyyy/MM/dd HH:mm').format(event.alarmDateTime);
                      final creator = groupMap[event.createdByGroupId]?.name ?? event.createdByGroupId;
                      final targetNames = event.groupIds.map((id) => groupMap[id]?.name ?? id).join('、');
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.alarm_on),
                          title: Text('$fullDate 起床目標'),
                          subtitle: Text('対象グループ: $targetNames\n作成グループ: $creator'),
                          trailing: Text(timeText),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: GroupBottomNavigation(
        active: GroupNavItem.calendar,
        onGrid: () {
          final navigator = Navigator.of(context);
          navigator.popUntil((route) => route.settings.name == null || route.settings.name == 'grid');
        },
        onTimeline: widget.onOpenTimeline,
      ),
    );
  }
}