import Foundation

extension Notification.Name {
    static let newChat = Notification.Name("newChat")
    static let openAbout = Notification.Name("openAbout")
    static let chatZoomIn = Notification.Name("chatZoomIn")
    static let chatZoomOut = Notification.Name("chatZoomOut")
    static let chatZoomReset = Notification.Name("chatZoomReset")
    static let serverStart = Notification.Name("serverStart")
    static let serverStop = Notification.Name("serverStop")
    static let toggleDebug = Notification.Name("toggleDebug")
    static let toggleInspector = Notification.Name("toggleInspector")
    static let toggleLogPanel = Notification.Name("toggleLogPanel")
    static let focusChatInput = Notification.Name("focusChatInput") // T-137 드래프트 시작 시 입력 포커스
    static let openBenchmark = Notification.Name("openBenchmark") // T-216 벤치마크 별도창 열기
}
