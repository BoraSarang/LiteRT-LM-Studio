# session-2026-09-16-macos — T-216~227 벤치마크 별도창+후속 안정화

1. 무엇을: 시트 자동시작 → 별도창+수동 시작, 예상/경과 시간, 단계 콜백, 중지 즉시 반영, 히스토리(보관 10 기본/50/100/무제한), 사이드바 최근 3건, 현재 채팅모델 AI 분석(마크다운+프롬프트 공개).
   후속: T-220 창 레이아웃(264 고정폭+헤더 2줄)+T-221 "측정 전" 버그(명시 선택 최우선)+T-222 MTP 끔 기본+전원 경고+T-223 엔진 표기 분리+복사+T-224 기록별 분석·원문 분리+T-225 사이드바 채팅식+T-226 새 측정 상단 고정+T-227 분석 경로 추종.
2. 플랫폼: macOS 단일, SwiftUI만, xcodebuild만. AppServices에 bench/history/chat/models 상주, ContentView는 주입.
3. 빌드+PERF+CACHE: unit 125/125, lint 신규 0건(기존 수용 3건), xcodebuild build SUCCEEDED(open 없이). PERF/CACHE 영향 없음(벤치 실행 시에만 동작).
4. 남은TODO: T-215 간헐 미도달 방(추후). 눈확인 대기: 벤치마크 창 열기·측정 시작·중지·분석·사이드바 선택·설정 보관·MTP 경고·헤더 표기.
5. 전달로그: ContentView body 솔버 타임아웃 5회 — 동명 오버로드 가설 기각(`benchmarkWithProgress` 분리 후에도 재현), `.task` 본문을 `restoreState()`로 추출해 해결. BenchmarkHistory.swift 신규+pbxproj 등록(101).
   T-221 조건 제거(`store.metrics != nil`이 기록 분기 차단). T-223/224 슬롯별 분석 캐시+로그 100줄. pbxproj 5파일 정상 등록 확인(문자열 검색 오판 정정: BuildFile은 fileRef 링크만 가짐).
6. 문서갱신: PLAN_v41~v44+T-216~227 완료+DESIGN 벤치마크절+CHANGELOG Unreleased+사용설명서 4장+MTP 1줄. error_message_ko.json 변경 없음(기존 코드 재사용).
7. 큐상태: 미커밋 유지 (지시 전 커밋 금지). bd 없음으로 close 생략.
8. E2E: 해당 없음. 앱 실행 눈확인은 사용자 허락 후 (포커스 스틸 방지).

---

## T-228/T-229 전역 권한+입력창 모델 피커 (PLAN_v45)

1. 무엇을: 전역 단일 권한(사용 안 함/매번 묻기 기본/모두 허용)+전송·삭제 게이팅(E-MAC-PERM-0011),
   입력창 모델 Menu 내장(설치 목록·Gemma/Qwen 우선·사이드바 동기). 받아쓰기/녹음 제외.
2. 플랫폼: macOS 단일, SwiftUI만, xcodebuild만. GlobalPermission.swift 신규+pbxproj 등록(106).
3. 빌드+PERF+CACHE: unit 127/127, lint 신규 0건(기존 3건), xcodebuild build SUCCEEDED(open 없이). PERF/CACHE 영향 없음.
4. 남은TODO: T-215만 잔류. 눈확인 대기: 피커 동기·Off 차단·Ask 확인·Allow 직행·빈 목록 안내.
5. 전달로그: SidebarView 줄합침 1건 즉시 복원. BuildFile 문자열 검색 오판 재발 방지(숫자 ID 대조).
6. 문서갱신: PLAN_v45+TODO T-228/229 완료+CHANGELOG Unreleased+DESIGN 3줄+사용설명서 2곳+error 1건.
7. 큐상태: 미커밋 유지 (지시 전 커밋 금지). bd 없음.
   상시 지시: 빌드 후 항상 설치·실행 2번 고정 (AGENTS.local.md 기록, 포커스 확인 생략).
   T-228/229 설치·실행 완료 (15:00, 앱 실행 중).
