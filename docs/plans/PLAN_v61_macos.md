# PLAN v61 — Tool Calling 표시 + 실행 (macOS, T-266~)

## S-0 스파이크 결과 (실측 확정, GO)

* serve SSE = OpenAI 표준: `delta.tool_calls[{index,id,type,function{name,arguments}}]`,
  `finish_reason: "tool_calls"`, 2턴째 `role: tool`+`tool_call_id` 접수 확인.
* describe FC:NO 모델도 tool_calls 방출 (게이팅은 찬스, 차단은 아님).
* thinking 서버 형상은 미확인 (지원 모델 없음) — `reasoning_content` 관용 파서로 대비.
* 네이티브 형상은 코드 확정 (Message channels+toolCalls, 자동실행 내장).

## S-1 표시 파이프 / S-2 실행 네이티브 / S-3 실행 서버 (PLAN_v61 본문 참조)
