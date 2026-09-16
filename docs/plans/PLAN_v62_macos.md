# PLAN v62 — 웹 검색 도구 (macOS, T-269)

## S-0 결과

* Node 22 존재, `~/.wigolo` 초기화済(249M), CLI 미설치 → 설치·실측은 사용자 몫.
* 계약 (문서 확정): `POST 127.0.0.1:3333/v1/{search,fetch}`,
  search req `{query,max_results}` / res `{results[{title,url,excerpt,citation_id}]}`,
  fetch → 마크다운+메타. 전 필드 optional 디코딩으로 방어.
* 폴백: DDG Instant Answer API (공식·키없음) → Wikipedia opensearch (공식·키없음).

## 변경

* `Core/WebSearch.swift` (신규): 체인+파서+`WebSearchTool`·`WebFetchTool`.
* `Core/WigoloManager.swift` (신규): 데몬 생명주기+바이너리 탐색+헬스체크.
* `LocalTools.registered()` 2종 추가 (토글+권한 게이트).
* 설정 토글+설치 안내, `E-MAC-NET-0015`, 문서 일체.