8. E2E: 해당 없음.

---

## T-230 사이드바 탭 분리 (PLAN_v46)

1. 무엇을: 사이드바 상단 [채팅 | 모델] 2칸+환경 고정. 채팅 탭=대화 목록, 모델 탭=벤치마크+모델.
2. 플랫폼: macOS 단일, SwiftUI만. SidebarView.swift만+ContentView 영속 1줄, 로직 불변.
3. 빌드+PERF+CACHE: unit 128/128, lint 신규 0건, build 전체 설치·실행 완료. PERF/CACHE 영향 없음.
4. 남은TODO: T-215만 잔류. 눈확인: 탭 전환·재실행 유지·긴 목록 접근.
5. 전달로그: 없음 (이동만).
6. 문서갱신: PLAN_v46+TODO T-230 완료+CHANGELOG Unreleased+DESIGN 사이드바절.
   T-231 추가: 환경+탭 고정층 분리 (TODO·CHANGELOG·DESIGN 갱신, 128/128+build 설치·실행).
   T-231 후속: 모델 채팅식 개편+관리 버튼(껍데기)+엔진 route 규칙 3종+헤더 통일 (129/129+build 설치·실행).
   T-232 모델 관리 창은 미완 후속 (apps-docs 명세서 기준).
   T-231 후속 개명: CLI 데몬→서버, 네이티브→앱 내 엔진 (EngineMode.title 원천+하드코딩 2+문구 4+테스트 4, 129/129+lint 신규 0+build 설치·실행).
   T-231 후속 인스펙터: 앱 내 엔진 경로면 재시작 없이 저장만 (버튼·안내 경로별 표시, 129/129+build 설치·실행).
7. 큐상태: 정리 완료 — `chore/macos-commit-T-216-231` 2건 커밋 후 main fast-forward 병합.
   feat `cac715e` (코드 28파일) + docs `8c21558` (문서 11파일). 원격 없음으로 push 생략.
   작업 트리 깨끗 (`.agent/` 제외, 관례). bd 없음.
8. E2E: 해당 없음.

---

## 정리안 (미커밋 28수정+13미추적)

* ① `feat/macos-benchmark-window`: 벤치마크 별도창 T-216~227 (신규 4파일+BenchmarkView/Store/History/Power+테스트+pbxproj).
  pbxproj는 ①에 통째로 (GlobalPermission 등록 포함, 중간 분할 시 빌드 깨짐).
* ② `feat/macos-permission-picker`: T-228 권한+T-229 입력창 피커 (GlobalPermission/ChatInputBar/ChatPaneView/ModelStore/Settings/Sidebar삭제게이트+error 1건+테스트 2건).
* ③ `feat/macos-sidebar`: T-230 탭+T-231 고정·채팅식·route 규칙·개명·인스펙터 분기 (Sidebar/Content/Inspector/ServerActions/Config 표시무관·테스트 2건).
* ④ 문서는 각 커밋에 포함 (PLAN_v41~46/TODO/CHANGELOG/DESIGN/사용설명서).
* `.agent/`는 커밋 제외 (관례 유지). 원격 없음이라 push/PR 생략, main 병합만.
* 남은 미완: T-215 (스크롤 간헐), T-232 (모델 관리 창).

---

## T-232 모델 관리 창 (PLAN_v47)

1. 무엇을: 별도창(`Window(id:modelManager)`) 가져오기·목록·설치·삭제·이름변경.
   가져오기 시트(추천 프리셋 5종+직접입력·HF API 파일 목록·로컬ID·토큰),
   직접 다운로드→스테이징 `~/Documents/.LiteRT-LM` 숨김 유지(`.part`→완료 시 개명),
   진행 바+퍼센트+경과+남은시간+취소, 상태 3종, 설치(import)/rename/삭제, 목록 60초 캐시.
   진입: 사이드바 관리 버튼(껍데기 Alert→진짜 열기)+팔레트. 권한 게이트 가져오기·설치로 확대.
