# PLAN v92 — 앱 데이터 홈 통합 `~/.litert-lm-studio` + 외부 스킬 임포트 (macOS, T-314·T-315)

> 사용자 요청: MCP·스킬·기록 등이 `~/Library/Application Support`, `~/Documents`,
> `~/Library/Caches`에 흩어져 있다. `~/.litert-lm`처럼 `~/.litert-lm-studio`
> 단일 홈으로 쓸 수 없나? + 클로드·오픈코드 스킬을 스킬 관리에서 확인·임포트.

## 사용자 결정
- 범위: **앱 소유 데이터만** 통합. `~/.litert-lm`(litert-lm CLI config·models)·`~/.wigolo`는 현행 참조 유지.
- 기존 데이터: **백업 후 자동 이사**(소형 JSON 복사=원본 보존, 대용량 스테이징 동일 볼륨 이동).
- 스킬: 설정에서 외부 폴더 추가 + Claude/opencode 스킬을 스킬 탭에서 확인 후 임포트.

## 새 홈 레이아웃
```
~/.litert-lm-studio/
├── chats/chat-history.json     ← App Support/LiteRTLMStudio/chat-history.json
├── mcp/servers.json            ← App Support/LiteRTLMStudio/mcp-servers.json
├── skills/<이름>/SKILL.md      ← App Support/LiteRTLMStudio/Skills/
├── benchmarks/history.json     ← App Support/LiteRTLMStudio/BenchmarkHistory.json
├── release-notes.json          ← App Support/LiteRTLMStudio/release-notes.json
├── engine-cache/               ← Caches/LiteRTLMStudio/EngineCache/
├── staging/                    ← Documents/.LiteRT-LM (모델·.mapping.json·.queue.json)
└── workspace/                  ← Documents/.LiteRT-LM/workspace
```
UserDefaults(plist)는 환경설정이라 이동하지 않는다. `studioHome` 키로 홈 재지정 가능(재실행 반영).

## 변경
1. 신규 `Core/StudioPaths.swift`: 홈 해석(순수)+하위 경로 빌더+`ensure`. 단일 진실.
2. 신규 `Core/StudioMigrator.swift`: 1회 이사. 소형 JSON은 복사(원본=백업), 스테이징은 이동.
   `studioHomeMigrated` 플래그, 실패 시 원본 유지+로그. 실행 지점=`LiteRTLMStudioApp.init`
   (스토어 생성 전, NSApp 호출 아님).
3. 경로 수렴: `ChatStore`·`MCPStore`·`SkillsStore`·`BenchmarkHistory`·`ReleaseNotes`·
   `NativeEngine.engineCacheDir`·`ShellTools.workspaceRoot`·`ModelStoreStaging.stagingURL`.
   각 저장소는 신 경로 미존재+구 경로 존재 시 폴백 복사(마이그레이터 미실행 대비).
4. `SkillsStore` 외부 루트: `skillRoots`(UserDefaults 배열)+`scan()` 멀티 루트.
   `SkillsImport`: `~/.claude/skills`·`~/.config/opencode/skills`·`~/.opencode/skills`·
   `~/.agents/skills` 탐색 → 후보 목록 → 선택 복사. 시트는 `SettingsMCPSkillViews.swift`에 추가.
5. 설정: 스킬 탭에 외부 루트 추가/제거·가져오기 버튼. 일반 탭에 홈 경로 표시(읽기 전용+폴더 열기).
6. 테스트: StudioPaths 해석·하위 경로, StudioMigrator 계획(존재성 주입), SkillsStore 멀티 루트·임포트 필터.

## 검증
- unit(기존 260 + 신규 12 = 272) 통과, swiftlint 신규 0, `./build_and_run.sh build macos` OK.
- 수동: 이사 후 채팅·MCP·벤치·캐시가 새 홈에서 보임, 구 홈은 백업으로 남음 — 실홈 확인 완료
  (`~/.litert-lm-studio/{chats,mcp,benchmarks,engine-cache,staging,workspace}`, 구 App Support JSON 유지,
  `studioHomeMigrated=1`). 신규 임포트(외부 폴더 추가·가져오기)는 사용자 눈확인 대기.
- 완료: 2026-09-18 (T-314·T-315).
