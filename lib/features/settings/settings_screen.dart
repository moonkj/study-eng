import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/study_controller.dart';
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
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
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
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(indent: 52), children[i]],
        ],
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
