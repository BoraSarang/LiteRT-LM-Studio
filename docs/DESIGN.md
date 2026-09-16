# DESIGN — LiteRT-LM Studio (macOS)

> 스킬: `macos-app-design` + `ios-the-final-5-percent` + `apple-design` 적용. 기준: 딱 맥 앱 같아야 함.

## 정렬 규칙 (전역 기본)

* 데이터 있음 → 좌측·상단 정렬. 데이터 없음(빈 상태) → 가로·세로 중앙 정렬. 별도 요구 없으면 전 화면 적용.

## 레이아웃 (3분할 매니저형)

* 좌측 사이드바 (220px): 상단 탭 [채팅 | 모델] (T-230, 영속).
  환경+탭은 스크롤 밖 고정층 (T-231), 목록만 스크롤.
  환경 섹션(uv·litert-lm 버전·가속·엔진·상태)은 항상 고정.
  채팅 탭=대화 섹션(새 채팅 버튼+전체 틴트 선택행+정렬+핀/이름변경/삭제),
  모델 탭=모델 섹션+벤치마크 섹션 (T-231 후속, 모델 우선).
  모델 섹션=채팅식 (관리 버튼+선택행+호버 메뉴, T-231 후속). 벤치마크·모델 헤더 통일 (제목+건수).
  모델 관리 별도창 (T-232, PLAN_v47): `Window(id:modelManager)` + 사이드바 "모델 관리" 버튼·팔레트.
  상단(새 모델 가져오기+폴더 열기+새로고침), 목록 3층(다운로드 중·설치됨·스테이징),
  상태 뱃지(설치됨 초록·다운로드 완료·미설치 주황·진행 바+퍼센트+경과+남은시간+취소).
  가져오기 시트(추천 프리셋+직접입력·HF API 자동 파일 목록·로컬ID·토큰, 1 모델→2 파일→3 저장→4 진행).
  시작 후 입력 잠금+에러 고정 슬롯+중복 시작 가드. `DownloadCenter` 앱 상주 (창 닫아도 계속·재오픈 표시).
  스테이징 `~/Documents/.LiteRT-LM` 숨김 유지, 완료 후에도 보관. 목록 캐시 60초.
  카탈로그 찾아보기 탭 (T-234, PLAN_v49; T-238/T-240 다듬기): 추천 모델 기본+전체 확장,
  검색·패밀리·정렬, 좌 목록(아바타+이름+통계)→우 상세(메타+Download Options+README 전체)+
  푸터(로컬·용량·경로). 탭·필터는 전폭 버튼 (segmented 고정폭 금지).
  다운로드 행 (T-245/T-246/T-248): 파일명+%·메타 1줄·바닥 2pt 바,
  받는 중 일시정지·취소·삭제, 멈춤 이어받기, 취소·실패 다시 받기, 삭제 컨펌.
  큐 영속+일시정지 복원+미완성 고아 (T-249). 모델 삭제 vs 파일 삭제 분리 (T-250).
  - 상태 행 (T-183/T-187, Ollama식): 대화 가능=선택 경로 준비됨. 초록=대화 가능, 주황=외부 미연결, 회색=중지(경로별 안내).
  - 엔진 행 (규칙 1, T-231 후속): 입력창 route 추종. 앱 내 엔진=초기화/중지/다시 실행, 서버=데몬 시작/중지.
    준비 중 스피너, 실패 코드 표시. 버튼은 전폭 행·중앙 정렬·한 줄.
  - 대화 유지형 (T-191): 동일 조건이면 conversation 재사용, KV 이어쓰기 (매번 풀 프리필 제거).
  - 새 채팅 드래프트 (T-137): 버튼 클릭은 방을 만들지 않고 틴트+입력 포커스만. 첫 전송 시 방 생성·선택. 평상시 버튼은 fill 없음.
