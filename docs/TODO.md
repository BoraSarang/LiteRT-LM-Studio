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
* [x] T-010 2단계: SPM LiteRTLM 네이티브 Engine 옵션 (PLAN_v7, S-0~S-4 완료)
* [x] T-129 S-0 스파이크: resolve+5종 실측 (PLAN_v7 §6, 판정 GO)
* [x] T-130 S-1 텍스트 패리티: 어댑터+토글+에러코드 (PLAN_v7 §4, 네이티브 실전송 눈확인 완료)
* [x] T-131 S-2 Vision+게이팅: 매핑 전달 회귀+capability 결정 (PLAN_v7, 버전범프 없음·테스트전용)
* [x] T-132 S-3 벤치마크 패리티: 네이티브 1턴 실측 확정, CLI 12B 워밍업 타임아웃으로 폴백 (PLAN_v7 §4)
* [x] T-133 S-4 폴리시: 앱 상주 표시+문서 (PLAN_v7 §4, 0.7.78에 포함)
* [x] T-134 재실행 복원: 최근 사용 세션 선택 (PLAN_v8)
* [x] T-135 준비중 가림: 0.5초 보정 점프 (PLAN_v8)
* [x] T-136 현재 방 ID 저장: 보기만 한 방도 복원 (PLAN_v8 §5, 0.7.80에 포함)
* [x] T-137 새 채팅 드래프트: 클릭 시 방 미생성+첫 전송 시 생성 (PLAN_v9)
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
* [x] T-091 열 cap 768 중앙+캐시 너비 버킷+정착 재측정
* [x] T-092 기본 창 1340×800+프레임 자동 유지
* [x] T-093 입력창·서버 로그 열폭 통일 (768 중앙)
* [x] T-094 터미널 개편: 구분선 제거+입력창 동일 박스+시스템 가로 3칸+자동스크롤+복사/지우기+시각
* [x] T-095 중앙 카드: 바깥 직사각형+터미널 높이 통일
* [x] T-096 마무리: 터미널=시스템 높이+미니 팝오버+여백 통일
* [x] T-097 입력창 뼈대 통일: 바깥 VStack에 배경+테두리 (터미널과 동일, 24pt 좁음 해소)
* [x] T-098 중앙 카드 바깥 여백: 외곽선 뒤 외부 12 → 8 조정
* [x] T-099 유저 버블 좌우 숨쉬기: 본문 .padding(12) 복원 (어시스턴트 그대로)
* [x] T-100 터미널 탭 전환 고정: 콘텐츠 영역 통일+셀 늘림+헤더 자리 유지
* [x] T-101 준비 중 커서 숨기기: 빈 응답 본문은 preparing 동안 ▍ 미표시 (첫 토큰부터)
* [x] T-102 에러 버블 안쪽 여백: isError만 좌우 12 (박스 그대로, 일반 응답 0 유지)
* [x] T-103 응답 푸터 개편: 스트리밍 중 하단 진행 표시+완료 후 호버 공개+복사·재시도 아이콘·툴팁
* [x] T-104 진입 출렁 제거: 관측 후 점프(킥1+확정1+검증1)+진입 중 치유 스킵
* [x] T-105 호버바 안정: pill 폐기→인플로우 일반 줄+해제 0.4초 지연+28 히트영역+툴팁 응답 복사/응답 재시도
* [x] T-106 재시도 추종: 텍스트 길이 기반 (stale 높이 무관)+축소 리셋
* [x] T-107 너비 무관 높이 캐시: 진입 초기 프레임 근사 부활 (버킷 미스 수정)
* [x] T-108 영속 높이 캐시: SHA256 안정 키+UserDefaults (빌드·재실행 후도 적중)
* [x] T-109 재시도 시작점: 질문행 앵커 2회+아이콘 간격 4 (일반 전송 통일)
* [x] T-110 팝인 마스킹: 행 첫 페인트 페이드인 (타임라인 크로스페이드는 스크롤뷰 재생성 회귀로 revert)
* [x] T-111 2단계 페인트: 선표시+지연 하이라이트 (동기 highlightAuto 첫 페인트 차단 해소, JS만)
* [x] T-112 콜드 렌더: 숨은 예열 웹뷰+페인트 게이트 종료+이중 점프 제거
* [x] T-113 삭제 컨펌 중복: AppKit 단발 모달+액션 1초 가드 (SwiftUI 다이얼로그 상태 경쟁 제거) + 눈확인 완료
* [x] T-087 완료 출렁 제거: 점프 데드밴드+heal 둔감화+수렴 연장
* [x] T-114 공통유틸: Pasteboard·시간·이미지 중복 제거 (PLAN_v6 §2)
* [x] T-115 앱분리: App 334줄 5파일 분리 (PLAN_v6 §2)
* [x] T-116 채팅분리: ChatBubbles 696줄 4파일 분리 (PLAN_v6 §2)
* [x] T-117 콘텐츠분리: ContentView 999줄 7파일 분리 (PLAN_v6 §2)
* [x] T-118 엔진분리: Markdown·Monitor·ChatStore 확장 분리 (PLAN_v6 §2)
* [x] T-119 구조개선: 캐시락·SSE Codable·헬스 타임아웃·로그 cap (PLAN_v6 §2)
* [x] T-120 테스트분리: 단일 695줄 3파일 분리 (PLAN_v6 §2)
* [x] T-121 검증: unit 61/61+lint+build 게이트 (PLAN_v6 §5)
* [x] T-122 린트 정리: 15건 무영향 수정 (PLAN_v6 §6)
* [x] T-123 사망코드 제거: 5종+테스트1 (PLAN_v6 §6)
* [x] T-124 테스트 보강: SSE·이미지·시간·cap 회귀 (PLAN_v6 §6)
* [x] T-125 토큰/컴포넌트: DS·CardBox·복사버튼·측정·차트 (PLAN_v6 §6)
* [x] T-126 복잡함수 분해: 5종 순수 추출 (PLAN_v6 §6)
* [x] T-127 성능/견고성: 병렬·타임아웃·락·캐시 (PLAN_v6 §6)
* [x] T-128 검증: unit 68/68+lint 41→4+build 게이트 (PLAN_v6 §6)
* [x] T-138 이름 변경 시트 반복: sheet(item:) 시도했으나 0.7.81에서 재현 지속 → 기각 (PLAN_v10)
* [x] T-139 이름 변경 AppKit 단발 모달: 시트 삭제→NSAlert+NSTextField+1초 가드 (PLAN_v11)
* [x] T-140 툴바 중앙 현재 채팅방 표시: 1줄째 채팅방명+2줄째 모델 요약 (PLAN_v12, 위치 오지정으로 T-141로 이동)
* [x] T-141 사이드바 타이틀 현재 채팅방 표시: navigationTitle 무반영으로 기각 (PLAN_v13)
* [x] T-142 좌측 타이틀 NSWindow 직접 동기화: WindowTitleSync+roomTitle (PLAN_v14)
* [x] T-143 빈 화면 서버 상태별 2종 문구: 실행 중=환영형, 그 외=시작 안내 (PLAN_v15)
* [x] T-144 입력창 플레이스홀더 위치 일치: 위 8·왼쪽 5 (PLAN_v16)
* [x] T-145 플레이스홀더 가로 미세 조정: 왼쪽 10 (최종)
* [x] T-146 네이티브 데몬 표시+입력 게이팅: 히어로 교체+sendAllowed (PLAN_v17)
* [x] T-147 어시스턴트 버블 좌측 2pt: 박스+푸터 함께 (좌단 일치 유지)
* [x] T-148 준비 문구 정정+스트리밍 묶음 갱신: 첫 토큰 대기+0.1초 flush (PLAN_v18)
* [x] T-149 전송 히스토리 범위 설정: 제한 없음 기본+10·20·40턴 (PLAN_v19)
* [x] T-150 채팅 마크다운 네이티브 전환: AttributedString+펜스 분리, 웹뷰 3파일+JS 번들 제거 (PLAN_v20)
* [x] T-151 개행 보존 줄블록 렌더: 제목·목록·표·문단 분리+인라인 파싱 (일렬 표시 수정)
* [x] T-152 서식 완성: 블록 전체 파싱·폰트 내장·실제 표·구분선·한글볼드 정규화
* [x] T-153 진입 즉시 점프: 빈 화면·출렁 해소 (폴링 전 2회 점프)
* [x] T-154 볼드 보장+인덴트: `**` 수동 분할·목록 인덴트·NativeMarkdown 분리
* [x] T-155 빈줄 수렴: 연속 빈줄 blank 1개 (선행/후행 무시)
* [x] T-156 진입 무동작+코드 태그: 수렴 시 재점프 제거·언어 태그 제거
* [x] T-157 표 구분선 다열 수정: 셀 단위 판정 (원문 회귀)
* [x] T-158 코드 구문 강조: Highlightr 벤더+GitHub 테마 2종 (PLAN_v20)
* [x] T-159 코드 상자 경계: 둥근 테두리로 본문과 분리
* [x] T-160 코드 헤더+비동기 승격: 언어·복사 버튼, 직렬 큐 하이라이트
* [x] T-161 표 스타일: 테두리 상자+행/열 구분선+셀 패딩
* [x] T-162 푸터 공간 예약: 상시 배치+투명도 전환·본문 직하 단일행
* [x] T-163 표 실선 직접 배치: Divider 축 버그 제거
* [x] T-164 목록 기본 인덴트: 최상위 12pt+중첩 누적
* [x] T-165 질문 다시 요청: 입력 푸터 행+입력창 채움+이후 삭제
* [x] T-167 진입 절대점프 일원화: 프록시 오버슛 제거·재생성 revert
* [x] T-169 응답 서식 색상: 인용 블록+인라인 코드 분홍+마커 secondary
* [x] T-168 입력 푸터 아이콘화: 복사·연필 아이콘 (응답과 통일)
* [x] T-170 응답 푸터 밀착: 하단 패딩 축소
* [x] T-171 호버 팁 자립화: 자체 말풍선 6곳 (`.help` 전역 미노출 대응)
* [x] T-172 대화 열 inset: 리스트 4px (입력창 구분)
* [x] T-173 응답 우측 잘림 수정: 제안 폭 줄바꿈 고정
* [x] T-174 본문 자간 복원: 0.015em tracking, 표·셀 포함, 코드 제외 (PLAN_v21)
* [x] T-178 빌드 정리: AppNotifications 컴파일 중복 등록 제거 (PLAN_v22)
* [x] T-178 빌드 정리: AppNotifications 컴파일 중복 등록 제거 (PLAN_v22)
* [x] T-179 서버 상태: 미연결 외부 실행 표시+재연결 (PLAN_v22)
* [x] T-175 실행 설정 확장: audio·스레드·cache·KV·thinking/budget (PLAN_v22)
* [x] T-176 생성 설정 확장: TopK/TopP/토큰/시드/시스템·serve+네이티브 연결 (PLAN_v22)
* [x] T-177 고급 접기: residency+visual+정밀도, vision config 추종 (PLAN_v22)
* [x] T-180 인앱 설명: TopK 우측 묶음·미지원 캡션·칸 140+힌트 (PLAN_v23)
* [x] T-181 사용설명서: docs/사용설명서.md 앱 전체 10장 (PLAN_v23)
* [x] T-182 인앱↔문서 대조 수정 (PLAN_v23)
* [x] T-183 Ollama식 상태 단일화: UnifiedStatus+사이드바 상태 행 (PLAN_v24)
* [x] T-184 조각 경계 공백 소실: styled() 보존 옵션+회귀 2건 (PLAN_v25)
* [x] T-185 네이티브 수명주기 UI: 상태+실행/중지/재실행 (PLAN_v26)
* [x] T-186 입력창 경로 선택+전역 토글 폐기 (PLAN_v26)
* [x] T-187 상태 표시 마무리 (PLAN_v26)
* [x] T-188 입력창 경로 피커 Menu화 (PLAN_v27)
* [x] T-189 툴바 시작/중지 경로 추종 (PLAN_v27)
* [x] T-190 TTFT 단계 계측: prepare+히스토리 로그 (PLAN_v28)
* [x] T-192 사이드바 버전 행: 환경 섹션에 앱 버전 표시
* [x] T-191 TTFT 처방: 계측 결과 반영 (PLAN_v28)
* [x] T-193 재사용 키 전체 전사 분리: 윈도우 슬라이드 대응 (PLAN_v28)
* [x] T-194 스트리밍 미완성 볼드 마커 숨김 (PLAN_v29)
* [x] T-195 코드 스팬 꺾쇠 보존: 파서 우회 렌더 (PLAN_v29)
* [x] T-196 스트리밍 하이라이트 1회로: 추종 기아 해소 (PLAN_v29)
* [x] T-197 스트리밍 중 코드 평문 표시: T-196 역효과 수정 (PLAN_v29)
* [x] T-198 빈 영역 보정: 문서 밖 오프셋만 수렴 (PLAN_v29)
* [x] T-199 진입 보정 상시화: 폴링 매 회차+5초 연장 (PLAN_v29)
* [x] T-200 진입·펜스 계측: finder 부착·verdict·블록 수 로그, 동작 불변 (PLAN_v30)
* [x] T-201 렌더 분리: 미닫힘 펜스 케이스+블록 해시 id+빈 코드 예약 (PLAN_v30)
* [x] T-202 스크롤 단일화: works 분리+epoch+양측 보정 (PLAN_v30)
* [x] T-203 검증·문서: full+lint+build+DESIGN·CHANGELOG 현행화 (PLAN_v30)
* [x] T-204 종료 후 문서 붕괴 보정: finishDocH+지연works 재수렴 (PLAN_v31)
* [x] T-205 보정 시 기준점 갱신: 자기차단 해소 (PLAN_v31)
* [x] T-206 앵커 실측 재수렴: 핀ON 허공 고착 해소 (PLAN_v32)
* [x] T-207 스크롤뷰 교체 감지+자 불일치 진단 (PLAN_v33)
* [x] T-208 스윕 복구+최종 확정: 얼어붙은 추정치 깨기 (PLAN_v34)
* [x] T-209 프록시 우선 착지: 동결 해제+확정 한 묶음 (PLAN_v35)
* [x] T-210 재수렴 calm 임계: 정착 후 출렁 제거 (PLAN_v36)
* [x] T-211 스윕 삭제+보정 예산: 진동자 해소 (PLAN_v37)
* [x] T-212 동결 깨움+핀 기본값: 콜드스타트 백지 해소 (PLAN_v38)
* [x] T-213 앵커 초기 보고+진입 완료 게이트: 떴다사라짐 해소 (PLAN_v39)
* [x] T-214 최종 슬롯 예산 우회: 예산 고갈 좌초 해소 (PLAN_v40)
* [x] T-216 벤치마크 별도창+수동시작+시간/단계 수정 (PLAN_v41 §3)
* [x] T-217 벤치마크 히스토리+보관설정(10/50/100/무제한)+사이드바 최근3건 (PLAN_v41 §3)
* [x] T-218 벤치마크 AI 분석(현재 채팅모델)+마크다운 렌더 (PLAN_v41 §3/§5)
* [x] T-219 벤치마크 검증·문서 (PLAN_v41 §6, 119/119+lint 에러 0)
* [x] T-220 벤치마크 창 깨짐 수정: 좌측 264 고정폭+기록 헤더 2줄+여백 확대 (눈확인 후속)
* [x] T-221 기록 클릭 "측정 전" 버그: 명시적 선택 최우선+사이드바 선택 전달+새 측정 시 해제 (눈확인 후속)
* [x] T-222 MTP 기본 OFF+벤치마크 전원 경고 (PLAN_v42, 123/123+lint 신규 0)
* [x] T-223 분석 엔진 표기 분리+결과 복사 (눈확인 후속, 125/125+lint 신규 0)
* [x] T-224 기록별 분석·원문 분리 (눈확인 후속, 125/125+lint 신규 0)
* [x] T-225 사이드바 벤치마크 채팅식 개편 (눈확인 후속, 125/125+lint 신규 0)
* [x] T-226 벤치마크 창 새 측정 영역 상단 고정 (눈확인 후속, 125/125+lint 신규 0)
* [x] T-227 AI 분석 측정 경로 추종 (눈확인 후속, 125/125+lint 신규 0)
* [x] T-228 전역 권한 3단계: Off/Ask/Allow 단일 스위치+전송·삭제 게이팅 (PLAN_v45, 127/127+lint 신규 0)
* [x] T-229 입력창 모델 피커: 설치 목록 내장 선택+Gemma/Qwen 우선 정렬 (PLAN_v45, 127/127+lint 신규 0)
* [x] T-230 사이드바 탭 분리: 상단 채팅/모델 탭+환경 고정 (PLAN_v46, 128/128+lint 신규 0)
* [x] T-231 사이드바 상단 고정: 환경+탭 스크롤 분리 상시 노출 (PLAN_v46, 128/128+lint 신규 0)
  후속: 모델 섹션 채팅식 개편+관리 버튼(껍데기)+엔진 route 추종 규칙 (129/129+lint 신규 0)
