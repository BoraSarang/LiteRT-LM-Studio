# LiteRT-LM-Studio

macOS native client for [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) (SwiftUI) — local chat with tools, benchmarks, and model management.

> 한국어 문서는 [README.ko.md](README.ko.md)를 참조하세요. 전체 사용법은 [docs/사용설명서.md](docs/사용설명서.md) (Korean)에 있습니다.

## Highlights

- **Chat** — streaming responses, Vision image attachments, sessions with a table-of-contents panel, follow-up suggestions, Markdown rendering, adjustable font size, and session sorting
- **Tools** — web search (Exa REST), filesystem & shell, system info, clipboard read/write, calendar & reminders, URL open, and Shortcuts, each gated by a per-app permission model (**off · ask every time · allow all**)
- **MCP & Skills** — connect stdio/SSE MCP servers and enable local skills whose bodies are prepended to the system prompt
- **Engines** — run through the server daemon (`litert-lm serve`) or the in-app engine (in-process inference), selectable per message from the chat input picker
- **Model catalog** — browse Hugging Face (`litert-community`, `google`), download with progress (pause / resume), install, rename, and delete
- **Benchmarks** — dedicated window with history and AI analysis of results
- **Menu bar** — status item with a popover showing engine state, uptime, and model, plus quick start/stop and recent chats
- **System monitor** — CPU/RAM/GPU meters, daemon stats, and a debug panel

## Requirements

- macOS 14 (Sonoma) or later; Apple Silicon recommended
- [`uv`](https://docs.astral.sh/uv/) at `/opt/homebrew/bin/uv`
- `litert-lm` CLI — install with `uv tool install litert-lm`
- Models in `~/.litert-lm/models`

## Build & Run

```sh
./build_and_run.sh build macos    # build, install to ~/Applications, and launch
./build_and_run.sh install macos  # build and install without launching
./build_and_run.sh test macos unit # run the unit test suite
```

You can also open `LiteRTLMStudio.xcodeproj` in Xcode and run the `LiteRTLMStudio` scheme (macOS 14.0+, Swift 5).

The server runs at `127.0.0.1:9379` (fixed port).

## Settings

The settings window has five tabs:

- **일반 (General)** — theme, Dock icon, launch at login, daemon shutdown, first-touch prefill, benchmark retention, and app permissions
- **채팅 (Chat)** — table of contents, follow-up suggestions, font size, session sorting, and history sharing
- **도구 (Tools)** — individual tool toggles, web search (Exa API key), and the working folder
- **MCP** — registered MCP servers
- **스킬 (Skills)** — installed skills and their prompt budget

Engine-level options (backend, MTP, and similar) live in the main window's **inspector → 실행 설정 (Run settings)** tab.

## Project Layout

- `LiteRTLMStudio/` — SwiftUI app (`ContentView`, `SidebarView`, `ChatPaneView`, `StatusItemController`, …)
- `LiteRTLMStudio/Core/` — stores, engines, Markdown, and the download center
- `LiteRTLMStudioTests/` — unit tests
- `docs/` — plans, TODO, design notes, changelog, and the user manual (Korean)
- `EngineVendor/`, `Vendor/` — vendored dependencies (engine headers, Highlightr)

## Docs

- [docs/사용설명서.md](docs/사용설명서.md) — full user manual (Korean)
- [docs/DESIGN.md](docs/DESIGN.md) — design notes
- [docs/CHANGELOG.md](docs/CHANGELOG.md) — release notes

## License

Apache-2.0 — see [LICENSE](LICENSE). This project is an independent client and is not affiliated with Google.
