import AppKit
import SwiftUI

/// 상대 시간 (순수, 테스트 가능, T-077): 방금 전·N초/분/시간 전·어제·N일 전·M월 d일.
nonisolated func chatRelativeTime(from date: Date, now: Date = Date()) -> String {
    let s = max(0, Int(now.timeIntervalSince(date)))
    switch s {
    case 0 ..< 10: return "방금 전"
    case 0 ..< 60: return "\(s)초 전"
    case 0 ..< 3600: return "\(s / 60)분 전"
    case 0 ..< 86400: return "\(s / 3600)시간 전"
    default: break
    }
    let cal = Calendar.current
    if cal.isDateInYesterday(date) { return "어제" }
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                  to: cal.startOfDay(for: now)).day ?? 0
    if days < 7 { return "\(days)일 전" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.dateFormat = "M월 d일"
    return f.string(from: date)
}

/// 완료 상대 시간 라벨 (T-077): 10초 주기 갱신, 라벨만 다시 그림.
struct RelativeTimeText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 10)) { ctx in
            Text(chatRelativeTime(from: date, now: ctx.date))
        }
    }
}

/// 말풍선 디스패처: 역할별 좌우 분리 (PLAN_v3 T-028).
struct MessageBubbleView: View {
    let message: ChatStore.Message
    let showCursor: Bool
    let preparing: Bool
    var scheme: MarkdownScheme = .auto
    var isStreaming: Bool = false
    var fontScale: CGFloat = 1.0 // T-070 채팅 폰트 줌
    let onRetry: () -> Void
    /// 전역 전송 중 여부 (T-165): 스트리밍 중 자르기는 인덱스 붕괴라 입력 푸터 숨김.
    var controlsDisabled = false
    var onEdit: (ChatStore.Message) -> Void = { _ in }

    var body: some View {
        if message.role == "user" {
            UserBubbleView(message: message, fontScale: fontScale,
                           disabled: controlsDisabled, onEdit: onEdit)
        } else {
            AssistantBubbleView(message: message, showCursor: showCursor,
                                preparing: preparing, scheme: scheme,
                                isStreaming: isStreaming, fontScale: fontScale, onRetry: onRetry)
        }
    }
}

/// 유저 버블: 우측 정렬 + 엑센트 틴트 + 복사·다시 요청 (T-165, 응답 푸터와 동일 패턴).
struct UserBubbleView: View {
    let message: ChatStore.Message
    var fontScale: CGFloat = 1.0 // T-070 채팅 폰트 줌
    var disabled = false // T-165 전역 스트리밍 중 숨김
    var onEdit: (ChatStore.Message) -> Void = { _ in }
    @StateObject private var copyFlag = CopyFlag()
    @State private var hovering = false // T-165 완료 푸터 호버 공개
    @State private var hoverHideWork: DispatchWorkItem? // T-105 해제 지연 (경계 깜빡임 방지)

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 2) {
                Text(message.text)
                    .font(.system(size: 14 * fontScale))
                    .tracking(NativeMarkdown.tracking(for: 14 * fontScale)) // T-174 자간 (질문도 동일)
                    .textSelection(.enabled)
                    .padding(12) // T-099 유저 버블 좌우 숨쉬기 복원 (어시스턴트는 그대로)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 10))
                if !disabled {
                    HStack(spacing: 4) {
                        Button {
                            PasteboardUtil.copy(message.text)
                            copyFlag.mark()
                        } label: {
                            Image(systemName: copyFlag.copied ? "checkmark" : "square.on.square")
                                .frame(minWidth: 20, minHeight: 20) // T-168 응답 푸터와 동일 아이콘
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).help("질문 복사").hoverTip("질문 복사")
                        Button { onEdit(message) } label: {
                            Image(systemName: "pencil")
                                .frame(minWidth: 20, minHeight: 20) // T-168 수정 의미 구분
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).help("수정해서 다시 요청").hoverTip("수정해서 다시 요청")
                    }
                    .font(DS.captionFont).foregroundStyle(.tertiary)
                    .frame(height: 20) // T-165 공간 예약 (숨김 때도 자리 유지)
                    .opacity(hovering ? 1 : 0)
                    .accessibilityHidden(!hovering)
                }
            }
        }
        .onHover { inside in // T-165 해제 지연 (바 경계 깜빡임 방지, 재진입 시 취소)
            if inside {
                hoverHideWork?.cancel()
                hoverHideWork = nil
                hovering = true
            } else {
                let work = DispatchWorkItem { hovering = false }
                hoverHideWork?.cancel()
                hoverHideWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
            }
        }
    }
}

