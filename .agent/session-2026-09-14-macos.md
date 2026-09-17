# session-2026-09-14-macos — LiteRT-LM Studio 이어하기

> 실행 중: 0.7.74 (71 아님, 설치까지 맞춤). 브랜치 main, **커밋 0건 — 전부 미커밋** (T-097~T-113).

## 1. 무엇을
- 중앙 카드·버블·터미널·푸터·호버·추종·캐시·페인트 개편 묶음 (T-097~T-113, 0.7.59→0.7.74).
- 확정 수정 3건: 삭제 컨펌 중복→AppKit 단발 모달 (T-113), 재시도 시작점 질문행 앵커 (T-109), 영속 높이 캐시 (T-108).

## 2. 플랫폼/빌드
- macOS 단일, xcodebuild만. unit 61/61, lint 에러 0, BUILD SUCCEEDED. `build_and_run.sh build macos` 사용.

## 3. PERF/CACHE
- 높이 캐시: UserDefaults 영속 (SHA256 안정 키, `mdHeightCacheAgnosticV1`). `hashValue`는 재실행마다 바뀌어 영속 키 실격.
- 진입 체인: 관측 후 점프(킥1+확정1+검증1) + 페인트 게이트(`lastPaintAt > entrySince`) + 이중발사 제거.

## 4. 남은 TODO (중요도순)
- **이솝 방(18msgs) 미표시 미해결**: 내용은 trivial(코드블록 없음, WebContent CPU 0%). T-111 2단계 페인트 적용됐으나 눈확인 대기. `rendered` 신호 + 3초 `.task` 강제표시 있음. → 추후 수정으로 보류.
- **T-113 눈확인 완료**: 삭제 컨펌 1회 표시 사용자 확인됨.
- T-109 질문행 앵커·T-108 영속 적중도 눈확인 대기.

## 5. 전달 로그 (진입 로그 해석법)
- `시작 문서/오프셋`은 이전 방 잔재(stale)라 trend로만 볼 것. `검증 킥→종료: 수렴/짧음/상한`이 본체.
- `문서=-1` = 부팅 직후 finder 미발견 (무해). 동일 세션 3ms 이중 점프는 T-112 가드로 제거됨.
- `짧음 + 큰 문서` 조합 = stale 시작 수치 (무해).

## 6. 문서갱신
- TODO/CHANGELOG는 0.7.74까지 반영. DESIGN은 T-100까지만 (이후 미반영). PLAN_v5 untracked 상태.

## 7. 큐상태/ ops 주의
- **버전 범프는 빌드→설치→재실행 순서로 한 번에**: 범프 후 plain xcodebuild만 하면 설치본 plist가 한 버전 뒤처짐 (0.7.71/0.7.73 때 2회 실수).
- 실패 기록 (재시도 금지): 타임라인 `.id()` 교체(스크롤뷰 재생성 회귀), 호버 pill 오버레이(추적 붕괴), 높이 기준만 추종(stale 레이스).

## 8. E2E
- 해당 없음 (serve 스파이크 수동). full 스위트·k6는 사용자 허락 전 실행 금지.

---

## 9. 리팩토링 세션 (T-114~T-121, 0.7.75, PLAN_v6)

- PLAN_v6 + TODO T-114~T-121 + DESIGN 구조 섹션 반영. 테스트 공개 API(PLAN_v6 §3) 불변.
- 분리: App 334→107+4파일, ChatBubbles 696→shim+4파일, ContentView 999→204+6파일, Markdown 605→91+345+187, SystemMonitor 460→379+83, ChatStore 350→268+117, Tests 695→361+97+246. 최대 파일 379줄.
- B: PasteboardUtil·TimeFormat·ImageUtil 신규, 복사 5곳·시간 2곳·축소 1곳 교체 (구 함수명은 래퍼 유지).
- C: MarkdownPage NSLock, DebugLogger 2000 cap, ChatSSEParser Codable, isHealthy 5초 타임아웃. 디바운스·백그라운드화는 제외 (PLAN_v6 §2 기록).
- 검증: build SUCCEEDED + unit 61/61 + 신규코드 lint 0건. 버전 0.7.75/75 범프 (설치는 미실행 — 다음 build_and_run.sh build macos 때 설치).
- 미커밋 유지 (지시 전 커밋 금지). `git status` 대량 변경 — 커밋 시 T-114~T-121 묶음 1건 권장.

---

## 10. 2차 리팩토링 세션 (T-122~T-128, 0.7.76, PLAN_v6 §6)

- 재조사에서 30건 후보 확정 (린트 41건 전수 분류 + grep 6종 + 대형 8종 정독).
- R-0: 무영향 17건 (미사용인자·nil·comma 5·줄길이 5·switch·파라미터정렬 6). R-1: 사망 5종+테스트1+shim (git 복원 가능).
- R-2: 신규 로직 8종 회귀. R-3: DS 정리+caption 21곳+CardBox·CopyFlag·HistoryLineChart·MeterRow·ChatImage.
- R-4: entryPoll(decideEntry+applyEntryStep)·updateNSView 3분할·template 3분할·chatRequest·perfLine·requestFailed·ingest 테이블·Coordinator 핸들러 3분할.
- R-5: refresh TaskGroup 병렬 (Sendable-safe: runProcess static+Model Sendable) + run 30초 타임아웃 + 리소스락 + 포매터캐시.
- 추가 분리: SystemMonitor+Sampling·MarkdownCoordinator·SessionTests·RefactorTests. 최대 파일 310→208줄대.
- 검증: build SUCCEEDED + unit 68/68 + 린트 41→4 (잔여는 테스트고정·Codable로 수용, PLAN 기록).
- 자정 플레이크 1건 수정 (testChatRelativeTime, 기존 결함). pbxproj 수동 스크립트 1회 꼬임 → Edit 직접 수리 (교훈: pbxproj는 Edit로).
- 설치 미실행 — 다음 build_and_run.sh build macos 때 0.7.76 설치. 커밋은 지시 대기.

