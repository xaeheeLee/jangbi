import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/theme/app_colors.dart';

/// Phase 0 임시 홈. 골격 확인용 — P1에서 회원가입/로그인/일감 화면으로 대체된다.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = Env.isSupabaseConfigured;
    return Scaffold(
      appBar: AppBar(title: const Text('전중배')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction, size: 64, color: AppColors.primary),
            const SizedBox(height: 16),
            const Text(
              '전국중장비배차',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              configured
                  ? 'Supabase 연결 설정됨 ✓'
                  : 'Supabase 미설정 — dart-define 필요',
              style: TextStyle(
                color: configured ? AppColors.success : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
