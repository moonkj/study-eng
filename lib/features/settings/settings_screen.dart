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
    final level = ref.watch(studyProvider).profile.overall;
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
          const _Group(
            children: [
              _Item(icon: Icons.notifications_none_rounded, title: '아침 알림', value: '오전 7:30', soon: true),
              _Item(icon: Icons.record_voice_over_outlined, title: '발음 음성', value: '미국 영어', soon: true),
              _Item(icon: Icons.speed_rounded, title: '듣기 속도', value: '보통', soon: true),
            ],
          ),
          const SizedBox(height: 18),
          Text('알림·음성 설정은 다음 단계에서 연결돼요.', style: sans(12, color: AppColors.ink2)),
        ],
      ),
    );
  }
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
  const _Item({required this.icon, required this.title, this.value, this.onTap, this.soon = false});
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final bool soon;

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
          if (soon) ...[const SizedBox(width: 6), const Tag('준비 중', color: AppColors.ink2, background: AppColors.sand)],
        ],
      ),
      onTap: onTap,
    );
  }
}
