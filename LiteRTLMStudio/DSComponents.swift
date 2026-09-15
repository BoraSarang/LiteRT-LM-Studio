import AppKit
import Charts
import SwiftUI

/// 카드 박스 (T-125): 입력창·터미널·결과카드 공용 뼈대 (바깥 패딩+배경+radius 8+구분선).
extension View {
    /// 카드 박스 적용 (T-097 터미널·입력창 동일 뼈대).
    func cardBox(
        padding: CGFloat = 12,
        background: Color = Color(nsColor: .textBackgroundColor),
        stroked: Bool = true
    ) -> some View {
        self
            .padding(padding)
            .background(background)
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                if stroked { RoundedRectangle(cornerRadius: 8).stroke(.separator) }
            }
    }
}

/// 복사 완료 플래그 (T-125): 1.5초 "복사됨" 상태 공유. 표시는 호출 측이 담당.
@MainActor
final class CopyFlag: ObservableObject {
    @Published private(set) var copied = false
    private var work: DispatchWorkItem?

    func mark() {
        copied = true
        work?.cancel()
        let done = DispatchWorkItem { [weak self] in self?.copied = false }
        work = done
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: done)
    }
}

/// 호버 팁 표시 판정 (순수, 테스트 가능, T-171): 정지 유지 시간이 임계 이상이면 표시.
nonisolated func hoverTipVisible(hovering: Bool, elapsed: TimeInterval,
                                 delay: TimeInterval = 0.6) -> Bool {
    hovering && elapsed >= delay
}

/// 호버 팁 (T-171): `.help` 무관 자체 말풍선 (활성화 정책·OS 무관 노출).
/// 아이콘 버튼에 부착, 0.6초 정지 후 상단에 표시.
struct HoverTipBox<Inner: View>: View {
    let text: String
    let content: Inner
    @State private var show = false
    @State private var work: DispatchWorkItem?

    var body: some View {
        content
            .onHover { inside in
                work?.cancel()
                if inside {
                    let since = Date()
                    let pending = DispatchWorkItem {
                        show = hoverTipVisible(hovering: true,
                                               elapsed: Date().timeIntervalSince(since))
                    }
                    work = pending
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: pending)
                } else {
                    work = nil
                    show = false
                }
            }
            .overlay(alignment: .top) {
                if show {
                    Text(text)
                        .font(DS.captionFont)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(.rect(cornerRadius: 6))
                        .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
                        .shadow(radius: 3)
                        .offset(y: -30)
                }
            }
    }
}

extension View {
    /// 호버 팁 부착 (T-171).
    func hoverTip(_ text: String) -> some View {
        HoverTipBox(text: text, content: self)
    }
}

/// 단일 시계열 미니 차트 (T-125): SystemCell·GPU 공용. X는 인덱스, Y 0~yMax.
struct HistoryLineChart: View {
    let history: [Double]
    let color: Color
    var height: CGFloat = 44
    var yMax: Double = 100

    var body: some View {
        Chart {
            ForEach(Array(history.enumerated()), id: \.offset) { idx, val in
                LineMark(x: .value("t", idx), y: .value("v", val))
                    .foregroundStyle(color.opacity(0.9))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0 ... yMax)
        .frame(height: height)
    }
}
