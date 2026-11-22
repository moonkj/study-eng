import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
import '../../data/pack_source.dart';
import '../../core/layout/adaptive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(studyProvider);
    final level = st.profile.overall;
    final settings = st.settings;
    return SafeArea(
      child: ListView(
        padding: readablePadding(context, maxWidth: 680),
        children: [
          Text('설정', style: sans(26, weight: FontWeight.w700, letterSpacing: -0.5)),
          const SizedBox(height: 16),
          _Group(
            children: [
              _Item(
                icon: Icons.school_outlined,
                title: '내 레벨',
                value: level.label,
                onTap: () => context.push('/level-result'),
              ),
              _Item(icon: Icons.quiz_outlined, title: '레벨 다시 진단하기', onTap: () => context.push('/level-test')),
            ],
          ),
          const SizedBox(height: 12),
          _Group(
            children: [
              _Item(
                icon: Icons.auto_awesome_outlined,
                title: '학습 내용',
                value: ref.watch(packSourceProvider) == null
                    ? '기본 샘플 (서버 미연결)'
                    : (st.pack.fromClaude ? 'Claude 맞춤 생성' : '기본 샘플'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Group(children: [_ReminderItem(minutes: settings.reminderMinutes)]),
          const SizedBox(height: 12),
          _Group(
            children: [
              _Item(
                icon: Icons.record_voice_over_outlined,
                title: '발음 음성',
                value: voices[settings.voice] ?? settings.voice,
                onTap: () => _pick<String>(
                  context,
                  title: '발음 음성',
                  options: voices,
                  selected: settings.voice,
                  onSelect: (v) {
                    ref.read(studyProvider.notifier).updateSettings(settings.copyWith(voice: v));
                    ref.read(sayProvider)("I've been meaning to call you.");
                  },
                ),
              ),
              _Item(
                icon: Icons.speed_rounded,
                title: '듣기 속도',
                value: speeds[settings.speed] ?? '${settings.speed}배',
                onTap: () => _pick<double>(
                  context,
                  title: '듣기 속도',
                  options: speeds,
                  selected: settings.speed,
                  onSelect: (v) {
                    ref.read(studyProvider.notifier).updateSettings(settings.copyWith(speed: v));
                    ref.read(sayProvider)("I've been meaning to call you.");
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const voices = {'en-US': '미국 영어', 'en-GB': '영국 영어'};
final speeds = <double, String>{0.8: '느리게', 1.0: '보통', 1.15: '조금 빠르게'};

void _pick<T>(
  BuildContext context, {
  required String title,
  required Map<T, String> options,
  required T selected,
  required void Function(T) onSelect,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(title, style: sans(17, weight: FontWeight.w700)),
            ),
            for (final e in options.entries)
              ListTile(
                minTileHeight: 52,
                title: Text(e.value, style: sans(15)),
                trailing: e.key == selected ? const Icon(Icons.check_rounded, color: AppColors.penBlue) : null,
                onTap: () {
                  onSelect(e.key);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PaperCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      // 목록 항목의 터치 물결 효과가 카드 배경 위에 보이도록
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(indent: 52), children[i]],
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.title, this.value, this.onTap});
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 56,
      leading: Icon(icon, color: AppColors.penBlue),
      title: Text(title, style: sans(15, weight: FontWeight.w500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null) Text(value!, style: sans(14, color: AppColors.ink2)),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AppColors.ink2),
        ],
      ),
      onTap: onTap,
    );
  }
}

String formatMinutes(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final period = h < 12 ? '오전' : '오후';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$period $h12:${m.toString().padLeft(2, '0')}';
}

/// 아침 알림 켜기/끄기 + 시각 고르기
class _ReminderItem extends ConsumerWidget {
  const _ReminderItem({required this.minutes});
  final int? minutes;

  Future<void> _set(BuildContext context, WidgetRef ref, int? value) async {
    final ok = await ref.read(studyProvider.notifier).setReminder(value);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('알림을 켜지 못했어요. 휴대폰 설정에서 알림 권한을 허용해 주세요.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = minutes != null;
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.notifications_none_rounded, color: AppColors.penBlue),
          title: Text('아침 알림', style: sans(15, weight: FontWeight.w500)),
          subtitle: Consumer(
            builder: (_, ref, _) {
              final blocked = ref.watch(reminderBlockedProvider);
              return Text(
                !on
                    ? '꺼짐'
                    : blocked
                    ? '휴대폰 설정에서 알림 권한이 꺼져 있어요'
                    : '매일 ${formatMinutes(minutes!)}',
                style: sans(13, color: on && blocked ? AppColors.error : AppColors.ink2),
              );
            },
          ),
          value: on,
          activeThumbColor: AppColors.card,
          activeTrackColor: AppColors.penBlue,
          onChanged: (v) => _set(context, ref, v ? (minutes ?? 7 * 60 + 30) : null),
        ),
        if (on)
          ListTile(
            minTileHeight: 52,
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: Text('알림 시각', style: sans(14)),
            trailing: Text(
              formatMinutes(minutes!),
              style: sans(14, weight: FontWeight.w600, color: AppColors.penBlue),
            ),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: minutes! ~/ 60, minute: minutes! % 60),
                helpText: '알림 받을 시각',
              );
              if (picked != null && context.mounted) await _set(context, ref, picked.hour * 60 + picked.minute);
            },
          ),
      ],
    );
  }
}
