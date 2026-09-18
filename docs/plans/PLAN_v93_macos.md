# PLAN_v93_macos — 스킬 가져오기 UI 개선 (검색·출처 뱃지·선택 도구)

## 배경
- T-315 스킬 외부 루트·임포트 구현 완료. UI가 검색/출처 표시/일괄 선택 도구 부족.
- AIModelTalk(SkillSettingsView·SkillPickerPopover) 패턴 참조: 검색 필드·출처 뱃지·카운트·모두 표시/숨김·새로고침.

## 목표
1. **ImportCandidate에 출처(SkillSource) 추가** — opencode/claude/agents/기타, 우선순위 기반 중복 제거.
2. **SkillsImportSheet 리디자인** — 검색, 헤더 카운트, 출처 뱃지, 모두 선택/해제, 새로고침.
3. **skillsTab에 출처 뱃지 표시** — 외부 스킬 행에 뱃지.

## 상세

### 1. SkillsStore.swift 확장
- `enum SkillSource: String, Codable, CaseIterable { opencode, claude, agents, other }`
  - `label`, `priority`(낮을수록 높음: opencode=0, claude=1, agents=2, other=3)
- `knownExternalRoots` → `[(url: URL, source: SkillSource)]` 반환 (우선순위 순)
- `ImportCandidate`에 `source: SkillSource` 추가
- `importCandidates`: 우선순위 순 스캔 → 동일 이름 중복 제거(높은 우선순위 승)

### 2. SkillsImportSheet (SettingsView.swift)
```
┌─────────────────────────────────────────────────┐
│ 스킬 가져오기                                    │
├─────────────────────────────────────────────────┤
│ 🔍 [스킬 검색_______________________] [✕]       │
├─────────────────────────────────────────────────┤
│ 총 42개 · 검색 12개 · 설치됨 3개                │
│ [모두 선택] [모두 해제] [새로고침]              │
├─────────────────────────────────────────────────┤
│ ☐ [opencode] code-review  • PR 리뷰 자동화       │
│ ☐ [claude]   debug-helper  • 디버그 가이드       │
│ ☑ [agents]   test-writer   • 테스트 생성 (설치됨)│
└─────────────────────────────────────────────────┘
```
- 검색: 이름 + blurb 대소문자 무시 부분일치, 실시간 필터
- 헤더: `총 N개 · 검색 M개 · 설치됨 K개`
- 버튼: 모두 선택(미설치만), 모두 해제, 새로고침(재스캔)
- 행: 체크박스, 출처 캡슐 뱃지, 이름, blurb(1줄, 회색), 설치됨 표시

### 3. skillsTab 출처 뱃지 (SettingsMCPSkillViews.swift)
- `SkillInfo`에 `source: SkillSource?` 추가 (외부 루트일 때만 설정)
- `list()`에서 source 결정: `isBuiltin`이면 nil, 외부면 루트 매핑 → `knownExternalRoots`의 source
- 행 HStack에 `source?.label` 캡슐 뱃지 표시

### 4. 검증
- unit(기존 272 + 신규) 통과, swiftlint 신규 0
- `./build_and_run.sh build macos` OK
- 수동: 설정→스킬 탭에서 외부 폴더 추가·가져오기 시 검색·뱃지·일괄 선택 동작 확인
- 완료: 2026-09-18 (T-315 UI 강화).

## 테스트 추가
- `testImportCandidatesSourcePriority`: 동일 이름 다른 출처 → 높은 우선순위만 남음
- `testImportCandidatesSearchFilter`: 검색어 필터링 검증
- `testSkillSourceBadge`: skillsTab 행 뱃지 렌더링(UI 테스트는 스킵, 모델 로직만)

## 파일 변경
- `LiteRTLMStudio/Core/SkillsStore.swift` (모델 확장)
- `LiteRTLMStudio/SettingsView.swift` (SkillsImportSheet 교체)
- `LiteRTLMStudio/SettingsMCPSkillViews.swift` (skillsTab 뱃지)
- `LiteRTLMStudioTests/LiteRTLMStudioRefactorTests.swift` (신규 테스트)
- `docs/TODO.md`, `docs/CHANGELOG.md`, `docs/DESIGN.md` 갱신