2. 플랫폼: macOS 단일, SwiftUI만, xcodebuild만. 신규 ModelDownload(순수+URLSession)+ModelManagerView/Sections,
   ModelStore 확장(스테이징·매핑·캐시·import/rename)+pbxproj 4건(107~110).
3. 빌드+PERF+CACHE: unit 134/134, lint 신규 0건(기준선 3건 유지), build 2회 SUCCEEDED+설치·실행 확인.
   `[CACHE]` 적중 로그. ContentView body 솔버 타임아웃 2회 — aliasBinding 분리 후 mainSplit/mainToolbar/
   rootDialogs/rootEvents 추출로 해결.
4. 남은TODO: T-215만 잔류. 눈확인 대기: 창 열기·파일 목록 조회·다운로드(소용량)·취소·개명·설치 후 `설치됨`·rename·삭제 게이트.
5. 전달로그: HF 컬렉션은 저장소 ID만 줌(파일명·로컬ID 별도). 최종 저장 `~/.litert-lm/models/<ID>/model.litertlm`
   실측(6.8GB+캐시, du 24G) — 스테이징 유지라 디스크 2배 안내 문구 포함. error E-MAC-STOR-0012 신규.
6. 문서갱신: PLAN_v47+TODO T-232 완료+DESIGN 관리창절+CHANGELOG Unreleased+사용설명서 4장·트러블슈팅 1행.
7. 큐상태: 미커밋 유지 (지시 전 커밋 금지). bd 없음으로 close 생략.
8. E2E: 해당 없음.

---

## T-233 가져오기 정리+상주화 (PLAN_v48)

1. 무엇을: ImportSheet 4섹션(1 모델→2 파일→3 저장→4 진행), 수동 불러오기 삭제·
   저장소/토큰 변경 시 0.5초 debounce 자동 재조회, 시작 후 입력 잠금+닫기만,
   에러 고정 슬롯, 중복 시작 가드. DownloadCenter를 AppServices 상주로 이동 —
   창 닫아도 계속+재오픈 시 진행·취소.
2. 플랫폼: macOS 단일, SwiftUI만, xcodebuild만. ModelDownload 순수 3건 추가
   (resolveFile/authHeader/hasActiveDownload)+ModelManagerSections 개편.
3. 빌드+PERF+CACHE: unit 137/137, lint 신규 0건, build 2회 SUCCEEDED+실행 확인.
   PERF/CACHE 영향 없음. no-op edit 병합 사고 2건 즉시 복원 (주석+선언 붙음).
4. 남은TODO: T-215만 잔류. 눈확인 대기: 섹션 흐름·자동 조회·잠금·시트 닫고 진행·
   창 닫고 재오픈·취소·완료 반영·소용량 실다운로드.
5. 전달로그: 세션 delegate가 downloader retain이라 기존도 뒤에서 계속 받았음.
   상주화로 핸들 상실 해소. 시트 activeItem은 center 참조라 닫혀도 안전.
6. 문서갱신: PLAN_v48+TODO T-233 완료+DESIGN 2줄+CHANGELOG+사용설명서 4장.
7. 큐상태: 미커밋 유지 (지시 전 커밋 금지). bd 없음.
8. E2E: 해당 없음.

---

## T-234 카탈로그형 개편 (PLAN_v49)

1. 무엇을: 관리 창 `[둘러보기 | 내 모델]` 탭. 둘러보기는 Staff picks 8종 기본+
   전체 확장(검색·패밀리·정렬·페이징 20건), 좌 목록→우 상세(메타+Download Options+
   README 전체)+푸터(로컬·용량·경로). 다운로드는 상주 center 연결.
   내 모델 탭·직접입력 시트는 유지.
