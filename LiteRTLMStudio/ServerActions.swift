import AppKit
import Combine
import SwiftUI

// MARK: - 서버 액션 (T-189 분리, 파일 길이 관리)
extension ContentView {
    /// 단일 시작/중지 버튼 상태 (T-189): 입력창 route를 따라감.
    /// 앱 내 엔진 선택 시 prepare/release, 데몬 선택 시 start/stop.
    /// 실행 중 아이콘은 기본 도형만 사용
    /// (link.badge.minus는 16pt 툴바에서 링처럼 뭉개져 보임). 외부 구분은 help+사이드바 표기로.
    var serverIcon: String {
        if chat.route == .native {
            return nativeEngine.preparedModelID != nil ? "stop.fill" : "play.fill"
        }
        return daemon.status == .running ? "stop.fill" : "play.fill"
    }

    /// 툴바 버튼 비활성 (T-189): 데몬 시작 중·앱 내 엔진 준비 중.
    var serverDisabled: Bool {
        if chat.route == .native { return nativeEngine.state == .preparing }
        return daemon.status == .starting
    }

    var serverHelp: String {
        if chat.route == .native {
            switch nativeEngine.state {
            case .preparing:
                return L(L10n.Server.nativePreparing)
            case .ready:
                return L(L10n.Server.nativeStop)
            case .failed:
                return L(L10n.Server.nativeRestart)
            case .idle:
                return L(L10n.Server.nativeInit)
            }
        }
        if daemon.status == .running {
            return daemon.external
                ? L(L10n.Server.externalDisconnect)
                : L(L10n.Server.stop)
        }
        if nativeEngine.preparedModelID != nil {
            return L(L10n.Server.startReadyNative)
        }
        return L(L10n.Server.start)
    }

     func toggleServer() {
        if chat.route == .native {
            if nativeEngine.preparedModelID != nil {
                nativeEngine.release()
                logger.info(feature: "앱내엔진", "툴바에서 중지 (메모리 반납)")
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
