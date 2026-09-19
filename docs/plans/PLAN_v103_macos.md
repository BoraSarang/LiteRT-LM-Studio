# PLAN_v103 — 생성 설정 입력 컨트롤 교체 (T-329, macOS)

> 사용자 결정: 상위 K 1~100 (0 제외, 엔진 유효 범위 유지).

## 원인

* Max 토큰·시드·시스템 프롬프트는 `TextField`이나 스타일 미지정이라
  List 행에서 일반 텍스트처럼 보임.
* 상위 K는 `Stepper(1...256)` + 값 텍스트.

## 변경 (`generateSectionBody` 내부만, 값·기본값·로그 불변)

1. 3종 `TextField`에 `.textFieldStyle(.roundedBorder)` 추가.
2. 상위 K → `Slider(1...100, step: 1)` + 우측 값 표시.
   기존 100 초과값은 Binding에서 100으로 클램프.
3. 시스템 프롬프트 → `TextEditor` + `frame(height: 64)`.

## 검증

* 회귀 test + lint 신규 0 + build + 눈확인 (입력·슬라이더·값 표시).