/// 어시스턴트 버블: 좌측 정렬 + 복사·재시도 + PERF 뱃지 + 에러 테두리.
struct AssistantBubbleView: View {    let message: ChatStore.Message
    let showCursor: Bool
    let preparing: Bool
    var scheme: MarkdownScheme = .auto
    var isStreaming: Bool = false
    var fontScale: CGFloat = 1.0 // T-070 채팅 폰트 줌
    let onRetry: () -> Void
    @StateObject private var copyFlag = CopyFlag()
    @State private var hovering = false // T-103 완료 푸터 호버 공개
    @State private var hoverHideWork: DispatchWorkItem? // T-105 해제 지연 (경계 깜빡임 방지)

    /// 도구 호출 횟수 접미 (T-266): `· 🔧2`.
    var toolSuffix: String {
        guard let calls = message.toolCalls, !calls.isEmpty else { return "" }
        return " · 🔧\(calls.count)"
    }

    var body: some View {
        // T-065: 어시스턴트는 기본 좌우 여백 없이 전폭. T-096 좌우 패딩 제거로 푸터와 좌단 일치.
        // T-147: 본문이 왼쪽 끝에 붙는 느낌 → 박스+푸터 함께 2pt (정렬 유지).
        VStack(alignment: .leading, spacing: 2) {
                // T-266: 생각 과정 접기 (완료 후 접힘 기본, 스트리밍 중 펼침).
                if let thinking = message.thinking, !thinking.isEmpty {
                    ThinkingBlockView(thinking: thinking, expanded: isStreaming)
                }
                // T-266: 도구 호출 칩 (이름+인자 요약+상태).
                if let calls = message.toolCalls, !calls.isEmpty {
                    ForEach(calls) { ToolCallChipView(record: $0) }
                }
                if message.text.isEmpty {
                    Text(showCursor && !preparing ? "▍" : "") // T-101 준비 중 커서 숨김 (스피너만)
                        .font(.system(size: 14 * fontScale))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12) // T-096 좌우 여백 제거
                        .background(Color(.textBackgroundColor).opacity(0.5))
                        .clipShape(.rect(cornerRadius: 10))
                } else {
                    MarkdownView(text: message.text, scheme: scheme, isStreaming: isStreaming,
                                   fontScale: fontScale)
                        .equatable() // T-045: 스트리밍 중 구버블 갱신 차단
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true) // T-173 제안 폭에 줄바꿈 (우측 잘림 방지)
                        .padding(.top, 12) // T-096 좌우 여백 제거 (푸터와 좌단 일치)
                        .padding(.bottom, 8) // T-170 푸터 밀착 (입력 측과 동일 조건)
                        .padding(.horizontal, message.isError ? 12 : 0) // T-102 에러만 안쪽 여백 (박스 그대로)
                        .background(Color(.textBackgroundColor).opacity(0.5))
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay {
                            if message.isError {
                                RoundedRectangle(cornerRadius: 10).stroke(.red.opacity(0.6))
                            }
                        }
                }
                if preparing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("첫 토큰 대기 중…")
                            .font(DS.captionFont).foregroundStyle(.secondary)
                    }
                }
                // T-103: 스트리밍 중 하단 진행 표시 (웜업 줄과 겹치지 않게 준비 제외). 완료 시 사라짐.
                if isStreaming && !preparing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("응답 중…")
                            .font(DS.captionFont).foregroundStyle(.secondary)
                    }
                }
                // T-162: 상시 배치+투명도 전환 (공간 예약, 출렁 방지). 응답+푸터 전체가 호버 영역.
                if !isStreaming {
                    HStack(spacing: 4) {
                        if let perf = message.perf {
                            Text(perf + toolSuffix).font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
                        }
                        if let finished = message.finishedAt {
                            RelativeTimeText(date: finished)
                                .font(DS.captionFont).foregroundStyle(.tertiary)
                        }
                        Button {
                            PasteboardUtil.copy(message.text)
                            copyFlag.mark()
                        } label: {
                            Image(systemName: copyFlag.copied ? "checkmark" : "square.on.square")
                                .frame(minWidth: 20, minHeight: 20) // T-162 본문 직하 단일행
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).help("응답 복사").hoverTip("응답 복사")
                        Button { onRetry() } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .frame(minWidth: 20, minHeight: 20) // T-162 본문 직하 단일행
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).help("응답 재시도").hoverTip("응답 재시도")
                    }
                    .font(DS.captionFont).foregroundStyle(.tertiary)
                    .frame(height: 20) // T-162 공간 예약 (숨김 때도 자리 유지)
                    .opacity(hovering ? 1 : 0)
                    .accessibilityHidden(!hovering)
                }
        }
        .onHover { inside in // T-105 해제 지연 (바 경계 깜빡임 방지, 재진입 시 취소)
            if inside {
                hoverHideWork?.cancel()
                hoverHideWork = nil
                hovering = true
            } else {
                let work = DispatchWorkItem { hovering = false }
                hoverHideWork?.cancel()
                hoverHideWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
            }
        } // T-103 완료 푸터 호버 공개
        .padding(.leading, 2) // T-147 응답 박스+푸터 좌측 숨쉬기
    }
}

