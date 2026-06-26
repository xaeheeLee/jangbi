import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';

/// 일감 상세 상단 지도.
///
/// - `Env.hasKakaoKey` 이면 카카오맵(webview 기반)을 위/경도 중심으로 표시하고
///   해당 좌표에 마커를 찍는다. 좌표가 없으면 서울 시청 기본 좌표를 사용한다.
/// - 키가 없으면 기존 placeholder(가짜 지도 + "카카오맵" 칩 + 핀)를 유지한다.
///   → 키 발급 전에도 빌드/동작이 깨지지 않게 한다.
class JobMap extends StatelessWidget {
  const JobMap({super.key, this.lat, this.lng, this.label});

  final double? lat;
  final double? lng;

  /// 지도 칩/마커 라벨(지역명 등). 비어 있어도 동작.
  final String? label;

  // 서울시청 기본 좌표(좌표 미제공 시 fallback).
  static const _defaultLat = 37.5665;
  static const _defaultLng = 126.9780;

  static const _height = 188.0;

  @override
  Widget build(BuildContext context) {
    if (!Env.hasKakaoKey) {
      return const _MapPlaceholder();
    }
    final center = LatLng(lat ?? _defaultLat, lng ?? _defaultLng);
    final markerLabel = label ?? '';
    return SizedBox(
      height: _height,
      child: KakaoMap(
        center: center,
        currentLevel: 4,
        onMapCreated: (KakaoMapController controller) async {
          await controller.addMarker(
            markers: [
              Marker(
                markerId: 'job',
                latLng: center,
                infoWindowContent: markerLabel,
                infoWindowFirstShow: markerLabel.isNotEmpty,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 키 미설정 시 보여주는 placeholder(.map): 회녹색 배경 + 블록/도로 + 핀 + 칩.
class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: JobMap._height,
      color: AppColors.mapBg,
      child: Stack(
        children: [
          Positioned(
              left: -12, top: 14, child: _block(92, 58, const Color(0xFFDDE7DC))),
          Positioned(
              right: 16, top: 8, child: _block(78, 50, const Color(0xFFE6E3D9))),
          Positioned(
              left: 34, bottom: 12, child: _block(72, 46, const Color(0xFFE6E3D9))),
          Positioned(
              right: -10, bottom: 20, child: _block(94, 60, const Color(0xFFDDE7DC))),
          Positioned(
              left: 0, right: 0, top: 86, child: Container(height: 13, color: Colors.white)),
          Positioned(
              top: 0, bottom: 0, left: 124, child: Container(width: 12, color: Colors.white)),
          const Align(
            alignment: Alignment(0, -0.1),
            child: _MapPin(),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(7),
                boxShadow: AppShadows.sm,
              ),
              child: const Text('카카오맵 · 지도는 키 설정 후 표시',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _block(double w, double h, Color c) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(3),
        ),
      );
}

/// 지도 핀(.pin): 회청 티어드롭 + 흰 점.
class _MapPin extends StatelessWidget {
  const _MapPin();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398, // 45deg
      child: Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          color: Color(0xFF3B4456),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(15),
            topRight: Radius.circular(15),
            bottomLeft: Radius.circular(15),
            bottomRight: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
                color: Color(0x47000000),
                blurRadius: 12,
                offset: Offset(0, 6)),
          ],
        ),
        child: Center(
          child: Transform.rotate(
            angle: -0.785398,
            child: Container(
              width: 11,
              height: 11,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
