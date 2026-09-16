import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 서버 액션 (T-189 분리, 파일 길이 관리)
extension ContentView {
    /// 단일 시작/중지 버튼 상태 (T-189): 입력창 route를 따라감.
    /// 네이티브 선택 시 prepare/release, 데몬 선택 시 start/stop.
    /// 실행 중 아이콘은 기본 도형만 사용
    /// (link.badge.minus는 16pt 툴바에서 링처럼 뭉개져 보임). 외부 구분은 help+사이드바 표기로.
    var serverIcon: String {
        if chat.route == .native {
            return nativeEngine.preparedModelID != nil ? "stop.fill" : "play.fill"
        }
        return daemon.status == .running ? "stop.fill" : "play.fill"
    }

    /// 툴바 버튼 비활성 (T-189): 데몬 시작 중·네이티브 준비 중.
    var serverDisabled: Bool {
        if chat.route == .native { return nativeEngine.state == .preparing }
        return daemon.status == .starting
    }

    var serverHelp: String {
        if chat.route == .native {
            switch nativeEngine.state {
            case .preparing:
                return "앱 내 엔진 준비 중…"
            case .ready:
                return "앱 내 엔진 중지 — 메모리 반납 (다시 실행은 사이드바)"
            case .failed:
                return "앱 내 엔진 다시 실행"
            case .idle:
                return "앱 내 엔진 초기화"
            }
        }
        if daemon.status == .running {
            return daemon.external
                ? "외부 데몬 연결 끊기 (⌘.) — 터미널 데몬은 계속 실행됩니다"
                : "서버 중지 (⌘.)"
        }
        if nativeEngine.preparedModelID != nil {
            return "서버 시작 (⌘R) — 앱 내 엔진으로 대화 가능합니다"
        }
        return "서버 시작 (⌘R)"
    }

     func toggleServer() {
        if chat.route == .native {
            if nativeEngine.preparedModelID != nil {
                nativeEngine.release()
                logger.info(feature: "네이티브엔진", "툴바에서 중지 (메모리 반납)")
            } else if nativeEngine.state != .preparing {
                Task { try? await nativeEngine.restart(modelID: chat.model) }
            }
            return
        }
        if daemon.status == .running {
            daemon.stop()
        } else {
            Task { await daemon.start() }
        }
    }

     func toggleLogPanel() {
        if daemon.status != .running {
            logger.info(feature: "하단패널", "서버 중지 상태 — 패널 열기 불가")
            return
        }
        logPanelVisible.toggle()
    }
}
