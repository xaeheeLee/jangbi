import 'package:flutter/material.dart';

/// 회원가입 시 제출하는 서류 5종 (기능명세 기준 라벨/순서).
enum DocType {
  businessReg('business_reg', '사업자등록증', '필수', Icons.business_outlined),
  license('license', '건설기계조종사면허', '필수', Icons.badge_outlined),
  insurance('insurance', '자동차보험증권', '필수', Icons.verified_user_outlined),
  vehicleReg('vehicle_reg', '차량등록증', '필수', Icons.directions_car_outlined),
  bankbook('bankbook', '통장 사본', '인출 계좌 확인용', Icons.account_balance_outlined);

  const DocType(this.code, this.label, this.meta, this.icon);

  /// DB/Storage 식별자 (snake_case).
  final String code;

  /// 화면 표기 문서명.
  final String label;

  /// 보조 설명(필수 여부 등).
  final String meta;

  /// 행 아이콘.
  final IconData icon;
}

/// 사용자가 로컬에서 선택한 서류(아직 업로드 전).
class PickedDoc {
  const PickedDoc({required this.path, required this.fileName});

  final String path;
  final String fileName;

  /// 확장자(소문자, 점 제외). 없으면 'jpg' 폴백.
  String get ext {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return 'jpg';
    return fileName.substring(dot + 1).toLowerCase();
  }
}