2. 플랫폼: macOS 단일, SwiftUI만, xcodebuild만. 신규 ModelCatalog(파싱+Store)+
   CatalogBrowserView/Sections, ModelDownload HEAD 크기, ModelStore 용량합,
   error E-MAC-NET-0013, 창 1080×700. pbxproj 111~113.
3. 빌드+PERF+CACHE: unit 142/142, lint 신규 0건, build 2회 SUCCEEDED+실행 확인.
   PERF: 20건 페이징·아바타 캐시·크기 lazy. private @State 확장 접근 에러→
   internal 공개, Group guard 불가→상세 함수 분리로 해결.
4. 남은TODO: T-215만 잔류. 눈확인 대기: picks→전체→검색·필터·정렬·상세·크기·
   다운로드 반영·README·푸터·직접입력·오프라인 안내.
5. 전달로그: HF 목록 API에 크기 없음(상세 HEAD로 해결). PARAMS/ARCH 근사+참고용
   캡션. Tool/Reasoning은 설치 후 describe 확정 병기.
6. 문서갱신: PLAN_v49+TODO T-234 완료+DESIGN+CHANGELOG+사용설명서 4장.
7. 큐상태: 미커밋 유지 (지시 전 커밋 금지). bd 없음.
8. E2E: 해당 없음.

---

## T-235/T-236 소규모 수정

1. T-235: 미선택(`selectedRecordID == nil`) 시 "+ 새 벤치마크" 버튼에 선택 틴트 —
   `fresh` fill 제거, 새 채팅 규칙과 통일. unit 142/142, lint 신규 0.
2. T-236: 카탈로그 좌 목록 `minWidth 240/ideal 300` 가변 → 264 고정
   (벤치마크 기록 패널과 통일).
3. build 2회 SUCCEEDED+실행 확인. CHANGELOG 2행.
4. 남은TODO: T-215만 잔류. 커밋 미커밋 유지.

---

## T-237~240 카탈로그 다듬기 묶음 (PLAN_v50)

1. T-237 README HTML 표: `<table>` 구간 → ProseBlock.table 변환, 링크 셀 파일명만,
   잡태그 스트립. 헬퍼 6종 NativeMarkdownHTML.swift 분리 (길이 경고 해소).
2. T-238 추천 모델: Staff picks 노출 2건+내부(타입·함수·mode 케이스) 정리.
3. T-239 용량: HEAD 리다이렉트 차단(NoRedirectDelegate)+x-linked-size 우선+
   Range 폴백. 302 실측 근거.
4. T-240 탭·필터: segmented 고정폭 → 전폭 버튼 (탭 50/50·패밀리 4등분),
   찾아보기·내 모델. AGENTS.local 규칙 1줄 추가.
5. 빌드+PERF+CACHE: unit 146/146, lint 신규 0건, build 2회 SUCCEEDED+실행 확인.
6. 남은TODO: T-215만 잔류. 눈확인 대기: 표 렌더·용어·전폭 탭·용량 표시·추천 목록.
7. 문서갱신: PLAN_v50+TODO 4건 완료+DESIGN+CHANGELOG+사용설명서+AGENTS.local.
8. 큐상태: 미커밋 유지. bd 없음. E2E 해당 없음.

---

## T-241 아바타 교체 + 140B 후속 수정

1. T-241: `/{org}/avatar` 401 실측, org API도 없음, cdn 해시는 추정 불가 —
   원격 아바타 폐기, 패밀리 이니셜 뱃지(Gemma 파랑·Qwen 보라·기타 회색).
   avatarURL 삭제+호출부 3건 교체.
2. 140B: 구 빌드(추종 HEAD)의 CDN 140B 잔재 + T-239 초안에 302 본문 길이
   오인 구멍. `sizeFromHead` 상태 가드 추가 (2xx만 인정).