---

## 11. T-010 S-0 스파이크 (판정 GO, PLAN_v7 §6)

- 5종 실측 (gemma4-12b·v0.17.0): caps=CLI describe 일치, init 14.1초, TTFT 2.8초, Vision 응답, BenchmarkInfo 6종, initialMessages 주입 동작.
- 교훈: Xcode SPM resolve는 거대 repo에서 무진전. S-1은 exact 핀 재시도 → 막히면 로컬 래퍼 패키지로 폴백.
- 다운로드 규칙 신설 (AGENTS.local): 필요 파일은 요청만, 직접 다운로드 금지.

---

## 12. T-010 S-1 텍스트 패리티 (0.7.77, PLAN_v7)

- EngineVendor 로컬 래퍼: binaryTarget URL+checksum, Swift 13종은 앱 타깃 직접 포함.
- 교훈 3건: ① 직접 SPM 핀은 모든 xcodebuild를 stall → 즉시 원복. ② vendored Swift 모듈은 explicit-module 호환 실패 → 직접 포함으로 피벗.
  ③ dylib 링크·임베드는 SPM 자동, modulemap만 OTHER_SWIFT_FLAGS로 노출. ④ upstream `Content`와 ViewModifier.Content 충돌 → CardBox를 extension으로.
- EngineMode 전역 토글+사이드바 표시, ChatStore 분기 (usesNative·runNative·nativeFailed·noteFirstToken).
- 검증: build SUCCEEDED + unit 75/75 (Fake 7종) + 린트 수용 4건 유지.
- 눈확인 완료: 네이티브 실전송 (초기화 13.9초·TTFT 17.4초→11.8초).
- 설치 미실행 — 다음 build_and_run.sh build macos 때 0.7.77 설치.

---

## 13. T-131 S-2 (테스트+결정, 버전범프 없음)

- FakeEngine 파라미터 캡처 (프롬프트·이미지·히스토리·temperature) + 매핑 전달 회귀.
- nativeFailed 직접 매핑은 기존 테스트 유지. 76/76 통과, 린트 수용 4건 유지.
- 다음: T-132 S-3 벤치마크 패리티, Vision 실사 눈확인은 T-132과 함께.

---

## 14. T-132 S-3 벤치마크 (0.7.78, PLAN_v7)

- EngineBenchmark 구조체+프로토콜 benchmark()+NativeEngine 실측+BenchmarkStore 분기+Fake 2종. 78/78, 린트 수용 4건.
- CLI 대조: `benchmark gemma4-12b` 워밍업 10분 타임아웃 실패 (프로세스 정리함). 네이티브 실측 pre 16.5·dec 17.0 tok/s.
- 판정: 12B는 네이티브가 주 경로, CLI 폴백 유지.
- Vision 실사 눈확인 완료: 스크린샷 첨부(768x482)→네이티브 전송→TTFT 8.8초→완료. 이미지 분석 품질 사용자 확인됨.
- 0.7.78 빌드·설치·실행 완료 (T-010 종료).

---

## 15. T-133 S-4 폴리시 (0.7.78에 포함, 별도 범프 없음)

- SystemMonitor.appRSSGB 1Hz 샘플링 + 인스펙터 네이티브 행 + bytesToGB 회귀. 79/79, 린트 수용 4건.
- DESIGN 구조에 네이티브 엔진 섹션 추가. PLAN_v7·TODO·CHANGELOG 반영.

---

## 16. PLAN_v8 스크롤 2건 (0.7.79, T-134/T-135)

- T-134: 복원은 생성순 선두→최근 사용 세션 (`mostRecentSessionID` + 회귀).
- T-135: 전송 0.5초 보정 (준비중→하단, 휠 시 취소, 스트리밍 중 방치).
- 검증: 81/81 + 수용 4건 유지. 0.7.79 빌드·설치·실행 완료.
- T-135 사용자 확인됨 (해결). T-134 후속: 보기만 한 방 복원 안 됨 → T-136CurrentID 저장으로 해결 예정이었으나
  새 채팅 드래프트(T-137) 작업으로 대체 진행 중.

---

## 17. T-137 새 채팅 드래프트 (0.7.80, PLAN_v9)

- `newSession()` 삭제 → `startDraft()` + `ensureSessionForSend()`. 방 생성은 첫 전송 시점.
- 버튼 fill 제거·드래프트 틴트, `.focusChatInput` 알림+nonce 포커스, nil 진입 점프 스킵.
- 교훈: 멤버와이즈 init 인자 순서 불일치는 solver 폭주(타임아웃)로 나타남 — 선언 순서=호출 순서.
  chatPane 단일 식 예산 초과 → messageListView·followStreamedText·messageRow·bottomSection 분리.
- 검증: 82/82 + 수용 4건 유지. 0.7.80 빌드·설치·실행 완료.
