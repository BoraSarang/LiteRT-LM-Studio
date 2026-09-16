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
    static let openModelManager = Notification.Name("openModelManager") // T-232 모델 관리 별도창 열기
    static let openModelManagerMyModels = Notification.Name("openModelManagerMyModels") // T-247 내 모델 탭으로 열기
    static let selectChatModel = Notification.Name("selectChatModel") // T-247 채팅 모델 선택 요청
    static let runBenchmarkModel = Notification.Name("runBenchmarkModel") // T-247 벤치마크 실행 요청
    static let requestAlias = Notification.Name("requestAlias") // T-232 관리 창에서 표시 이름 바꾸기 요청
}
