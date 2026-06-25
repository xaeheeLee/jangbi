import 'package:flutter/material.dart';

/// 목업(index.html) CSS 변수에서 1:1 추출한 그림자 토큰.
/// 색상 하드코딩 금지 원칙과 동일하게, BoxShadow 도 이 토큰만 사용한다.
abstract final class AppShadows {
  /// --shadow: 0 1px 2px rgba(16,24,40,.04), 0 10px 28px rgba(16,24,40,.07)
  static const card = <BoxShadow>[
    BoxShadow(
      color: Color(0x0A101828), // rgba(16,24,40,.04)
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x12101828), // rgba(16,24,40,.07)
      blurRadius: 28,
      offset: Offset(0, 10),
    ),
  ];

  /// --shadow-sm: 0 1px 2px rgba(16,24,40,.05), 0 4px 14px rgba(16,24,40,.05)
  static const sm = <BoxShadow>[
    BoxShadow(
      color: Color(0x0D101828), // rgba(16,24,40,.05)
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x0D101828), // rgba(16,24,40,.05)
      blurRadius: 14,
      offset: Offset(0, 4),
    ),
  ];

  /// --shadow-lift: 0 10px 22px rgba(0,47,108,.18) (네이비 버튼/FAB).
  static const lift = <BoxShadow>[
    BoxShadow(
      color: Color(0x2E002F6C), // rgba(0,47,108,.18)
      blurRadius: 22,
      offset: Offset(0, 10),
    ),
  ];

  /// 빨강 버튼: 0 10px 22px rgba(220,38,38,.26)
  static const liftRed = <BoxShadow>[
    BoxShadow(
      color: Color(0x42DC2626), // rgba(220,38,38,.26)
      blurRadius: 22,
      offset: Offset(0, 10),
    ),
  ];

  /// 흰 버튼(잔액카드 충전): 0 4px 14px rgba(0,0,0,.14)
  static const whiteBtn = <BoxShadow>[
    BoxShadow(
      color: Color(0x24000000), // rgba(0,0,0,.14)
      blurRadius: 14,
      offset: Offset(0, 4),
    ),
  ];

  /// 로고 배지: 0 14px 34px rgba(0,12,40,.22) (inset white 는 별도 border 로 표현).
  static const logoBadge = <BoxShadow>[
    BoxShadow(
      color: Color(0x38000C28), // rgba(0,12,40,.22)
      blurRadius: 34,
      offset: Offset(0, 14),
    ),
  ];

  /// 떠있는 탭바: 0 14px 34px rgba(16,24,40,.16)
  static const floatTab = <BoxShadow>[
    BoxShadow(
      color: Color(0x29101828), // rgba(16,24,40,.16)
      blurRadius: 34,
      offset: Offset(0, 14),
    ),
  ];
}