3. unit 146/146, lint 신규 0건, build 2회 SUCCEEDED+실행 확인.
4. 눈확인 대기: 뱃지 표시·상세 용량 GB 표시 (구 빌드 잔재 주의).
5. 문서: TODO T-241 완료+CHANGELOG 2행.

---

## T-242 게이트 저장소 대응

1. 원인: google 계열 게이트 저장소 401 (라이선스 승인 필요) + 찾아보기 탭에
   토큰칸 없음 + 실패가 상세에 미표시 → 무반응 체감.
2. 처방: 상세 Download Options에 토큰 SecureField(세션 유지)+캡션,
   401/403 특화 문구 직접 표시(httpErrorMessage), 파일 변경 시 빈 ID 제안.
   Self 오참조 1건 수정 (ModelDownloader→ModelDownload).
3. unit 147/147, lint 신규 0건, build 2회 SUCCEEDED+실행 확인.
4. 눈확인 대기: E4B 토큰 없이 → 승인 안내 / 토큰 입력 후 진행.
5. 문서: TODO T-242 완료+CHANGELOG 1행.

---

## T-243 HF 수동 다운로드 링크

1. 상세 Download Options에 "수동 다운로드" 링크 추가 (HF 파일 목록 tree/main).
   `repoTreeURL` 헬퍼+회귀 1건. 함수 길이 경고는 행 분리로 해소.
2. unit 147/147, lint 신규 0건, build 2회 SUCCEEDED+실행 확인.
3. 문서: TODO T-243 완료+CHANGELOG 1행.

---

## T-244~248 다운로드 버튼·진행바·일원화 (PLAN_v51)

1. T-244 속도+시작 문구: statusLine 평균 속도, 다운로드 누르면 요청 문구.
2. T-245/T-246/T-248: 닫기→삭제+컨펌, 일시정지·이어받기(Range 206/200)·
   완전취소·다시 받기, 중복가드 downloading만, Web Island식 행.
   ModelDownloader.swift·DownloadRowView.swift 분리 등록 (115/116).
3. T-247 일원화: 사이드바 삭제→관리창 이동+3초 하이라이트,
   내 모델에 선택·벤치마크 이식, 직접삭제 코드 제거.
4. unit 149/149, lint 신규 0건, build 2회 SUCCEEDED+실행 확인.
5. 눈확인 대기: 일시정지→이어받기 실측·취소·삭제컨펌·바·이동·하이라이트.
6. 문서: PLAN_v51+TODO 5건 완료+CHANGELOG+사용설명서 4장.

---

## T-249/T-250 재실행 복원+삭제 분리 (PLAN_v52)

1. T-249: 큐 영속(`.queue.json` 원자 쓰기, 토큰 제외)+재실행 일시정지 복원+
   미완성 고아 표시·삭제. final 존재분 완료 처리. 매핑 원자 쓰기.
2. T-250: 모델 삭제(레지스트리, 파일 유지)+체크박스 연쇄+파일 삭제(설치 유지 경고)+
   stale 매핑 퍼지. stagedFileForModel 순수 함수.
3. unit 151/151, lint 신규 0건, build 2회 SUCCEEDED+실행 확인.
4. 눈확인 대기: 종료→복원·이어받기·고아 삭제·3경로 삭제·사이드바 이동.
5. 문서: PLAN_v52+TODO 2건 완료+CHANGELOG+사용설명서 4장+DESIGN 현행.

---

## T-251 고아 다시 받기

1. 미완성행 [다시 받기]: 찾아보기 탭+stem 정제 검색어 자동 검색+덮어씀 안내.
   검색창을 catalog.query 직결로 변경 (외부 설정 반영).
   orphanRow Sections 분리 (파일 길이 경고 해소).
2. unit 152/152, lint 신규 0건(전체 3건 기준선), build 2회 SUCCEEDED+실행 확인.
3. 문서: TODO T-251 완료+CHANGELOG+사용설명서 1행.

