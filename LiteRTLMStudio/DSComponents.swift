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
