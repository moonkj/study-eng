import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
import '../../data/pack_source.dart';
import '../../core/layout/adaptive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../toeic/toeic_target.dart' show pickToeicTarget;

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
          Text('설정', style: AppType.title1(weight: FontWeight.w700, letterSpacing: -0.5)),
          const SizedBox(height: AppSpace.lg),
          _Group(
            children: [
              _Item(
                icon: Icons.school_outlined,
                title: '내 레벨',
                value: level.label,
                onTap: () => context.push('/level-result'),
              ),
              _Item(icon: Icons.quiz_outlined, title: '레벨 다시 진단하기', onTap: () => context.push('/level-test')),
              _Item(
                icon: Icons.flag_outlined,
                title: '토스 목표',
                value:
                    '${st.toeicTarget.label} · ${st.toeicTarget.score}점${settings.toeicTarget == null ? ' (기본)' : ''}',
                onTap: () => pickToeicTarget(context, ref),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
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
          const SizedBox(height: AppSpace.md),
          _Group(children: [_ReminderItem(minutes: settings.reminderMinutes)]),
          const SizedBox(height: AppSpace.md),
          _Group(
            children: [
              _Item(
                icon: Icons.contrast_rounded,
                title: '화면 테마',
                value: themes[settings.theme] ?? themes['system'],
                onTap: () => _pick<String>(
                  context,
                  title: '화면 테마',
                  options: themes,
                  selected: settings.theme,
                  onSelect: (v) => ref.read(studyProvider.notifier).updateSettings(settings.copyWith(theme: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
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
const themes = {'system': '휴대폰 설정 따라', 'light': '밝게 (종이)', 'dark': '어둡게 (밤의 종이)'};
final speeds = <double, String>{0.8: '느리게', 1.0: '보통', 1.15: '조금 빠르게'};

void _pick<T>(
  BuildContext context, {
  required String title,
  required Map<T, String> options,
  required T selected,
  required void Function(T) onSelect,
}) {
  showModalBottomSheet<void>(
    useRootNavigator: true,
    context: context,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xl, AppSpace.md, AppSpace.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
              child: Text(title, style: AppType.headline(weight: FontWeight.w700)),
            ),
            for (final e in options.entries)
              ListTile(
                minTileHeight: 52,
                title: Text(e.value, style: AppType.body()),
                trailing: e.key == selected ? Icon(Icons.check_rounded, color: context.colors.penBlue) : null,
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
      padding: EdgeInsets.symmetric(vertical: AppSpace.xs),
      // 목록 항목의 터치 물결 효과가 카드 배경 위에 보이도록
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(indent: ActionRow.dividerIndent),
              children[i],
            ],
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
    return ActionRow(icon: icon, title: title, value: value, onTap: onTap, bordered: false);
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
          secondary: Icon(Icons.notifications_none_rounded, color: context.colors.penBlue),
          title: Text('아침 알림', style: AppType.body(weight: FontWeight.w500)),
          subtitle: Consumer(
            builder: (_, ref, _) {
              final blocked = ref.watch(reminderBlockedProvider);
              return Text(
                !on
                    ? '꺼짐'
                    : blocked
                    ? '휴대폰 설정에서 알림 권한이 꺼져 있어요'
                    : '매일 ${formatMinutes(minutes!)}',
                style: AppType.caption(color: on && blocked ? context.colors.error : context.colors.ink2),
              );
            },
          ),
          value: on,
          activeThumbColor: context.colors.card,
          activeTrackColor: context.colors.penBlue,
          onChanged: (v) => _set(context, ref, v ? (minutes ?? 7 * 60 + 30) : null),
        ),
        if (on)
          ListTile(
            minTileHeight: 52,
            contentPadding: const EdgeInsets.only(left: 72, right: AppSpace.lg),
            title: Text('알림 시각', style: AppType.callout()),
            trailing: Text(
              formatMinutes(minutes!),
              style: AppType.callout(weight: FontWeight.w600, color: context.colors.penBlue),
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
