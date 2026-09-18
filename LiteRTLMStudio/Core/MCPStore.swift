import Foundation

/// MCP 서버 설정 저장소 (T-285): JSON 영속+공유 싱글톤.
/// 설정 UI가 관찰, 게이트웨이 도구가 조회.
@MainActor
final class MCPStore: ObservableObject {
    static let shared = MCPStore()

    struct Payload: Codable {
        var servers: [MCPServerConfig] = []
    }

    @Published var servers: [MCPServerConfig] = []
    @Published var lastError: String?
    let storageURL: URL
    private let logger = DebugLogger.shared

    init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            self.storageURL = Self.resolvedURL()
        }
        load()
    }

    nonisolated static func resolvedURL() -> URL {
        StudioPaths.mcpServersURL
    }

    /// 켜진 서버 목록 (게이트웨이 조회용).
    var enabledServers: [MCPServerConfig] {
        servers.filter { $0.enabled && $0.isRunnable }
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        servers = payload.servers
    }

    func save() {
        guard let data = try? JSONEncoder().encode(Payload(servers: servers)) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    /// 추가·수정·삭제·토글 (저장 포함).
    func upsert(_ server: MCPServerConfig) {
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
        } else {
            servers.append(server)
        }
        save()
        logger.info(feature: "MCP", "서버 저장: \(server.name)")
    }

    func remove(id: UUID) {
        servers.removeAll { $0.id == id }
        save()
        logger.info(feature: "MCP", "서버 삭제")
    }

    func setEnabled(id: UUID, _ on: Bool) {
        guard let idx = servers.firstIndex(where: { $0.id == id }) else { return }
        servers[idx].enabled = on
        save()
        logger.info(feature: "MCP", "\(servers[idx].name) \(on ? "켜짐" : "꺼짐")")
    }

    /// 연결 테스트: 도구 0건이어도 성공 (list 호출 자체가 성공이면 통과).
    func testConnection(_ server: MCPServerConfig) async -> String {
        do {
            let tools = try await MCPClient.listTools(server: server)
            logger.info(feature: "MCP", "\(server.name) 연결 성공 (도구 \(tools.count)건)")
            return "연결 성공 (도구 \(tools.count)건)"
        } catch {
            lastError = "E-MAC-NET-0016"
            logger.error(code: "E-MAC-NET-0016", feature: "MCP", "\(server.name) 연결 실패: \(error)")
            return "연결 실패: \(error)"
        }
    }
}
