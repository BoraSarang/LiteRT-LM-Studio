# session-2026-09-17-macos — T-291 후속질문 LLM 호출 전환

1. 무엇을: 키워드 휴리스틱 → 응답 완료 후 LLM 1회 lazy 호출로 맥락 있는 3개 제안.
   로딩 스켈레톤→도착 시 교체, 실패 시 기존 휴리스틱 조용히 폴백. 현재 채팅 경로 그대로.
2. 플랫폼: macOS 단일, SwiftUI만, xcodebuild만. 기존 파일만 수정 (pbxproj 불필요).
3. 빌드+PERF+CACHE: unit 238/238 (신규 10건: 파서·프롬프트·질문추출+종단), lint 신규 0건(기준선 3건),
   build SUCCEEDED+설치·실행. 실측 로그로 실동작 확정 (완료 3개×5회, KV 재사용 유지).
4. 남은TODO: 당시 T-270·T-289·T-215 미완.
5. 전달로그: no-op edit 병합 사고 1건 (`keywords` 본문 고아화) → 즉시 복원·빌드 확인.
6. 문서갱신: PLAN_v80+T-291 완료+DESIGN+CHANGELOG+사용설명서 2장 1행.
7. 큐상태: 미커밋 유지.
8. E2E: 해당 없음.

---

# session-2026-09-17-macos — T-292 후속질문 선행 생성 (2건째)

1. 무엇을: 서버 route만 스트리밍 중 300자 도달 시 선행 호출+완료 시 드리프트 판정(유지/재호출).
   네이티브는 Engine 동시 추론 미검증으로 겹치기 기각, 완료 후 즉시+작업 축소(Q 1000·A 800·max 100).
2. 플랫폼: macOS 단일, SwiftUI만, xcodebuild만. 기존 파일만 수정 (pbxproj 불필요).
3. 빌드+PERF+CACHE: unit 242/242 (신규 4건), lint 신규 0건(기준선 3건), build SUCCEEDED+설치·실행.
   PERF: 네이티브 후속 작업량 축소, 서버는 스트리밍과 중첩. CACHE 영향 없음.
4. 남은TODO: T-270·T-289·T-215 미완. 눈확인 대기(서버): 스트리밍 중 선행 요청→완료 즉시 칩/드리프트 재호출.
   네이티브 체감 단축분은 실측 후 판단.
5. 전달로그: 테스트가 실제 버그 포착 (`finalize` 재호출이 `request` 중복 가드에 차단) → 재호출 전 칩 비움으로 수정 후 통과.
   `Engine` actor·`createConversation` 직렬 확인, C 병렬 추론 문서는 전무.
6. 문서갱신: PLAN_v81+T-292 완료+DESIGN 후속칩절+CHANGELOG Unreleased. error_message_ko.json 변경 없음.
7. 큐상태: 미커밋 유지 (T-290·T-291·T-292 공존, 지시 전 커밋 금지).
8. E2E: 해당 없음.

---

# session-2026-09-17-macos — T-293 데몬 카드 삭제 + T-294 새소식 앱 저장소 (3건째)

1. 무엇을: T-293 인스펙터 데몬 히어로 카드 route 무관 완전 삭제 (캡션·차트·route 파라미터·테스트 정리,
   샘플링·E-MAC-NET-0010 유지). T-294 새소식 엔진+앱 2원 조회+추천 링크 (빈 결과 조용히 스킵).
2. 플랫폼: macOS 단일, SwiftUI만, xcodebuild만. 기존 파일만 수정 (pbxproj 불필요).
3. 빌드+PERF+CACHE: unit 244/244 (신규 3건: cross-source·앱무시·source기본값, 삭제 1건),
   lint 신규 0건(기준선 3건). ChatPaneView 400행 제한 초과 1건 발생 → 순수 함수 2종 FollowUpSuggest로
   이동해 해소. build SUCCEEDED+설치·실행. PERF/CACHE 영향 없음.
4. 남은TODO: T-270·T-289·T-215 미완. 눈확인 대기: 양 경로 카드 소실·새소식 엔진 3건 정상·앱 링크 클릭.
   앱 릴리즈 생기면 자동 합류 (cap 20 합산, 밀림 시 10+10 분리 후속).
5. 전달로그: SF Symbol은 `macwindow`로 확정 (`app.mac` 미존재, 심볼 회귀 테스트에 추가).
   AppRelease id가 source+tag로 바뀌어 merge 중복 키도 id 기준으로 통일.
6. 문서갱신: PLAN_v82+v83+T-293·294 완료+DESIGN 웰컴·시스템절+CHANGELOG+사용설명서 9장 1행.
   error_message_ko.json 변경 없음.
7. 큐상태: 미커밋 유지 (T-290~294 공존, 지시 전 커밋 금지).
8. E2E: 해당 없음.

---

# session-2026-09-17-macos — T-295~T-300 전수 리팩토링 (4건째)

1. 무엇을: Gallery 대비 응답속도 분석→세션키 KV 재사용→MTP 토글→후속 격리→전수 리팩토링.
   상태 정합(release 전체해제·evict 정리·LRU 터치·stream 단일경로)+히스토리 정직화+
   ConfigStore 단일주입+KV 단일소스+사각·중복 제거.
2. 플랫폼: macOS 단일, SwiftUI만, xcodebuild만. 기존 파일만 수정 (pbxproj 불필요).
3. 빌드+PERF+CACHE: unit 244/244, lint 신규 0건(serious 기존 8건 유지),
   build SUCCEEDED+설치·실행. 실측: 2턴째~ TTFT 0.9초 평탄, 후속 3초대.
4. 남은TODO: T-270·T-289·T-215 미완. 눈확인: MTP 토글 재실행 유지, 중지버튼 표시,
   제한없음 범위, 칩 탭 후 답변 길이 정상.
5. 전달로그: prefix키 설계 결함(턴마다 키 변경→매번 프리필) 자인 후 방ID 고정키로 교체.
   후속 공유가 본대화 오염(40자 답변) 일으켜 격리로 복귀. ToolLedger 통합은
   의미 차이(index vs callID)로 기각. grep 도구 패턴 오류 시 bash grep으로 우회.
6. 문서갱신: PLAN_v84+v85+T-295~300 완료+CHANGELOG Unreleased.
   error_message_ko.json 변경 없음.
7. 큐상태: feat 5a26616+docs 0d2cdc2 커밋, 푸시 미실시. P2(LRUCache·빌더·테스트분할) 후속.
8. E2E: 해당 없음.
