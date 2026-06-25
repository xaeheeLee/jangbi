import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../auth/auth_providers.dart';
import 'dispatch_models.dart';
import 'dispatch_providers.dart';
import 'widgets/application_card.dart';
import 'widgets/ticket_card.dart';

/// 배차 탭 본문(목업 ⑤ 배차 현황). 3영역:
/// ① 지정배차 수신 배너 ② 내 배차권 ③ 내 지원/매칭 현황.
class DispatchScreen extends ConsumerWidget {
  const DispatchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) {
      return const _SignedOut();
    }

    final designations = ref.watch(incomingDesignationsProvider);
    final available = ref.watch(availableTicketsProvider);
    final used = ref.watch(usedTicketsProvider);
    final apps = ref.watch(myApplicationsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(incomingDesignationsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          // ① 지정배차 수신.
          ...designations.maybeWhen(
            data: (jobs) => [
              for (final j in jobs) ...[
                DesignationBanner(
                  job: j,
                  onTap: () => context.push('/job/${j.id}'),
                ),
                const SizedBox(height: 10),
              ],
            ],
            orElse: () => const [],
          ),

          // ② 내 배차권.
          const _SectionHead(title: '내 배차권', icon: Icons.confirmation_number_outlined),
          available.when(
            loading: () => const _LoadingBox(),
            error: (e, _) => _ErrorBox(message: e.toString()),
            data: (tickets) {
              if (tickets.isEmpty) {
                return const _EmptyBox(
                  icon: Icons.confirmation_number_outlined,
                  text: '사용 가능한 우선배차권이 없습니다.\n사진 인증·지정배차 보상으로 받을 수 있어요.',
                );
              }
              return Column(
                children: [
                  _TicketSummary(count: tickets.length),
                  const SizedBox(height: 10),
                  for (final t in tickets) ...[
                    TicketCard(ticket: t),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),

          // 사용 이력(접기).
          ...used.maybeWhen(
            data: (tickets) => tickets.isEmpty
                ? const <Widget>[]
                : [_UsedTicketsTile(tickets: tickets)],
            orElse: () => const <Widget>[],
          ),

          const SizedBox(height: 18),

          // ③ 내 지원/매칭 현황.
          const _SectionHead(title: '내 지원·매칭 현황', icon: Icons.local_shipping_outlined),
          apps.when(
            loading: () => const _LoadingBox(),
            error: (e, _) => _ErrorBox(message: e.toString()),
            data: (list) {
              if (list.isEmpty) {
                return const _EmptyBox(
                  icon: Icons.inbox_outlined,
                  text: '지원한 일감이 없습니다.\n일감 탭에서 지원하면 여기서 진행 상황을 볼 수 있어요.',
                );
              }
              return Column(
                children: [
                  for (final a in list) ...[
                    ApplicationCard(
                      application: a,
                      onTap: () => context.push('/job/${a.jobId}'),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TicketSummary extends StatelessWidget {
  const _TicketSummary({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF1EC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFBD5C9)),
      ),
      child: Row(
        children: [
          const Icon(Icons.confirmation_number, size: 20, color: AppColors.red),
          const SizedBox(width: 8),
          const Text(
            '보유 우선배차권',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink2,
            ),
          ),
          const Spacer(),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$count'),
                const TextSpan(
                  text: '장',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.red,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsedTicketsTile extends StatelessWidget {
  const _UsedTicketsTile({required this.tickets});
  final List<PriorityTicket> tickets;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 4),
        title: Text(
          '사용·만료 이력 ${tickets.length}건',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink3,
          ),
        ),
        children: [
          for (final t in tickets) ...[
            TicketCard(ticket: t),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.navy),
          const SizedBox(width: 7),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBox extends StatelessWidget {
  const _LoadingBox();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: AppColors.ink3),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink2,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 30, color: AppColors.red),
          const SizedBox(height: 8),
          const Text(
            '불러오지 못했습니다.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: AppColors.ink3),
          ),
        ],
      ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.lock_outline, size: 44, color: AppColors.ink3),
          SizedBox(height: 12),
          Text(
            '로그인 후 배차 현황을 확인할 수 있습니다.',
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