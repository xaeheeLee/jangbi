import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 하단 탭 정의.
class AppNavItem {
  const AppNavItem(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// 목업 .tabbar/.tab 1:1 커스텀 탭바.
/// 높이 64, 흰배경, 상단 border 1px line, padding-bottom 6.
/// 탭: 세로정렬 gap 3 / 아이콘 22 / 라벨 10px·w700 /
/// 비활성 ink-3, 활성 navy + 상단 인디케이터 바(가로 22·높이 3·navy·하단 라운드).
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.line, width: 1)),
      ),
      padding: EdgeInsets.only(bottom: 6 + bottomInset),
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _Tab(
                  item: items[i],
                  active: i == currentIndex,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.active, required this.onTap});
  final AppNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.navy : AppColors.ink3;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 상단 인디케이터 바(활성 탭).
          if (active)
            const Align(
              alignment: Alignment.topCenter,
              child: _Indicator(),
            ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(active ? item.activeIcon : item.icon, size: 22, color: color),
              const SizedBox(height: 3),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 3,
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(4)),
      ),
    );
  }
}
