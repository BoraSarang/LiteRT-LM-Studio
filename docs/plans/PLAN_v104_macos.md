# PLAN_v104 — 대화 목차 후속칩 스타일 (T-330, macOS)

> 사용자 결정: 전체 표시 + 패널 내 스크롤.

## 변경 (ChatOutlineView.swift 확장 패널만)

* 행: 캡슐 (`padding h12/v7` + `DSColor.primary` 0.12 + `Capsule`),
  후속 칩과 동일. 바깥 반투명 카드 제거.
* `ScrollView` + `maxHeight 400` (100개도 화면 안).
* 후속 칩 배경도 `DSColor.primary`로 통일.
* 추출 규칙·호버·점프·축소바 불변.

## 검증

* 기존 outline unit 회귀 + lint + build + 눈확인.