/// 추론 과정 블록 (T-266/T-276): 타이틀은 박스 밖 대화 시작점 정렬, 내용은 기존 박스 유지.
/// 스트리밍 중 펼침·완료 후 접힘 기본.
struct ThinkingBlockView: View {
    let thinking: String
    var expanded: Bool = false
    @State private var open: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                open = !(open ?? expanded)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(expanded ? "추론 중…" : "추론 과정")
                        .font(DS.captionFont).foregroundStyle(.secondary)
                    Image(systemName: (open ?? expanded) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "추론 과정 (생성 중)" : "추론 과정 펼치기")
            if open ?? expanded {
                Text(thinking)
                    .font(DS.captionFont).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(.rect(cornerRadius: 10))
            }
        }
        .onChange(of: expanded) { _, streaming in
            // T-289: 시작 시 펼침, 완료 시 리셋 (수동 토글은 다음 스트림까지 유지).
            open = streaming ? true : nil
        }
    }
}

/// 도구 호출 칩 (T-266 S-1): 이름+인자 요약+상태점. 실행 결과는 S-2.
struct ToolCallChipView: View {
    let record: ToolCallRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if record.status == .streaming {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                } else {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .frame(width: 12, height: 12)
                }
                Text(record.name)
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(record.summary)
                    .font(DS.captionFont).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(statusText).font(DS.captionFont).foregroundStyle(.tertiary)
            }
            if let result = record.result {
                Text(result)
                    .font(DS.captionFont).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(.rect(cornerRadius: 8))
        .help("도구 호출: \(record.name)")
    }

    var statusIcon: String {
        switch record.status {
        case .streaming: return "ellipsis"
        case .received: return "wrench"
        case .done: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .denied: return "nosign"
        }
    }

    var statusColor: Color {
        switch record.status {
        case .failed, .denied: return .red
        case .done: return .green
        default: return .secondary
        }
    }

    var statusText: String {
        switch record.status {
        case .streaming: return "호출 중…"
        case .received: return "수신됨"
        case .done: return "완료"
        case .failed: return "실패"
        case .denied: return "거부됨"
        }
    }
}
