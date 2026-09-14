# TODO — LiteRT-LM Studio (macOS)

* [x] T-001 Phase 0 스파이크: serve 기동 + 일반/스트림 채팅 curl 검증
* [x] T-002 Xcode 스캐폴딩 + build_and_run.sh + DebugLogger + error_message_ko
* [x] T-003 상태 화면: uv/litert-lm 버전, 모델(list+du), config 유무, 데몬 상태
* [x] T-004 DaemonManager: 시작/중지/헬스체크/로그 + 포트 충돌 에러
* [x] T-005 ChatStore: 스트리밍 채팅 + 중단 + PERF(TTFT·tok/s)
* [x] T-006 ModelStore: import/delete/rename/describe + 실제 용량
* [x] T-007 풀 기능: benchmark 실행 시트, 이미지 첨부(Vision 검증 중), GPU/MTP 토글, 미지원 비활성화
* [x] T-008 3분할 UI + DebugPanel(Cmd+Shift+D, 복사, PERF/CACHE 뷰어)
* [x] T-009 게이트: xcodebuild + swiftlint + smoke/unit 통과, ~/Applications 복사
* [ ] T-010 2단계: SPM LiteRTLM 네이티브 Engine 옵션 (별도 마일스톤)
* [x] T-011 Vision 실측 확정: 실제 사진 한글 묘사 성공 (200 OK, 첫 호출 약 3분·인코더 초기화, 앱 타임아웃 300s+중단 대응)
* [x] T-012 시스템 그래프 복원+정확도: 분리형 복귀·데몬 강조·RAM 활성상태보기·footprint·경과나눗 (PLAN_v2)
* [x] T-013 툴바 분리: primaryAction 그룹 캡슐→개별 아이템, 서버버튼 고정폭 (아이콘 이탈 수정)
* [x] T-014 외부 아이콘: link.badge.minus→stop.fill 통일 + 심볼 회귀 테스트
* [x] T-015 전체 CPU 100% 고정: 틱 인덱스 교정(.2=idle/.3=nice) + 순수헬퍼 회귀 테스트
* [x] T-017 활성상태보기 패리티: CPU 2색 스택 + RAM 3색 스택 (PLAN_v2 §6)
* [x] T-023 그래프 교정: 선 렌더 + 절대틱 X고정 + 순서·확대 (활성상태보기 대조)
* [x] T-016 인스펙터 4섹션 on/off: 툴바 분할컨트롤 상시 + 전체off시 컬럼 자동숨김 + 마스터 보이기 복원 (PLAN_v2 §5)
* [x] T-018 툴바 후속: 분할칸 우측 끝 이동 + columnVisibility 컬럼 완전숨김 + 칸 파랑/희미 대비
* [x] T-019 마스터 우측 끝 이동 + 2열/3열 조건분기 (doubleColumn 사이드바 숨김 버그 수정)
* [x] T-020 샘플링+Thinking 병합: 생성 섹션 1개 + 분할칸 3개로 축소
* [x] T-021 인스펙터 3섹션 카드 분리: 헤더 없는 Section 박스로 구분 (접기 없음)
* [x] T-022 표시 상태 영속 저장: 3섹션+마스터 AppStorage 교체 (재실행 유지)
* [x] T-024 누적 스택+색+한줄: CPU/RAM 누적선·마크안쪽 색·범례순서·값행 1줄
* [x] T-025 선색 분리: series+scale로 CPU 2선·RAM 3선 고정색
* [x] T-026 아이콘 적용: Dock Light-LM + 메뉴바 ChipOnly
* [x] T-027 메뉴바 교체: ChipOnly(밋밋)→MenuBarIcon 얇은선 템플릿
* [x] T-028 말풍선 개편: 좌우 버블+복사/재시도 푸터+에러 테두리 (PLAN_v3)
* [x] T-029 마크다운: WKWebView 높이피팅+appendChunk (AGENTS.local 예외 승인)
* [x] T-030 입력바 개편: TextEditor 멀티라인+단축키+첨부 썸네일
* [x] T-031 스크롤 Sticky-Pin: 하단고정 추종+NSScrollView 절대좌표
* [x] T-032 세션/영속: 세션 목록+JSON 파일 영속
* [x] T-033 입력창 높이: 2줄 고정 시작·8줄 상한·초과 내부스크롤 (PLAN_v3)
* [x] T-034 입력창 실측식: 숨은 Text로 줄수 측정·명시 높이 (빈칸 과대 원인 제거)
* [x] T-035 종료 정리 확정: willTerminate 동기 shutdown+UserDefaults 직접 읽기+전이 테스트
* [x] T-036 자동 스크롤: 앵커 LazyVStack 이동+다음런루프 스크롤
* [x] T-037 마크다운 휠: NoScrollWKWebView 포워딩 이식
* [x] T-038 응답 사라짐: Coordinator pending flush+회귀 테스트
* [x] T-039 하단 로그: chatPane 하단으로 이동 (사이드바 제외)
* [x] T-040 마크다운 다크: 명시 이중 CSS
* [x] T-041 디자인 시스템+수동 외관: DS 토큰+AppearanceMode+설정 피커
* [x] T-042 다크 CSS 미적용: color-scheme 메타+실효 scheme 전달 (스크린샷: 다크에서 본문 검게 나옴)
* [x] T-043 마크다운 하단 잘림: 레이아웃 후 지연 실측+documentElement 기준 (스크린샷: 버블 하단 클립)
* [x] T-044 추종 게이트: 휠 일시정지+0.4s 스로틀 (읽는 중 끌어내림)
* [x] T-045 CPU 100%·응답 없음: 1Hz 모니터 전체 리렌더 차단+Markdown equatable
* [x] T-046 세션 전환 하단 점프: currentSessionID 감지+게이트 우회+높이 보정
* [x] T-047 절대좌표 점프: ScrollViewFinder 이식+jumpToBottom+4연타 수렴+추종 멱등화
* [x] T-048 추종은 내용-증가 때만: 하단-스킵이 증가분까지 막던 버그 수정
* [x] T-049 말풍선 하단 여백: 블록 기본 마진 명시+마지막 자식 0
* [x] T-050 마크다운 엔진 이식: marked+hljs+렌더러/CSS+복사버튼+링크+스트리밍 점진 (아티팩트 제외)
* [x] T-051 완료 후 표 풀림: finalize 빈호출 → 원문 setBody + 상태머신 분리
* [x] T-052 빈 화면 진단·복구: JS try/catch 폴백+에러보고+프로세스사망 재로드
* [x] T-053 디버그 패널 개조: 별도 윈도우+자동스크롤+선택복사+검색+시간 표시
* [x] T-054 점프 오버슛: 클램프+지연 치유+보정 로그
* [x] T-055 디버그 패널 정리: 헤더 2단+빈 상태 중앙 표시
* [x] T-056 빈 화면 치유: 렌더 검증+자동 재시도+로드 실패 대응
* [x] T-057 디버그 List 전환: 네이티브 선택+헤더 slim+밀리초+단일 복사
* [x] T-058 대화 목록 Claude식: 새대화 버튼+전체선택행+정렬+핀/이름변경/삭제컨펌
* [x] T-059 삭제컨펌 중복+용어통일: nil-먼저+채팅 통일
* [x] T-060 개명: LiteRT-LM Studio (번들 com.borasarang.litert-lm-studio, 기록·설정 이사)
* [x] T-061 메뉴바/Dock 앱명: CFBundleName 표시명
* [x] T-062 툴바 분할칸 간격: 다닥붙음 해소
* [x] T-063 아이콘 교체: NoText 에셋+메뉴바 고가시성 (README A+D안)
* [x] T-064 하단 버튼: 텍스트→아래 화살표 원형+가로 중앙 정렬
* [x] T-065 어시스턴트 버블 전폭: 60pt 예약 제거 (유저 버블 유지)
* [x] T-066 한글 볼드: 조사 직결·안쪽 공백 `**`도 볼드 (marked 인라인 확장)
* [x] T-067 벤더 최신화: marked v14→v18.0.13 + hljs v11.9.0→v11.12.0 (UMD 유지, node 16종 비교)
* [x] T-068 정보 창: TubeKeep식 AboutView (제작자+라이브러리 링크, 문의 제외)+버전 범프 0.7.33
* [x] T-069 코드 하이라이트 색: hljs 토큰 팔레트 (라이트/다크)+pre 분홍 상속 차단
* [x] T-070 채팅 폰트 줌: ⌘+/⌘-/⌘0 (0.7~2.0, 재실행 유지)
* [x] T-071 입력란 플레이스홀더 진하게: tertiary→secondary
* [x] T-072 인스펙터 타이틀: 시스템 현황·실행 설정·생성 설정+3열 320 고정
* [x] T-073 시스템 현황 정리: 데몬 불일치 진단+자동범례 숨김+타이틀 위+호버 팝오버
* [x] T-074 타이틀 %: CPU·RAM도 GPU처럼 타이틀 옆에 % 표시
* [x] T-075 본문 자간: 0.015em+줄간격 1.65 (코드는 제외)
* [x] T-076 전송 명시 점프: streaming 시작 시 re-pin+수렴 (읽기 보호 유지)
* [x] T-077 응답 푸터: 완료 후에만 복사·재시도 표시
* [x] T-078 진입 점프 강화: 6연타 2초 수렴+성공 확인 (스트리밍 탭과 독립)
* [x] T-079 진입 오판 수정: 미성장 문서 자명 성공 차단 (스크롤 여지 게이트)
* [x] T-080 진입 수렴 기반: 안정까지 연장(5초 상한)+휠 임계+didFinish 폴백 병행
* [x] T-081 진입 확정: 프록시 강제 생성+조기종료 삭제+핀 실측 정정
* [x] T-082 진입 킥 매회: 0회차 허공 킥 수정 (앵커 미배치 대비 재킥)
* [x] T-083 떨림·빈 화면: 킥 1회·늦게+높이 캐시 (이중 구동 해소)
* [x] T-084 백지 진입: 문서 0 오프셋 강제+짧음 게이트+진입 진단 로그
* [x] T-086 거짓 수렴 차단: 검증 킥+디버그 전체 복사
* [x] T-090 리사이즈 재측정: 너비 관측+여유 확보+디바운스 (잘림 방지)
* [x] T-087 완료 출렁 제거: 점프 데드밴드+heal 둔감화+수렴 연장
