# PLAN v18 — 준비 문구 정정 + 스트리밍 묶음 갱신 (macOS, T-148)

## 1. 목표

"엔진 준비 중" 오해 문구 정정 + 토큰당 전체 리렌더로 인한 앱 CPU 완화.

## 2. 분석

* `preparing`은 매 전송 켜짐 → 첫 토큰에 꺼짐. 의미는 "첫 토큰 대기 중".
  엔진 초기화는 모델당 1회 (`prepare` early-return, `release` 호출처 없음).
* 토큰마다 `messages[idx].text` 대입 → @Published → ContentView 전체 본문 재계산 +
  Markdown JS·스크롤 연쇄. 0.1초 묶음으로 횟수 절감 (TTFT·완료 로직 불변).

## 3. 변경

1. `MessageBubbles.swift`: "엔진 준비 중… 첫 요청은 수 분…" → "첫 토큰 대기 중…".
2. `ChatStore.swift`: `shouldFlushText` 순수 헬퍼 + SSE 루프 묶음 갱신 + 종료 후 최종 반영.
3. `ChatStore+Native.swift`: 네이티브 루프 동일 적용.
4. 테스트: `testShouldFlushText` 3항 (87종 목표).
5. 문서: TODO T-148 + CHANGELOG 0.7.95 + 본 PLAN.

## 4. 검증

* unit + lint 신규 0 + `build macos` 설치.
* 눈확인: 스트리밍 부드러움 유지(10Hz), 커서·추종·푸터 정상, tok/s·TTFT 정상 기록.
  손대지 않은 것: 히스토리 전체 재전달(prefill 비용), Debug 빌드 오버헤드.
