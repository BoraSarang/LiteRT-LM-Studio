import AppKit
import SwiftUI

/// 추천 링크 1행 (T-262): 제목·설명·URL 고정.
struct WelcomeLink: Hashable {
    let title: String
    let detail: String
    let url: String
    let icon: String

    nonisolated static var all: [WelcomeLink] {
        [
            WelcomeLink(title: "공식 문서", detail: "LiteRT-LM 시작·API 안내",
                        url: "https://ai.google.dev/edge/litert-lm", icon: "book"),
            WelcomeLink(title: "GitHub", detail: "릴리즈·이슈·소스",
                        url: "https://github.com/google-ai-edge/LiteRT-LM",
                        icon: "chevron.left.forwardslash.chevron.right"),
            WelcomeLink(title: "Hugging Face", detail: "커뮤니티 모델 모음",
                        url: "https://huggingface.co/litert-community", icon: "face.smiling"),
            WelcomeLink(title: "AI Edge Gallery", detail: "온디바이스 데모 앱",
                        url: "https://github.com/google-ai-edge/gallery", icon: "square.grid.2x2")
        ]
    }
}

/// 메인 웰컴 (T-262): 빈 채팅 화면 교체. 환영+새소식+업데이트+추천 링크.
struct WelcomeView: View {
    @ObservedObject var notes: ReleaseNotes
    @ObservedObject var uv: UvManager
    var daemonRunning: Bool

    @State private var showUpgradeConfirm = false
    @State private var upgrading = false
    @State private var upgradeNote: String?

    /// 설치된 litert-lm 버전 (`x.y.z` 추출, 없으면 nil).
    var installed: String? { OnboardingGate.parseVersion(uv.litertVersion) }

    /// 설치 버전보다 새 정식 릴리즈 (없으면 nil=최신).
    var update: AppRelease? { ReleaseNotesParser.newerStable(notes.releases, installed: installed) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                envLine
                newsCard
                if update != nil { updateRow }
                linksCard
                serverHint
            }
            .frame(maxWidth: DS.chatMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .task { await notes.refreshIfNeeded() }
        .confirmationDialog("litert-lm 업데이트", isPresented: $showUpgradeConfirm,
                            titleVisibility: .visible) {
            Button("업데이트 실행") { Task { await runUpgrade() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("`uv tool upgrade litert-lm`을 실행합니다. 수 분 걸릴 수 있어요.")
        }
    }

    /// 환영 헤더.
    var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "brain")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("LiteRT-LM Studio")
                .font(.system(size: 22, weight: .bold))
            Text("온디바이스 LLM 채팅 매니저 — 아래에 질문을 입력하세요")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    /// 환경 1줄: 설치 버전+최신 버전+상태 점.
    var envLine: some View {
        HStack(spacing: 6) {
            Circle().fill(daemonRunning ? .green : .gray)
                .frame(width: 8, height: 8)
            Text("litert-lm \(installed ?? "확인 중")")
                .font(DS.captionFont).foregroundStyle(.secondary)
            if let tag = notes.latestStable?.tag {
                Text("· 최신 \(ReleaseNotesParser.displayVersion(tag))")
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            if update != nil {
                Text("업데이트 있음")
                    .font(DS.captionFont.weight(.semibold)).foregroundStyle(.orange)
            }
        }
    }

    /// 새소식 카드 (최대 3건, What's New 요약).
    var newsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("새소식")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if notes.showingCache {
                    Text("오프라인 — 저장된 소식")
                        .font(DS.captionFont).foregroundStyle(.secondary)
                }
                if notes.isLoading {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button { Task { await notes.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("새소식 새로고침")
                }
            }
            if notes.featured.isEmpty, !notes.isLoading {
                Text("소식을 불러오지 못했습니다. 새로고침을 눌러 다시 시도해 주세요.")
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
            ForEach(notes.featured) { rel in
                newsRow(rel)
                if rel.id != notes.featured.last?.id { Divider() }
            }
        }.cardBox()
    }

    /// 새소식 1행: 버전+날짜+요약 3줄+자세히 링크.
    func newsRow(_ rel: AppRelease) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(ReleaseNotesParser.displayVersion(rel.tag))
                    .font(.system(size: 13, weight: .semibold))
                if rel.prerelease {
                    Text("프리릴리즈").font(DS.captionFont).foregroundStyle(.secondary)
                }
                Spacer()
                if let date = rel.publishedAt {
                    RelativeTimeText(date: date)
                        .font(DS.captionFont).foregroundStyle(.tertiary)
                }
            }
            ForEach(ReleaseNotesParser.summaryLines(rel.body), id: \.self) { line in
                Text(line).font(DS.captionFont).foregroundStyle(.secondary).lineLimit(2)
            }
            if let url = URL(string: rel.url), !rel.url.isEmpty {
                Link("자세히 보기", destination: url)
                    .font(DS.captionFont)
            }
        }
    }

    /// 업데이트 행 (신버전 있을 때만).
    var updateRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
                if let tag = update?.tag {
                    Text("v\(ReleaseNotesParser.displayVersion(tag)) 사용 가능")
                        .font(.system(size: 13, weight: .semibold))
                }
                Spacer()
                if upgrading {
                    ProgressView().scaleEffect(0.7)
                    Text("업데이트 중…").font(DS.captionFont).foregroundStyle(.secondary)
                } else {
                    Button("업데이트") { showUpgradeConfirm = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            if let note = upgradeNote {
                Text(note).font(DS.captionFont).foregroundStyle(.secondary)
            }
        }.cardBox()
    }

    /// 추천 링크 카드 4행.
    var linksCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("추천 링크")
                .font(.system(size: 13, weight: .semibold))
                .padding(.bottom, 4)
            ForEach(WelcomeLink.all, id: \.url) { link in
                Button { openLink(link.url) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: link.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(link.title).font(.system(size: 13, weight: .medium))
                            Text(link.detail).font(DS.captionFont).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(link.title) 열기")
            }
            Text("출처: LiteRT-LM 커뮤니티 안내")
                .font(DS.captionFont).foregroundStyle(.tertiary)
                .padding(.top, 4)
        }.cardBox()
    }

    /// 서버 미실행 시 축소 안내.
    var serverHint: some View {
        Group {
            if !daemonRunning {
                Text("사이드바에서 모델을 고르고 ▶ 버튼(⌘R)으로 데몬을 띄우세요")
                    .font(DS.captionFont).foregroundStyle(.secondary)
            }
        }
    }

    /// 외부 링크 열기 (기본 브라우저).
    func openLink(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
        DebugLogger.shared.info(feature: "웰컴", "링크 열기: \(raw)")
    }

    /// litert-lm 업데이트 실행 (확인 팝업 이후 호출).
    func runUpgrade() async {
        upgrading = true
        upgradeNote = nil
        defer { upgrading = false }
        DebugLogger.shared.info(feature: "업데이트", "uv tool upgrade litert-lm 시작")
        let (out, code) = await UvManager.runProcess(
            UvManager.uvPath, args: ["tool", "upgrade", "litert-lm"], timeout: 120)
        if code == 0 {
            await uv.refresh()
            await notes.refresh()
            upgradeNote = "업데이트 완료 (litert-lm \(installed ?? ""))"
            DebugLogger.shared.info(feature: "업데이트", "완료: \(out.prefix(120))")
        } else {
            upgradeNote = "업데이트 실패 (E-MAC-ENG-0003)"
            DebugLogger.shared.error(code: "E-MAC-ENG-0003", feature: "업데이트", out)
        }
    }
}