---

## T-252 고아 직접 이어받기

1. 매핑 값 확장 `{localID, repo}` + 구 문자열 형식 호환 디코드.
   설치·가져오기 성공 시 repo 기록, rename 보존, 호출 7곳 동반 수정.
2. 고아 행: repo 알면 [이어받기] 직접 (URL 복원+stageForResume),
   모르면 [다시 받기] 유지.
3. ImportSheet 분리 (파일 길이), ModelTests IO 분리 (본문 길이).
4. unit 153/153, lint 신규 0건, build 2회 SUCCEEDED+실행 확인.
5. 문서: TODO T-252 완료+CHANGELOG+사용설명서 1행.

---

## T-253 실제 파일명 동기화

1. 상세 파일 변경 시 로컬 ID를 stem으로 항상 동기화 (빈칸 조건 삭제).
   초기 선택값도 상세 로드 시 stem으로 정정됨. fileStem 순수 함수+회귀.
2. unit 154/154, lint 신규 0건, build 2회 SUCCEEDED+실행 확인.
3. 문서: TODO T-253 완료+CHANGELOG 1행.

---

## T-254/T-255 파일 설치+전송 확인 제거

1. T-254: 내 모델 헤더 `파일로 설치`+NSOpenPanel→스테이징 복사(원본 유지·
   동명 실패). isInstallableFile 순수+회귀.
2. T-255: 전송 확인 제거 (전송 항상 허용). 권한은 삭제·가져오기·설치+
   장래 도구 실행용 재정의. 설정 문구 수정.
3. unit 155/155, lint 신규 0건, build 2회 SUCCEEDED+실행 확인.
4. 문서: TODO 2건 완료+CHANGELOG+사용설명서 2곳.

---

## T-257 온보딩 게이트 랜딩

1. 첫 실행 랜딩: uv·litert-lm 확인 후 시작, 미설치 안내+복사+재확인,
   저버전 경고만 (차단 아님). uv 소실 시 게이트 복귀.
2. OnboardingGate 순수 2종+회귀. restoreState·wireBenchmark 분리.
3. unit 156/156, lint 신규 0건, build 2회 SUCCEEDED+실행 확인.
4. 문서: PLAN_v53+TODO 완료+CHANGELOG+사용설명서 1장.

---

## T-258 대화 목차 플로팅

1. 우측 중앙 플로팅: 바 3개→호버 확장, 질문 첫 줄 40자 목록 (AI Model Talk 규칙).
   클릭 점프+핀 해제+1.5초 플래시. 설정 채팅 탭 토글 (기본 켬).
2. ChatOutlineView 신규+행 배경 플래시 (버블 수정 없음). 회귀 3건.
3. unit 159/159, lint 신규 0건, build 2회 SUCCEEDED+실행 확인.
4. 문서: PLAN_v54+TODO 완료+CHANGELOG+DESIGN+사용설명서.

---

## T-259 목차 호버 유지+투명

1. 바에서 패널로 옮기면 접히던 문제: 호버를 컨테이너 전체로 + 0.3초 지연 접힘.
   패널 배경 50% 투명.
2. lint 0건, build 2회 SUCCEEDED+실행 확인 (동작 수정이라 unit 추가 없음).

---

## T-259/T-260 목차 후속+핀 해제

1. T-259: 호버 컨테이너 전체+0.3초 지연 접힘+패널 50% 투명.
2. T-260: 수동 휠 무반응 원인=핸들러가 시각만 기록. 스탬프 시
   requestPinCheck 발행→뷰에서 reconcilePin+해제 로그.
   struct weak 캡처 불가 교훈: 상태 변경은 Notification 경유.
3. unit 159/159, lint 신규 0건, build 2회 SUCCEEDED+실행 확인.
4. 문서: TODO 2건 완료+CHANGELOG.