* [x] T-232 모델 관리 창: 별도 창 가져오기·목록·삭제·이름변경 (PLAN_v47, 스테이징 ~/Documents/.LiteRT-LM+캐시+상태 3종)
* [x] T-233 가져오기 정리+상주화: 4섹션 시트·자동 조회·시작 후 잠금·DownloadCenter 앱 상주 (PLAN_v48)
* [x] T-234 카탈로그형 개편: 둘러보기 탭(Staff picks+전체)+상세+README+푸터 (PLAN_v49)
* [x] T-237 README HTML 표: table 구간 네이티브 변환·링크 셀 파일명만 (PLAN_v50)
* [x] T-238 추천 모델 용어: Staff picks 노출·내부 정리 (PLAN_v50)
* [x] T-239 용량 표시: x-linked-size 우선+Range 폴백 (PLAN_v50)
* [x] T-240 탭·필터 전폭 버튼: 찾아보기·내 모델+규칙화 (PLAN_v50)
* [x] T-241 아바타 로컬 교체: HF 아바타 주소 무효(401) → 패밀리 이니셜 뱃지 (PLAN_v50)
* [x] T-242 게이트 저장소 대응: 상세 토큰칸+401 문구 직접 표시+파일 변경 시 ID 제안 (PLAN_v50)
* [x] T-243 HF 수동 다운로드 링크: 상세에 수동 다운로드 링크 (PLAN_v50)
* [x] T-244 다운로드 속도 표시: 진행행에 평균 속도 추가 (PLAN_v50)
* [x] T-245 삭제 컨펌: 닫기→삭제 개명+컨펌+`.part` 같이 삭제 (PLAN_v51)
* [x] T-246 버튼 풀세트: 일시정지·이어받기+취소 완전화+중복가드 (PLAN_v51)
* [x] T-247 모델 관리 일원화: 사이드바 삭제→관리창 이동+선택·벤치마크 이식 (PLAN_v51)
* [x] T-248 진행바 Web Island식: 파일명+%·메타·바닥 바 (PLAN_v51)
* [x] T-235 새 벤치마크 버튼 틴트 오표시: 미선택 시에도 선택처럼 보임 → fill 제거 (채팅 새 채팅 규칙과 통일)
* [x] T-236 카탈로그 좌 목록 폭 고정: HSplit 가변 → 264 고정 (벤치마크 기록 패널과 통일)
* [x] T-249 재실행 복원: 큐 영속+일시정지 복원+고아+원자쓰기 (PLAN_v52)
* [x] T-250 삭제 분리: 모델 vs 파일+체크박스+퍼지 (PLAN_v52)
* [x] T-251 고아 다시 받기: 미완성행 다시 받기+stem 검색 (PLAN_v52)
* [x] T-252 고아 직접 이어받기: 매핑 repo 확장+구호환 (PLAN_v52)
* [x] T-254 파일로 설치: NSOpenPanel→스테이징 복사→미설치 표시 (PLAN_v52)
* [x] T-255 전송 확인 제거: 전송 항상 허용+권한 도구용 재정의 (PLAN_v52)
* [x] T-257 온보딩 게이트 랜딩: uv·litert-lm 확인 후 시작 (PLAN_v53)
* [x] T-258 대화 목차 플로팅: 우측 중앙 바→호버 확장+점프·플래시+채팅 설정 토글 (PLAN_v54)
* [x] T-259 목차 호버 유지+투명: 컨테이너 호버+지연 접힘+패널 50% (PLAN_v54)
* [x] T-260 수동 스크롤 핀 해제: 휠 스탬프 시 실측 정정 (PLAN_v55)
* [x] T-261 후속질문 칩: 응답 기반 3~4개 우측 칩+즉시 전송+채팅 설정 토글 (PLAN_v56)
* [x] T-262 메인 웰컴 페이지: 빈 화면 환영+새소식(Releases+캐시)+업데이트+추천 링크 (PLAN_v57)
* [x] T-263 Spotlight식 팔레트+전체 채팅 검색: ⌘K·필터·전환+스크롤+플래시 (PLAN_v58)
* [x] T-264 한글 검색 강화: 초성+혼용+띄어쓰기 무시 (PLAN_v59)
* [x] T-265 팔레트 점프 진입 충돌+맨 아래로 미달 치유: 전환 억제+무스탬프 코어+상향 재점프 (PLAN_v60)
* [x] T-266 Tool calling S-1 표시 파이프: 이벤트·파서·접기+칩 (PLAN_v61)
* [x] T-267 Tool calling S-2 실행 네이티브: 로컬 도구+권한 게이트 (PLAN_v61)
* [x] T-268 Tool calling S-3 실행 서버: tools 전송+tool 응답 루프 (PLAN_v61)
* [x] T-269 웹 검색 도구: wigolo 우선 체인+검색/가져오기+데몬 관리 (PLAN_v62)
* [x] T-270 macOS 시스템 도구팩: 읽기 4+쓰기 5+날짜 파서+allowlist (PLAN_v63)
* [x] T-273 네이티브 초기화 자동 폴백: 모달 제외 재시도+코드 정정 (PLAN_v65)
* [x] T-274 인라인 think 분리: 본문 추론 접기로 이동 (PLAN_v65 후속)
* [x] T-278 미닫힘 꼬리 분리: 종료 시 마지막 빈줄 뒤 답변으로 (PLAN_v65 후속)
* [x] T-279 채팅 모델 저장: SceneStorage→AppStorage+1회 승계 (PLAN_v66 후속)
* [x] T-275 경로 고정+자동 초기화: 저장소 주입·마이그레이션·전환/변경 시 prepare (PLAN_v66)
* [x] T-276 추론 타이틀 정렬+자동 스크롤: 타이틀 박스 분리·합산 추종 (PLAN_v67)
* [x] T-277 재사용 시작 실패 재시도: 새 대화 1회 폴백 (PLAN_v68)
* [x] T-282 2턴째 시작 실패: 도구 턴 재사용 스킵+진단 (PLAN_v71)
* [x] T-284 wigolo 설정 통합: 설치+상태+자동 생명주기, 폴백 제거 (PLAN_v72)
* [x] T-285 MCP 클라이언트+스킬: 게이트웨이 2종+SKILL.md 주입 (PLAN_v73)
* [x] T-286 wigolo 내장 마무리: 문구+설치 배너+상태 동기화 (PLAN_v74)
* [x] T-283 승인 이중 로그+결과없음 정상화: 멱등 가드·allFailed 분리 (PLAN_v71 후속)
* [x] T-287 wigolo=유일 내장검색: 등록 게이트+토글 유도+도구탭 이전 (PLAN_v75)
* [x] T-289 전체 재감사 통합 처방 P0+P1+P2 (PLAN_v78)
* [x] T-290 앱내엔진 용어 통일+도구 미지원 모델 도구 제외 (PLAN_v79)
* [x] T-288 wigolo 완전 내장화: doctor+init 파이프라인+4칸 상태 (PLAN_v76)
* [x] T-271 설정 도구 탭: 전수 목록+개별 ON/OFF (PLAN_v63 후속)
* [x] T-272 셸 실행 + 파일 저장 도구: 차단+jail+확인 (PLAN_v64)
* [x] T-215 잔여 간헐 미도달 방: 현재 정상 동작 확인 — 종결 (PLAN_v31~v40 경위)
* [x] T-291 후속질문 LLM 호출: lazy 1회+현재 경로+실패 시 휴리스틱 폴백 (PLAN_v80)
* [x] T-292 후속질문 선행 생성: 서버만 스트리밍 중 선행+드리프트 판정, 네이티브는 작업 축소 (PLAN_v81)
* [x] T-293 데몬 히어로 카드 삭제: route 무관 완전 제거, 샘플링·E-MAC-NET-0010 유지 (PLAN_v82)
* [x] T-294 새소식 앱 저장소 합류: 피드 2원+추천 링크, 빈 결과 조용히 스킵 (PLAN_v83)
* [x] T-295 상태 정합: release 전체해제·evict/active 정리·prepare LRU 터치·stream 단일경로 (PLAN_v85)
* [x] T-296 히스토리 정직화: 미설정 기본 10턴+명시적 제한없음 동작 복원 (PLAN_v85)
* [x] T-297 ConfigStore 단일화: ContentView에 services.config 주입 (PLAN_v85)
* [x] T-298 사각 제거: max_prefix 플러밍·recent()·UI import·trailing (PLAN_v85)
* [x] T-299 중복 제거: JSON 헬퍼·pastTurns·KV 필드 통일, 도구결과 매칭은 의도적 분리 유지 (PLAN_v85)
* [x] T-300 검증: 244/244+lint 신규 0+build 게이트 (PLAN_v85)
* [x] T-301 세션 제거: evictSession 추가+재시도 꼬리 정리+1회성 호출 정리 (2차 조사)
* [x] T-303 1차 조사 (D1~D3): editMessage/취소/후속질문 3결함 수정 (unit 247/247)
* [x] T-304 2차 조사 (R2-15/17): prepare 실패 상태·dropModel LRU 방출 정합 (unit 247/247)
* [x] T-305 NativeEngine 400줄 관리: 주석 정리로 file_length 임계 유지
* [x] T-306 첫터치 프리필 예열 (PLAN_v87): prepare 선행+기본 OFF 토글+발동 didSet
* [x] T-307 예열 게이트: unit 252/252·lint 신규 0·build 통과
* [x] T-302 첫터치 프리필 실측: 방 열람→첫 전송 TTFT 대조 (실측 통과)
* [x] T-308 검색 데몬 실행 로그: serve 출력 수집+로그 보기 팝오버 (PLAN_v88)
* [x] T-309 웹 토글 명칭 정리: 마스터→웹 도구 사용 (PLAN_v89)
* [x] T-310 wigolo node PATH: node 경유 실행+PATH 주입 (PLAN_v90)
* [x] T-311 응답중 멈춤: 근본원인=스트림 정상 완료 시 `continuation.finish()` 누락 (PLAN_v90)
* [x] T-312 오늘 날짜 주입: FC 미지원 모델도 날짜·요일 인지 (시스템 프롬프트, PLAN_v90)
* [x] T-313 후속 질문 로딩 애니메이션: 심머+크로스페이드+최소 노출 0.4s (PLAN_v91)
* [x] T-314 앱 데이터 홈 통합: `~/.litert-lm-studio` 단일 홈+백업 후 자동 이사 (PLAN_v92) — StudioPaths/StudioMigrator, 경로 9곳 수렴, 실홈 이사 검증(chats·mcp·benchmarks·engine-cache·staging 이동, 원본 백업 유지).
* [x] T-315 스킬 외부 루트+임포트: 설정 폴더 추가+Claude/opencode/agents SKILL.md 가져오기 (PLAN_v93) — skillRoots 멀티 루트+자동 탐색 3곳+우선순위 병합, `SkillsImportSheet` 검색·출처 뱃지·일괄 선택·새로고침, skillsTab 출처 뱃지 표시.
* [x] T-316 web_search 1위 본문 자동 첨부: `combinedForModel`+autoFetchCap 2000, 실패 시 검색만 (PLAN_v94, 274/274+lint 신규 0+build OK)
* [x] T-317 웹 도구 칩 표시 개편: 한글 명칭+대표 인자+기본 접힘+가져오기 외부열기 (PLAN_v95, 눈확인 대기)
* [x] T-318 디자인 토큰 4파일: Colors/Typography/Spacing/Components 신규+DS 별칭 유지 (PLAN_v96 P0)
* [x] T-319 Browse 중복 제거+한글화: 추천 가로카드만+Download Options/PARAMS 한글화 (PLAN_v96 P0)
* [x] T-320 Benchmark·Settings 잘림: 2줄 셀+실패사유+Section 4개+ScrollView+DSSegmented (PLAN_v96 P0)
* [x] T-321 My Models P1: WarningBanner+원본 삭제+Badge+litertlm 숨김+버튼 위계 (PLAN_v96 P1)
* [x] T-322 차트·툴팁 P2: 바 수치라벨+GPU/MTP/환경 hover+EmptyState (PLAN_v96 P2)
* [x] T-323 인스펙터 사이드바식: List 전환+헤더 요약+호버 메뉴(기본값·숨기기)+unit (PLAN_v97)
* [x] T-324 인스펙터 실행/생성 탭: 시스템 고정+전폭 탭+툴바 단일화 (PLAN_v98)
* [x] T-325 2차 UI 버그픽스: 잘림 툴팁·한글화·인스펙터 세그먼트+Sticky바 (PLAN_v99)
* [x] T-326 팔레트 개편: 초성 하이라이트+최근 5개+벤치 섹션+아이콘 (PLAN_v100)
* [x] T-327 리스트 배경·카드화: 3리스트 배경+Divider+내 모델 카드행 (PLAN_v101)
* [x] T-330 대화 목차 후속칩 스타일+전체 스크롤 (PLAN_v104)
* [x] T-331 README 멀티라인 HTML 제거: svg 블록 스킵 (PLAN_v105)
* [x] T-332 대화 목차: 불투명+우측 정렬+하단 배치+하단 스크롤
* [x] T-333 인스펙터 배경 사이드바와 통일
* [x] T-334 실행 설정 잘림 해소: 탭 라벨 숨김·KV 줄바꿈·고급 세로 배치·스위치·한글화
* [x] T-335 잔여 수정: 표셀 svg·벤치하단·MTP 제한·HF토큰 게이트전용 (PLAN_v106)
* [x] T-336 초기화 실패 원인 표시: 파일 선확인+상세 문구 (PLAN_v107)
* [x] T-337 윈도우 위치 점프 제거: autosave 동기 적용 (실패 — T-339로 대체)
* [x] T-338 윈도우 루트에 Accessor 이동: ContentView 해석 전 복원 (실패 — T-339로 대체)
* [x] T-339 윈도우 위치 점프 근본 수정: AppDelegate 표시 전 복원+WindowAccessor 제거 (눈확인 통과)
* [x] T-340 실행 시 옛 모델 기본값 제거: 저장된 선택값 시드+폴백 빈 값 (눈확인 통과)
* [x] T-341 README 인라인 SVG 실제 이미지 렌더: NSImage SVG 디코드+라인 높이 배지 (눈확인 통과)
* [x] T-342 도구 호출 칩 표시 개선: 인자 한글 요약+결과 JSON pretty+원문 토글 (눈확인 완료)
* [x] T-343 도구 턴 느림 진단·단일 승인: 이중 runTolled 제거+턴 구간 로그+최종 TTFT (눈확인 완료)
* [x] T-344 서버 무수신 스톨 대응: 60초 워치독+E-MAC-NET-0006+최종 TTFT 위치 수정 (눈확인 완료)
* [x] T-345 스톨 자동 복구+대기 경과 표시: 데몬 재시작 1회 재전송+첫토큰 경과 초 (눈확인 완료)
* [x] T-346 도구 거짓말 처방: 실패 throw로 failed 칩+사전검증 원장 기록+정직 가드+승인창 포커스 (301/301+lint 신규 0+build OK, 눈확인 완료)
* [x] T-347 도구 성능: 재전송 턴 히스토리 트림+시스템 경량화+후속질문 3초 idle+선행 제거+읽기 전용 자동 승인+승인 대기 로그 분리 (305/305+lint 신규 0+build OK+실측 완료: 1턴 626자→3턴 104자, 후속질문 idle 3s·새 전송 기각, 승인 대기 0.97~2.14s, 왕복 19.5~36.4s, 읽기 전용 "매번 묻기"에서 자동 실행 확인) — P2-6 speculative_decoding은 MTP=ON 유지로 마감(TTFT 비개선, 디코드 속도 전용)
* [x] T-348 영어 도구명 UI 제거: 승인 팝업·칩 툴팁을 한글 제목으로 교체 (ToolCatalog.title 매핑, 306/306+build OK)
* [x] T-349 일정·미리 알림 삭제 도구: delete_calendar_event·delete_reminder 추가 (제목 일치·날짜 협소, 권한+승인, 309/309+build OK)
* [x] T-350 서버 도구 인자 정규화: 인자 없는 도구의 빈/공백/null → 빈 객체, 데몬 중복 조각(`{}{}`)은 첫 완전 객체 채택, 실패 시 원문 로그. 실측: get_system_info·read_clipboard 모두 정상 실행 (310/310+build OK)
* [x] T-351 1턴 병렬 도구 호출 유도: 시스템 프롬프트 `[도구 병렬 규칙]`+본문 `parallel_tool_calls: true` (기존 runTurnCalls 멀티콜 루프 재사용). curl 실측: 한 응답에서 read_clipboard+get_system_info 동시 방출 확인 (311/311+build OK, 눈확인 완료)
* [x] T-352 웹 검색 wigolo→Exa REST 교체: `api.exa.ai/search`(`contents.highlights`)·`/contents`(text) Bearer 호출+순수 파서 `parseExaSearch`/`parseExaContents`, 등록 게이트를 바이너리→API 키 존재로 전환, 설정 도구 탭 Exa 키 필드+`dashboard.exa.ai` 링크+실검색 테스트, wigolo 코드·설정 UI·배너·데몬 전면 삭제(4파일 정리, WigoloManager/Support 삭제). (305/305+lint 신규0+build OK, Exa 키 실측 대기)
* [x] T-353 Exa 라이브 크롤 강제: 검색·contents 요청에 `maxAgeHours: 0` — 기본 캐시가 GitHub 릴리스 페이지를 v0.16.1에서 멈춘 낡은 본문을 반환(실측, 실제 최신 v0.17.1). 라이브 크롤 시 v0.17.1 확인. 요청 본문을 순수 `searchBody`/`contentsBody`로 분리+도구 설명에 "예고만 하고 멈추지 말고 즉시 호출" 보강. (306/306+build OK, 눈확인 완료)
* [x] T-354 Exa 비용 절충+웹 규칙: 검색은 캐시 허용(지연·크레딧 절약), `web_fetch`(contents)만 `maxAgeHours: 0` 라이브. 시스템 프롬프트에 `[웹 결과 활용 규칙]`(본문 있으면 바로 답, 부족하면 즉시 web_fetch, "확인해 보겠습니다"만 하고 끝내지 말 것)을 1턴·재전송 턴 모두 주입. (307/307+build OK, 눈확인 완료)
* [x] T-355 메뉴바 NSStatusItem+NSPopover 전환: `MenuBarExtra(.menu)`를 Etchost식 수동 상태 아이템으로 교체. `StatusItemController`가 버튼에 기존 `MenuBarLabel`(칩+상태 점)을 호스팅 뷰로 얹고, 클릭 시 아이콘 아래 팝오버(상태 카드: 상태·:9379·가동시간·모델 + 빠른 동작: 서버 시작/중지·새 채팅·최근 채팅방 3·메인 창·모델 관리·설정·종료)를 띄운다. 씬 밖이라 `openWindow` 불가 → `.openMainWindow` 노티(+AppKit 폴백). 동기화: `daemon`·`chat`·`nativeEngine`을 팝오버/라벨이 직접 구독(AppServices는 중첩 변경 미전파), 점·문구·툴팁·토글 버튼(`MenuBarActionText`: 서버 시작/중지 ↔ 앱 내 엔진 준비/중지)이 현재 전송 경로를 반영. `AppServices.shared`(약참조) 주입. (311/311+build OK+lint 신규 0, 눈확인 대기)
* [x] T-356 설정 창 탭 깜빡임 수정: 일반·채팅·도구 탭의 바깥 `ScrollView` 중첩(T-320 잘림 대응으로 추가)이 탭 바 hover 시 `NSTabView` 재레이아웃마다 안쪽 스크롤을 재측정시켜 탭 영역이 깜빡였다(MCP·스킬은 `Form(.grouped)` 단독이라 무증상). 바깥 `ScrollView`+잉여 `.padding(.bottom, 32)` 제거로 5탭을 `Form(.grouped).padding()`으로 통일. (311/311+build OK+lint 신규 0, 눈확인 대기)
* [x] T-357 설정 창 좌우 여백 정리: 5탭이 `.formStyle(.grouped)` 위에 균일 `.padding()`(16pt)을 더해 좌우가 상하의 약 두 배. 좌우는 grouped 네이티브 인셋에 맡기고 세로만 여백을 주는 공용 모디파이어 `View.dsSettingsForm()`(`Components.swift`)으로 5곳 통일, 설정 창 최소 폭 580→560. (311/311+build OK+lint 신규 0, 눈확인 대기)
* [x] T-358 설정 창 좌우 여백 근본 수정: T-357로도 좌우가 상하보다 넓게 보인 원인은 패딩이 아니라 창 크기였다 — SwiftUI `Settings` 씬은 `defaultSize`가 없어 macOS 기본 900×508로 뜨고, 내용 최소 폭(560)이 그보다 좁아 grouped `Form`이 행을 가운데 정렬된 열로 배치하며 좌우에 ~170pt씩 잉여 여백이 생겼다. 내용 폭을 `minWidth/maxWidth 600`으로 고정 + `Settings` 씬에 `.windowResizability(.contentSize)`로 리사이즈 잠금 + `dsSettingsForm()`을 사방 균일 `.padding(DSSpace.l)`로 되돌리고, 저장된 900pt 프레임 키(`NSWindow Frame com_apple_SwiftUI_Settings_window`)를 1회 삭제. AX 실측: 설정 창 600×508, 콘텐츠 좌 16/우 16·섹션 카드 좌 36/우 36 대칭(하단 16과 일치). 창 제목도 SwiftUI가 선택 탭 이름(일반/채팅/…)으로 덮어써 "LiteRT-LM Studio 설정"으로 고정 필요 → 공용 폼에 `SettingsWindowTitleSetter`(KVO로 `title` 감시 후 재고정) 부착. 5탭 전환 모두 제목 "LiteRT-LM Studio 설정" 유지 확인. (311/311+build OK+lint 신규 0, 눈확인 대기)
* [x] T-359 설정 탭 재구성(분류 감사 후 재배치): 오분류 4건 교정 — ①`웹 도구 사용`(채팅)→도구>웹(Exa와 통합) ②`대화 기록 전송`(일반>대화)→채팅>동작 ③`첫터치 프리필`(채팅)→일반>시스템 ④`벤치마크 기록 보관`(일반>대화)→일반>고급. 채팅 탭에 섹션 헤더(`표시`·`동작`)와 신규 2설정(채팅 글자 크기=`chatFontScale` 슬라이더 0.7~2.0·기본값 버튼, 세션 정렬=`sessionSort` 3종) 추가, 도구 탭 작업폴더를 `파일·셸` 섹션으로. **엔진 설정 이중화 해소**: 설정 탭의 `MTP`·`적용`(⌘S) 제거하고 인스펙터 `BackendSectionView`로 일원화 → `SettingsView`가 `ConfigStore` 의존을 버려 설정 창을 열 때 `config.load()`의 `revert()`가 인스펙터 미저장 변경을 조용히 취소하던 회귀도 함께 해소. (311/311+build OK+lint 신규 0 file 351줄, 눈확인 완료)
* [x] T-360 경고 정리(동작 불변): swiftlint 11건 → 0. ①파일 길이: `ToolCallFormat`(ToolEvents 447→333)·후속질문 뷰 3종(FollowUpSuggest 403→350)·벤치마크 확장(NativeEngine 398→367)을 각각 새 파일로 분리 ②함수 길이: `streamEvents`→`StreamInput`+`pump`/`pumpWithRetry`, `request`→`performRequest(_ PendingRequest)`(파라미터 6→1), `runServerTurns`→`streamServerTurn` ③복잡도: `firstObjectEnd`의 문자 스캔을 `JSONObjectScanner`로 분리, `statement_position`은 `} else if`로 ④`type_body_length`(268): 캐시 수명주기 5개 함수를 같은 파일 확장으로 ⑤`large_tuple`: `getCachedBackends` 튜플→`CachedBackends` 구조체. 컴파일러 경고: 헤더맵 경고는 `ALWAYS_SEARCH_USER_PATHS=NO`로 제거, 앱 코드 2건(`FollowGate.find` superview → `MainActor.assumeIsolated`, `DaemonManager.port` → `nonisolated`)도 정리. 남은 2건은 벤더 `Core/LiteRTLM`(Conversation·ToolManager Sendable)로 T-010 정책상 미수정. (311/311+build OK+lint 0)
* [x] T-361 다국어 인프라(언어 설정): `Core/Localization.swift`(AppLanguage system/ko/en, `L10nKey`, `LanguageStore`(NSLock, 코드별 `.lproj` 번들 조회), `L`/`T`/`LK` 전역 함수, `LanguageManager`(`appLanguage` 기본 `.system`, 변경 시 `objectWillChange`+`AppleLanguages` 기록, 다음 실행 시 시스템 소문자 일치), `View.languageAware`(locale 주입+`.id` 강제 리빌드)) + `Core/LocalizationKeys.swift`(`L10n` 시맨틱 키 레지스트리) + `Localizable.xcstrings`(sourceLanguage ko, ko/en 9키) + 설정>일반>외관에 언어 세그먼트(시스템/한국어/English)와 "즉시 적용, 시스템 문구는 다음 실행" 안내. pbxproj에 4파일 등록, `LOCALIZATION_PREFERS_STRING_CATALOGS=YES`(자동 추출은 `SWIFT_EMIT_LOC_STRINGS=NO`로 차단). 커버리지 테스트 `LiteRTLMStudioLocalizationTests`(ko/en 키 집합 일치·미번역 검출). (315/315+build OK+lint 0, 눈확인 대기)
* [x] T-362 키 체계 + 순수 로직 전환: `L10n` 네임스페이스를 Appearance·Permission·Engine·History·Status·Benchmark·ModelCatalog·Model(stage)·Session·Sidebar·Inspector·Skill·Time·ToolStatus·MenuBar까지 확장하고, 표시 문자열을 만들던 순수 로직을 키 기반으로 전환 — `ToolCatalog`(`tools.<name>.title|detail` 파생, 카테고리 rawValue ASCII화)·`ModelAlias.modalities(_:)`(구 modalitiesKorean)·`ModelCatalog`(family/sort)·`BenchmarkHistory`(stage/estimate/elapsed/status/retention/summary/analysis + `allModelsToken`으로 표시-저장 분리)·`ModelStore.StageState`·`ChatStore`·`SkillsStore`·`UnifiedStatus`·`MessageBubbles.chatRelativeTime`(appLocale+템플릿)·`MenuBarStatusText`·`MenuBarRouteStatus`·`MenuBarActionText`. `BenchmarkView`/`BenchmarkWindowSections`의 "전체 기록" 센티넬을 토큰으로 교체. 키 전수 인덱스는 `Core/LocalizationKeyIndex.swift`로 분리(파일 길이·type_body_length 회피). 카탈로그 147키(도구 40 포함) ko/en. 테스트는 `LiteRTLMStudioTestCase`(한국어 고정)로 결정화하고, 로컬라이징 테스트를 7종(ko/en 키 집합·미번역·선택 언어 조회·전 키 해석·포맷 인자·영어 전환 시 순수 헬퍼)으로 보강. (318/318+build OK+lint 0)
* [x] T-363 화면 문구 치환: 사용자 UI 리터럴 약 401건을 전부 `L(L10n.…)`로 교체(영역별 12커밋: MCP·스킬 → 웰컴/정보/팔레트 → 카탈로그/가져오기 → 시스템 모니터·디버그·메뉴바·단축어 → 창 제목/앱 메뉴/마크다운). 치환 시 기존 한국어를 카탈로그 ko 값으로 그대로 옮겨 적었고, 레지스트리 724키·카탈로그 764키. 남은 한국어는 `DebugLogger` 로그·도구 실행 결과·모델 프롬프트·초성 검색/한국어 날짜 파서로 의도적 유지(DebugPanelView 로그 표시 포함). 창 제목·앱 메뉴는 SwiftUI 씬/메뉴가 1회 구성되어 전환은 다음 실행 반영. (318/318+build OK+lint 0)
* [x] T-364 카탈로그 ko/en 확정: 표시 문자열을 만들던 Core 로직까지 키로 전환 — `ConfigStore.diffSummary`(켬/끔·자동·기본·무제한·내장 + 스레드/캐시/MTP/KV/Thinking/예산/정밀도), `ModelCatalog` 추천 설명 8종·목록/상세 조회 실패, `ToolCallFormat` 인자 라벨(내용·코드·N일·완료 포함), `ChatStore.perfLine`(%.1fs · 약 %d 토큰/초)와 오류 버블 6종, `NativeEngine` 준비 실패 사유, `ModelDownloader` 오류 5종, 세션 기본 제목(`session.new` 재사용), `BatteryStatus.powerLine`(MTP/배터리), 후속질문 칩 툴팁·접근성 레이블. 커버리지 테스트가 전 키 해석과 ko/en 집합 일치를 검증해 누락을 차단(레지스트리 774키, 카탈로그 814키, ko/en 100%). (318/318+build OK+lint 0)
* [x] T-365 한국어 문구 다듬기: 카탈로그 ko·en 814키를 korean-humanizer 패턴(번역체·피동·hype·3의 법칙·연결어미 뒤 쉼표·줄표·이모지·hedging)으로 전수 스캔 — 번역체·피동·hype는 0건이었고, 연결어미 뒤 쉼표 1건(`skill.noSkillMD`)과 줄표 표시 문구 20건(menuBar.tooltip·failed, engineNotice.noModel, import.*, inspector.*, server.*, sidebar.externalRestart/status.help, welcome.*, exa.test.success, settings.followUpEnabled.help, benchmark.estimate.*)만 정리. 런타임 조합 툴팁 2곳(SidebarView·CatalogBrowserView)도 가운뎃점으로 통일하고 테스트 단언 3건 동기화. 로그·도구 결과·프롬프트·초성 검색은 대상 제외 유지. (319/319+build OK+lint 0)
* [x] T-366 시스템 표면 + 문서: `InfoPlist.xcstrings`(권한 설명 4건 ko/en, `InfoPlist.strings` 컴파일 검증 테스트), `error_message_ko.json`(E-MAC-* 29개)을 `error.<코드>` 키로 카탈로그 이관 후 JSON·pbxproj 등록·테스트 번들 리소스 삭제(코드 전수 ko/en 해석 테스트로 대체), 원문 중복 표현("앱 내 엔진 엔진") 정리, README(한/영)·사용설명서·CHANGELOG 언어 안내. 창/메뉴 제목의 즉시 갱신은 SwiftUI 씬·메뉴가 1회 구성되어 다음 실행 반영(사용자 눈확인 대기). (319/319+build OK+lint 0)
* [x] T-367 릴리스 0.7.150: PR #3 머지(`fb574be`) → 태그 `v0.7.150` → GitHub Release 생성, README(한/영) 스크린샷 4종(`docs/images/`) 추가, CHANGELOG를 릴리스 요약으로 정리하고 상세 136건을 `docs/CHANGELOG-DETAIL.md`로 분리, main 재빌드·설치(0.7.150), 머지된 브랜치 로컬·원격 정리(원격에는 `main`만 남김). (319/319+build OK+lint 0)
* [ ] T-368 남은 눈확인: 언어 전환 후 **창 제목·앱 메뉴**가 다음 실행에 반영되는지(앱이 그리는 UI는 즉시), 시스템 권한 대화상자 문구가 선택 언어로 뜨는지 — 사용자 확인 필요
* [x] T-369 안정화 S 번들: E-MAC-PERF-0001 카탈로그 매핑+BenchmarkHistory 원자 쓰기+ChatStore.send 전송 가드+Markdown `.auto` 실효 테마 (323/323+lint 신규 0)
* [x] T-370 릴리스 게이트: release.yml에 unit 테스트 스텝 추가+태그·MARKETING_VERSION 불일치 시 실패 처리 (수동 실행은 통과)
