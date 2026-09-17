# PLAN v67 — 추론 타이틀 정렬 + 추론 자동 스크롤 (T-276)

## 변경

* `ThinkingBlockView`: 타이틀 박스 밖으로 (좌단 본문 시작점 일치), 내용은 기존 박스 유지.
* `followStreamedText`: thinking 변경 트리거 + 본문+추론 합산 길이 판정.

## 검증

* unit 유지, lint 0, build 2회, 눈확인 (정렬·추종·휠정지·접힘).
