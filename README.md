# LiteRT-LM-Studio

macOS native client for [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) (SwiftUI) — chat, benchmarks, and model management.

> 한국어 문서는 [README.ko.md](README.ko.md) 참조.

## Features

- **Chat** — streaming responses, Vision images, sessions, Markdown rendering, font zoom
- **Benchmarks** — separate window, history, AI analysis of results
- **Model catalog** — browse Hugging Face (`litert-community`, `google`), download with progress (pause/resume), install/rename/delete
- **Engines** — Server daemon (`litert-lm serve`) or in-app engine (process-local inference)
- **System monitor** — CPU/RAM/GPU meters, daemon stats, debug panel

## Requirements

- macOS 14+ (Apple Silicon recommended)
- [`uv`](https://docs.astral.sh/uv/) at `/opt/homebrew/bin/uv`
- `litert-lm` CLI (`uv tool install litert-lm`)
- Models in `~/.litert-lm/models`

## Build & Run

```sh
./build_and_run.sh build macos   # build, install to ~/Applications, launch
./build_and_run.sh test macos unit
```

The server runs at `127.0.0.1:9379` (fixed).

## Project Layout

- `LiteRTLMStudio/` — SwiftUI app (`ContentView`, `SidebarView`, `ChatPaneView`, …)
- `LiteRTLMStudio/Core/` — stores, engines, markdown, download center
- `LiteRTLMStudioTests/` — unit tests
- `docs/` — plans, TODO, design notes, changelog (Korean)
- `docs/사용설명서.md` — full user manual (Korean)

## License

Apache-2.0 (same as LiteRT-LM).
