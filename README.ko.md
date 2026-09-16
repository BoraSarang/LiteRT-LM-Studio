# LiteRT-LM-Studio

[LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM)용 macOS 네이티브 클라이언트 (SwiftUI) — 채팅, 벤치마크, 모델 관리.

> English version: [README.md](README.md). 전체 사용법은 [docs/사용설명서.md](docs/사용설명서.md) 참조.

## 기능

- **채팅** — 스트리밍 응답, Vision 이미지 첨부, 대화 목록, 마크다운 렌더, 글씨 크기 조절
- **벤치마크** — 별도 창, 히스토리 보관, AI 결과 분석
- **모델 관리** — Hugging Face 카탈로그 둘러보기, 진행률 다운로드(일시정지·이어받기), 설치·이름변경·삭제
- **실행 경로** — 서버 데몬 (`litert-lm serve`) 또는 앱 내 엔진 (프로세스 내 추론)
- **시스템 현황** — CPU/RAM/GPU 미터, 데몬 통계, 디버그 패널

## 요구 사항

- macOS 14+ (Apple Silicon 권장)
- [`uv`](https://docs.astral.sh/uv/) (`/opt/homebrew/bin/uv` 경로)
- `litert-lm` CLI (`uv tool install litert-lm`)
- 모델 위치: `~/.litert-lm/models`

## 빌드·실행

```sh
./build_and_run.sh build macos   # 빌드 후 ~/Applications에 설치·실행
./build_and_run.sh test macos unit
```

서버는 `127.0.0.1:9379` 고정.

## 프로젝트 구성

- `LiteRTLMStudio/` — SwiftUI 앱 본체
- `LiteRTLMStudio/Core/` — 스토어, 엔진, 마크다운, 다운로드 센터
- `LiteRTLMStudioTests/` — 단위 테스트
- `docs/` — PLAN·TODO·DESIGN·CHANGELOG·사용설명서

## 라이선스

Apache-2.0 (LiteRT-LM과 동일).