* 중앙 (가변): 채팅 타임라인 + 스트리밍 버블 + 중단 버튼 + 입력창(첨부·경로 메뉴·전송). 빈 상태 온보딩 카드.
  - 바깥 카드: 안쪽 12 + 외곽선(radius 12) + 바깥 8 플로팅 여백 (T-095/T-098).
  - 입력창: 터미널과 동일 뼈대 (바깥 박스 배경+테두리, 에디터 투명) (T-097).
  - 터미널: 탭 전환 고정 (콘텐츠 영역 통일+셀 늘림+헤더 자리 유지) (T-100).
  - 버블: 유저 우측 / 어시스턴트 좌측 + 복사·재시도 푸터 + 에러 테두리 (PLAN_v3).
  - 본문: 네이티브 마크다운 (T-150, WKWebView 제거): 줄블록(제목·목록·표·구분선·인용·문단)+펜스 코드(Highlightr 색상·헤더·복사)+줄바꿈 보존. 대화 열 12px inset (T-172).
  - 입력: TextEditor 멀티라인 (Return 전송·Shift 줄바꿈·Cmd+. 중단).
  - 입력창 모델 피커 (T-229): 전송 경로 옆 Menu 내장 (설치 목록·Gemma/Qwen 우선·사이드바 동기).
  - 권한 (T-228): 설정 단일 스위치 (사용 안 함/매번 묻기/모두 허용), 전송·삭제 게이팅.
  - 전송 경로 피커 (T-186/T-188): Menu 스타일 한 칸 (서버 / 앱 내 엔진, 구글 Engine-vs-Server 구도).
  - 툴바 시작/중지 (T-189): 입력창 경로 추종 (앱 내 엔진=초기화/반납, 서버=start/stop). 액션 묶음은 ServerActions.swift 분리.
  - 스크롤: Sticky-Pin (하단 고정 시만 추종) + 진입 절대점프 일원화 (T-167).
    종료 후 보정 5종 (빈 영역·위 고착·붕괴·고착·프록시 재착지, 이동량 가드, T-198~204).
    앵커 실측 재수렴 (핀ON 사각지대, T-206). 교체 감지+자 진단 (T-207).
    스윕 삭제+보정 예산 2회 (T-211). 프록시 우선 착지 (T-209).
* 우측 인스펙터 (240px): backend(CPU/GPU), MTP, temperature/topK/topP, max tokens, thinking budget(미지원 시 비활성화), vision/audio backend.
* 실행 설정 확장 (T-175/T-177, PLAN_v22): Audio 실행(오디오 모델만)·CPU 스레드(CPU 모드만)·캐시·KV 토큰·Thinking 기본값/예산 + 고급 접기(Metal residency·Visual 예산·정밀도).
* 생성 설정 확장 (T-176, PLAN_v22): Temperature(기본 1.0)·TopK(64)·TopP(0.95)·Max 토큰·Seed·시스템 프롬프트(네이티브만)·Thinking 토글/예산.
* DebugPanel: Cmd+Shift+D 별도 윈도우, 열림 시 마지막, 자동 스크롤 토글+핀, 네이티브 List 선택 복사, 검색 (T-053/T-057).
* 벤치마크 별도창 (T-216/T-217/T-218): `Window(id:benchmark)` + 사이드바 "벤치마크" 섹션(열기+최근 3건).
  좌측 히스토리(전체/모델 필터+삭제, JSON 영속 `BenchmarkHistory.json`, 보관 10(기본)/50/100/제한없음 설정),
  우측 새 측정(모델·모드 선택+예상 소요+CLI 경고+측정 시작/중지+경과+4단계+원문) + AI 분석(현재 채팅 모델·route, 마크다운 렌더, 프롬프트 공개).
* 벤치마크 창 다듬기 (T-220/T-226): 좌측 기록 패널 264 고정폭+헤더 2줄 분리, 우측 새 측정 영역 상단 고정·결과만 스크롤.
* 벤치마크 기록·분석 (T-221/T-223/T-224/T-227): 명시적 선택 최우선(라이브 metrics 분기 차단)+사이드바 선택 전달+새 측정 시 해제, 헤더 "측정 {경로} · 분석 {엔진}"+분석 복사, 슬롯별 분석 캐시+종료 시점 로그 100줄 저장, 측정한 경로·모델로 분석(미준비 시 안내).
* 벤치마크 전원·사이드바 (T-222/T-225, PLAN_v42/v44): 신규 모델 MTP 끔 기본(파일 명시 존중)+MTP·배터리 상태 줄(켬/20% 이하 방전 경고), 사이드바 채팅식(새 벤치마크+전체 선택행+호버 메뉴, 창과 선택 동기).

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
* 앱 내 엔진 (T-010/PLAN_v7, 코드명 `NativeEngine`): `EngineVendor`(바이너리 래퍼) + `Core/LiteRTLM`(벤더 소스 13종, 수정 금지)
  + `InferenceEngine`(추상) + `NativeEngine`(생명주기) + `EngineMode`(전역 토글, 기본 CLI).
  인스펙터에 앱 내 엔진 모드 앱 상주 표시. 에러코드 `E-MAC-ENG-0001/0002`.
* 테스트 공개 API(§3 목록) 이름 변경 금지.
