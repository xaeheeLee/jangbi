import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_providers.dart';
import '../dispatch/dispatch_screen.dart';
import '../jobs/jobs_list_screen.dart';

/// 하단 5탭 셸. 일감 / 배차 / 캘린더 / 지갑 / MY.
/// 각 탭 본문은 P2 이후 구현 — 현재는 placeholder.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _tabs = <_TabDef>[
    _TabDef('일감', Icons.work_outline, Icons.work),
    _TabDef('배차', Icons.local_shipping_outlined, Icons.local_shipping),
    _TabDef('캘린더', Icons.calendar_today_outlined, Icons.calendar_today),
    _TabDef('지갑', Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet),
    _TabDef('MY', Icons.person_outline, Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    final suspended = ref.watch(membershipStatusProvider) == 'suspended';
    final tab = _tabs[_index];
    final isJobsTab = _index == 0;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(isJobsTab ? '일감' : tab.label)),
      body: Column(
        children: [
          if (suspended) const _SuspendedBanner(),
          Expanded(
            child: switch (_index) {
              0 => const JobsListScreen(),
              1 => const DispatchScreen(),
              _ => _Placeholder(label: tab.label),
            },
          ),
        ],
      ),
      bottomNavigationBar: SizedBox(
        height: AppTheme.tabBarHeight + MediaQuery.of(context).padding.bottom,
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.card,
          selectedItemColor: AppColors.navy,
          unselectedItemColor: AppColors.ink3,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
          items: [
            for (final t in _tabs)
              BottomNavigationBarItem(
                icon: Icon(t.icon),
                activeIcon: Icon(t.activeIcon),
                label: t.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _TabDef {
  const _TabDef(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _SuspendedBanner extends StatelessWidget {
  const _SuspendedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.revBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.revFg, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '준회원(잔액 부족) 상태입니다. 포인트를 충전하면 정회원 기능이 복구됩니다.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.revFg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.construction, size: 48, color: AppColors.ink3),
          const SizedBox(height: 12),
          Text(
            '$label · 준비 중',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink2,
            ),
          ),
        ],
      ),
    );
  }
}
