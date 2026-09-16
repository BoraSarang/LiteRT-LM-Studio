# DESIGN — LiteRT-LM Studio (macOS)

> 스킬: `macos-app-design` + `ios-the-final-5-percent` + `apple-design` 적용. 기준: 딱 맥 앱 같아야 함.

## 정렬 규칙 (전역 기본)

* 데이터 있음 → 좌측·상단 정렬. 데이터 없음(빈 상태) → 가로·세로 중앙 정렬. 별도 요구 없으면 전 화면 적용.

## 레이아웃 (3분할 매니저형)

* 좌측 사이드바 (220px): 환경 섹션(uv·litert-lm 버전·가속·엔진·상태), 대화 섹션(새 채팅 버튼+전체 틴트 선택행+정렬+핀/이름변경/삭제), 모델 섹션(목록·용량·선택), 서버 섹션(상태점·포트·업타임·시작/중지).
  - 상태 행 (T-183/T-187, Ollama식): 대화 가능=선택 경로 준비됨. 초록=대화 가능, 주황=외부 미연결, 회색=중지(경로별 안내).
  - 엔진 행 (T-185): 네이티브 실행/중지/다시 실행 버튼. 준비 중 스피너, 실패 코드 표시.
  - 대화 유지형 (T-191): 동일 조건이면 conversation 재사용, KV 이어쓰기 (매번 풀 프리필 제거).
  - 새 채팅 드래프트 (T-137): 버튼 클릭은 방을 만들지 않고 틴트+입력 포커스만. 첫 전송 시 방 생성·선택. 평상시 버튼은 fill 없음.
* 중앙 (가변): 채팅 타임라인 + 스트리밍 버블 + 중단 버튼 + 입력창(첨부·경로 메뉴·전송). 빈 상태 온보딩 카드.
  - 바깥 카드: 안쪽 12 + 외곽선(radius 12) + 바깥 8 플로팅 여백 (T-095/T-098).
  - 입력창: 터미널과 동일 뼈대 (바깥 박스 배경+테두리, 에디터 투명) (T-097).
  - 터미널: 탭 전환 고정 (콘텐츠 영역 통일+셀 늘림+헤더 자리 유지) (T-100).
  - 버블: 유저 우측 / 어시스턴트 좌측 + 복사·재시도 푸터 + 에러 테두리 (PLAN_v3).
  - 본문: 네이티브 마크다운 (T-150, WKWebView 제거): 줄블록(제목·목록·표·구분선·인용·문단)+펜스 코드(Highlightr 색상·헤더·복사)+줄바꿈 보존. 대화 열 12px inset (T-172).
  - 입력: TextEditor 멀티라인 (Return 전송·Shift 줄바꿈·Cmd+. 중단).
  - 전송 경로 피커 (T-186/T-188): Menu 스타일 한 칸 (segmented 168pt 깨짐 수정).
  - 툴바 시작/중지 (T-189): 입력창 경로 추종 (네이티브=prepare/release, 데몬=start/stop). 액션 묶음은 ServerActions.swift 분리.
  - 스크롤: Sticky-Pin (하단 고정 시만 추종) + 진입 절대점프 일원화 (T-167).
    종료 후 보정 5종 (빈 영역·위 고착·붕괴·고착·프록시 재착지, 이동량 가드, T-198~204).
    앵커 실측 재수렴 (핀ON 사각지대, T-206). 교체 감지+자 진단 (T-207).
* 우측 인스펙터 (240px): backend(CPU/GPU), MTP, temperature/topK/topP, max tokens, thinking budget(미지원 시 비활성화), vision/audio backend.
* 실행 설정 확장 (T-175/T-177, PLAN_v22): Audio 실행(오디오 모델만)·CPU 스레드(CPU 모드만)·캐시·KV 토큰·Thinking 기본값/예산 + 고급 접기(Metal residency·Visual 예산·정밀도).
* 생성 설정 확장 (T-176, PLAN_v22): Temperature(기본 1.0)·TopK(64)·TopP(0.95)·Max 토큰·Seed·시스템 프롬프트(네이티브만)·Thinking 토글/예산.
* DebugPanel: Cmd+Shift+D 별도 윈도우, 열림 시 마지막, 자동 스크롤 토글+핀, 네이티브 List 선택 복사, 검색 (T-053/T-057).

## 토큰

* 폰트: SF Pro Text/UI, 코드·로그는 SF Mono 12. 본문 자간 0.015em (T-174, 코드는 제외).
* 간격: 8pt 그리드, 카드 radius 10, 사이드바 섹션 헤더 11pt semibold secondary.
* 색: 시스템 시맨틱 컬러만 (다크모드 자동). 상태점: green=실행중, gray=중지, red=에러.

## 상호작용

* 서버 시작 → 폴링 스피너 → 상태점 전환 + 로그 스트림.
* 채팅 전송 → 낙관적 유저 버블 → 스트리밍 어시스턴트 버블 → 완료 시 PERF 뱃지(TTFT·tok/s).
* 미지원 기능(Thinking/Tool, 현 모델): 컨트롤 disabled + “이 모델은 미지원” 툴팁.

## 아이콘

* Dock: Light-LM (블루 그라데이션+LM). 메뉴바: MenuBarIcon 얇은선 템플릿+상태점.

## 구조 (PLAN_v6 리팩토링 이후)

* 앱: `LiteRTLMStudioApp`(본체) + `AppServices` + `MenuBarView` + `SettingsView` + `AppNotifications`.
* 콘텐츠: `ContentView`(툴바·task) + `FollowGate` + `SidebarView` + `InspectorView` + `ChatPaneView` + `ChatScrollActions` + `PaletteViews`. 순수 스크롤 수학은 `ScrollMath(ContentView ext)` 유지.
* 채팅: `SessionListView` + `MessageBubbles` + `ChatInputBar` + `BottomPanelView`.
* 마크다운: `MarkdownView`(네이티브 렌더) + `NativeMarkdown`(순수 파서) + `CodeHighlight`(Highlightr 래퍼) + `CodeBlockView`(헤더·복사·비동기 승격).
  - 스트리밍 미닫힘 펜스 별도 처리+블록 해시 식별 (T-201, PLAN_v30): 꼬리 뒤집힘·상태 오부착 방지.
* 스크롤: 진입 폴링/지연보정 works 분리+epoch+양측 보정 (T-202, PLAN_v30).
* 코어: `ChatStore(+Session/+Native)` + `SystemMonitor(+Sampling/+Daemon)` + `PasteboardUtil` + `TimeFormat` + `ImageUtil`.
* 공용 UI: `DSComponents`(CardBox·CopyFlag·HistoryLineChart·HoverTip) + `MeterRow` + `ChatStore.ChatImage`.
* 네이티브 엔진 (T-010/PLAN_v7): `EngineVendor`(바이너리 래퍼) + `Core/LiteRTLM`(벤더 소스 13종, 수정 금지)
  + `InferenceEngine`(추상) + `NativeEngine`(생명주기) + `EngineMode`(전역 토글, 기본 CLI).
  인스펙터에 네이티브 모드 앱 상주 표시. 에러코드 `E-MAC-ENG-0001/0002`.
* 테스트 공개 API(§3 목록) 이름 변경 금지.
