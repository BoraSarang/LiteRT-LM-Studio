# PLAN v73 — MCP 클라이언트 + 스킬 (T-285)

## 목표

* 외부 MCP 서버(stdio·SSE) 연결, 게이트웨이 2종으로 모델 노출.
* SKILL.md 폴더 스캔+토글+시스템 프롬프트 주입.

## 변경

* `Core/MCPClient.swift`·`MCPStore.swift`·`MCPTools.swift`·`SkillsStore.swift` (신규).
* `LocalTools`+`ToolCatalog` 2행, 프롬프트 합성 양 경로, Settings 2탭.
* `E-MAC-NET-0016`, 문서 일체.
