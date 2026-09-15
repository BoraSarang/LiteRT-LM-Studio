# PLAN v25 — 조각 경계 공백 소실 수정 (macOS)

## 1. 목표

`**` 분할 후 조각별 파싱에서 경계 공백이 trim되어 붙어 보이는 버그 수정.
제보 2건: `궁금하네요.CMD` (뒤 공백 소실), `제가"서버가 중지됨"같은` (양쪽 소실).

## 2. 원인

`NativeMarkdown.styled` 67행이 조각마다 `AttributedString(markdown:)`을
옵션 없이 호출. 파서가 조각 앞뒤 공백을 제거.
같은 파일 `attributed()`는 `.inlineOnlyPreservingWhitespace`로 보존 중이라
`styled()`에만 옵션 누락된 상태.

## 3. 변경 (T-184)

* `styled()` 67행에 `inlineOnlyPreservingWhitespace` 옵션 추가 (1줄).
  `bodyText` 경유 전부(제목·목록·인용·문단·표셀·질문/응답)에 일괄 적용.
* 회귀 테스트 2건: 마침표 뒤 공백 1곳 + 따옴표 볼드 양쪽 공백.
* 버전 0.7.123.

## 4. 비범위

* `normalizeStrong` 안쪽 trim (의도대로, 유지).
* 스트리밍 중 `**` 미완성 마커 노출 (별도 후보, 이번 제외).
* `inlineText` dead code (손대지 않음).

## 5. 검증

* unit 99/99 목표 (97 기존 + 2 신규) + lint 신규 0 + `build macos` 설치·눈확인.
