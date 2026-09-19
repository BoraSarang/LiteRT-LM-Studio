# session-2026-09-19-macos (8줄 요약)

1. T-351~T-353 커밋 `0ab3f03`: 웹 검색 wigolo→Exa REST 교체 + 라이브 크롤 + 1턴 병렬 도구. 테스트 306/306, lint 신규 0, build OK.
2. T-352: `api.exa.ai/search`(`contents.highlights`)·`/contents`(text) Bearer, 파서 `parseExaSearch`/`parseExaContents`, 등록 게이트 바이너리→API 키, 설정 도구 탭 Exa 키 필드+`dashboard.exa.ai` 링크+실검색 테스트. WigoloManager/WigoloSupport 삭제, 배너·데몬·설치 UI 정리(pbxproj 포함).
3. T-353: Exa 기본 캐시가 GitHub 릴리스 페이지를 v0.16.1에서 멈춤(실측, 실제 v0.17.1) → 요청에 `maxAgeHours:0` 라이브 크롤 강제로 해결. 사용자 눈확인 통과. 요청 본문 순수 `searchBody`/`contentsBody` 분리.
4. T-351: 시스템 프롬프트 `[도구 병렬 규칙]`+본문 `parallel_tool_calls: true`(기존 runTurnCalls 루프 재사용). curl로 1응답 멀티콜 확인. UI 눈확인(1턴 2도구)은 미완.
5. 이전 마감 유지: T-346~T-350, T-347 실측, P2-6 MTP=ON 마감.
6. 참고: Exa `maxAgeHours:0`은 항상 라이브 크롤이라 호출 지연·비용이 늘 수 있음(정확도 우선 결정). 키는 UserDefaults `exaApiKey`(평문, Keychain 이관은 후속 후보).
7. 미검증/후보: T-351 병렬 눈확인, Exa 키 Keychain 이관, 모델이 본문 무시 시 시스템 프롬프트 `[1번 페이지 본문] 우선` 보강.
8. 규칙: main 직접 push 금지, 파괴적 변경 확인, 한국어.
