import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import 'notification_models.dart';
import 'notification_providers.dart';

/// 알림센터(`/notifications`). 본인 알림 리스트 + "모두 읽음".
/// 정본 B 카드형 톤. 기능/RPC 변경 없음 — notifications 테이블 읽기/읽음 UPDATE만.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadCountProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: 16,
        title: const Text('알림'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AppColors.line),
        ),
        actions: [
          if (unread > 0)
            _ReadAllButton(
              onTap: () async {
                await markAllNotificationsRead();
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(message: e.toString()),
        data: (items) {
          if (items.isEmpty) return const _EmptyState();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _NotificationCard(
              notification: items[i],
              onTap: () => _open(context, items[i]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _open(BuildContext context, AppNotification n) async {
    if (!n.read) {
      // 낙관적 처리: 스트림이 곧 갱신되므로 await 결과를 화면 전환에 묶지 않는다.
      await markNotificationRead(n.id);
    }
    if (!context.mounted) return;
    final jobId = n.jobId;
    if (jobId != null && jobId.isNotEmpty) {
      context.push('/job/$jobId');
    }
  }
}

/// 앱바 "모두 읽음" 텍스트 버튼.
class _ReadAllButton extends StatelessWidget {
  const _ReadAllButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: const Text(
          '모두 읽음',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: AppColors.blueInk,
          ),
        ),
      ),
    );
  }
}

/// 알림 카드: 유형 아이콘 칩 + 제목·본문 + 상대시각. 안읽음=연파랑 배경 + 점.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onTap});
  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final c = n.type.colors;
    final unread = !n.read;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: unread ? AppColors.primaryBg : AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: unread ? const Color(0xFFDCE8FB) : AppColors.line,
          ),
          boxShadow: unread ? const [] : AppShadows.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 유형 아이콘 칩.
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(n.type.icon, size: 20, color: c.fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        relativeTime(n.createdAt),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink3,
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 7),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (n.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      n.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink2,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none, size: 48, color: AppColors.ink3),
          SizedBox(height: 12),
          Text(
            '새 알림이 없어요.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.red),
            const SizedBox(height: 12),
            const Text(
              '알림을 불러오지 못했습니다.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.ink2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.ink3),
            ),
          ],
        ),
      ),
    );
  }
}
