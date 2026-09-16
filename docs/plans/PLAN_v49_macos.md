# PLAN v49 — 카탈로그형 모델 관리 (macOS, T-234)

## 1. 목표

* 관리 창을 LM Studio식 카탈로그형으로 개편. 상단 `[둘러보기 | 내 모델]` 탭.
* 둘러보기: Staff picks 기본 + `[전체 모델 보기]` 확장, 검색·패밀리·정렬,
  좌 목록 → 우 상세(메타+Download Options+README 전체) → 기존 상주 downloader 연결.
* 내 모델: 기존 3층(다운로드 중·설치됨·스테이징)+직접입력 시트 유지.

## 2. 목록 정책 (확정)

* 첫 화면 Staff picks 8종 (수동 큐레이션, 순서 고정).
* `[전체 모델 보기]` → HF API 페이징 20건씩 (다운로드순 기본).
* 검색창 입력 시 전체 모드 자동 전환. 전체 모드에서만 필터·정렬 활성.

## 3. 데이터 (HF API 실측)

* 목록: `GET /api/models?search=&filter=litert-lm&sort=&direction=-1&limit=20`
  (id·likes·downloads·tags·pipeline_tag·createdAt).
* 상세: `GET /api/models/{id}` (lastModified·siblings·cardData).
* 크기: 선택 파일만 HEAD lazy 조회 (목록 N+1 금지).
* README: `{repo}/resolve/main/README.md`, NativeMarkdown 재사용.
* 아이콘: 조직 아바타 AsyncImage + SF Symbol 폴백.
* PARAMS/ARCH 근사 + "참고용" 캡션. Tool/Reasoning은 설치 후 describe 확정 병기.

## 4. 변경

* `Core/ModelCatalog.swift` 신규: `CatalogEntry` 순수 파싱(목록·상세·뱃지·params·
  쿼리 빌더·siblings 필터) + `CatalogStore` (검색·모드·상세·README·크기·캐시).
* `CatalogBrowserView.swift` (+Sections) 신규: 탭·검색·Staff picks·필터·목록·
  상세·Download Options·README·푸터(로컬 n개·용량 합·경로).
* `ModelManagerView`: 탭 껍데기 (둘러보기=브라우저, 내 모델=기존 유지).
* `ModelDownload`: HEAD 크기 조회 1함수. `ModelStore`: 스테이징 용량 합 1함수.
* `error_message_ko.json`: 조회 실패 E-MAC-NET-0013. 창 최소 900×640.
* 회귀 6건: 목록 파싱·상세 파싱·뱃지·쿼리·siblings·용량합.

## 5. 검증

* unit 143/143 + lint 신규 0 + `build macos` 2회 + DebugPanel ERROR 0.
* 눈확인: picks→전체→검색·필터·정렬·상세·크기·다운로드 반영·README·푸터·직접입력.
* 오프라인·레이트리밋 안내+재시도. PERF: 20건 페이징·아바타 캐시.
