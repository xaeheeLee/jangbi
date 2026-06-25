import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_bottom_nav.dart';
import '../../core/widgets/brand_logo.dart';
import '../auth/auth_providers.dart';
import '../calendar/calendar_screen.dart';
import '../dispatch/dispatch_screen.dart';
import '../jobs/jobs_list_screen.dart';
import '../profile/profile_screen.dart';
import '../wallet/wallet_screen.dart';

/// 하단 5탭 셸. 일감 / 배차 / 캘린더 / 지갑 / MY.
/// 각 탭 본문은 P2 이후 구현 — 현재는 placeholder.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  // PREVIEW_TAB: 개발용 초기 탭 주입(스크린샷). 기본 0(일감).
  int _index = const int.fromEnvironment('PREVIEW_TAB');

  static const _tabs = <AppNavItem>[
    AppNavItem('일감', Icons.work_outline, Icons.work),
    AppNavItem('배차', Icons.local_shipping_outlined, Icons.local_shipping),
    AppNavItem('캘린더', Icons.calendar_today_outlined, Icons.calendar_today),
    AppNavItem('지갑', Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet),
    AppNavItem('MY', Icons.person_outline, Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    final suspended = ref.watch(membershipStatusProvider) == 'suspended';
    final tab = _tabs[_index];
    final isJobsTab = _index == 0;
    final isCalendarTab = _index == 2;
    // 캘린더 탭: 중앙 정렬 타이틀 + 알림 벨(목업 crop_calendar 기준).
    final showBell = isJobsTab || isCalendarTab;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        // 일감 탭: 소형 로고 + "일감". 그 외: 탭 라벨.
        titleSpacing: 16,
        centerTitle: isCalendarTab,
        title: isJobsTab
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LogoMark(size: 25),
                  SizedBox(width: 8),
                  Text('일감'),
                ],
              )
            : Text(tab.label),
        // 하단 1px line 구분선(.appbar border-bottom).
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AppColors.line),
        ),
        actions: showBell
            ? [
                _NotificationButton(onTap: () {}),
                const SizedBox(width: 8),
              ]
            : null,
      ),
      body: Column(
        children: [
          if (suspended) const _SuspendedBanner(),
          Expanded(
            child: switch (_index) {
              0 => const JobsListScreen(),
              1 => const DispatchScreen(),
              2 => const CalendarScreen(),
              3 => const WalletScreen(),
              4 => const ProfileScreen(),
              _ => _Placeholder(label: tab.label),
            },
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        items: _tabs,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// 앱바 알림 버튼(.iconbtn): 38x38, 우상단 빨강 점(.dot).
class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.notifications_none, size: 22, color: AppColors.ink),
            Positioned(
              top: 8,
              right: 9,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: AppColors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.card, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
