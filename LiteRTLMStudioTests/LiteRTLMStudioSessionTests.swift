import AppKit
import XCTest
@testable import LiteRTLMStudio

/// 세션 회귀군 (T-127 파일 분리): ChatStore 세션 생명주기.
final class LiteRTLMStudioSessionTests: XCTestCase {
    /// 채팅 재시도 조회: 마지막 user 프롬프트 반환, 없으면 nil (T-028).
    @MainActor
    func testLastUserPrompt() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-prompt-\(UUID().uuidString).json")
        let store = ChatStore(storageURL: url)
        XCTAssertNil(store.lastUserPrompt())
        store.messages.append(ChatStore.Message(role: "user", text: "안녕"))
        store.messages.append(ChatStore.Message(role: "assistant", text: "반가워"))
        XCTAssertEqual(store.lastUserPrompt(), "안녕")
        try? FileManager.default.removeItem(at: url)
    }

    /// 세션 생명주기: 드래프트·생성·전환·삭제 + 영속 왕복 (T-032/T-137).
    @MainActor
    func testChatSessions() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-test-\(UUID().uuidString).json")
        let store = ChatStore(storageURL: url)
        // 빈 저장소 init → 방 없이 드래프트.
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNil(store.currentSessionID)
        let id = store.ensureSessionForSend()
        XCTAssertNotNil(id)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.currentSessionID, id)
        store.messages.append(ChatStore.Message(role: "user", text: "첫 질문입니다"))
        store.refreshTitle()
        XCTAssertEqual(store.sessions.first?.title, "첫 질문입니다")
        // 드래프트 시작: 행 추가 없이 현재만 해제.
        store.startDraft()
        XCTAssertNil(store.currentSessionID)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.sessions.count, 1)
        store.selectSession(id!)
        XCTAssertEqual(store.messages.count, 1)
        let reloaded = ChatStore(storageURL: url)
        XCTAssertEqual(reloaded.sessions.count, 1)
        reloaded.selectSession(id!)
        XCTAssertEqual(reloaded.messages.first?.text, "첫 질문입니다")
        reloaded.deleteSession(id!)
        XCTAssertEqual(reloaded.sessions.count, 0)
        XCTAssertNil(reloaded.currentSessionID)
        try? FileManager.default.removeItem(at: url)
    }

    /// 채팅 정렬: 핀 우선 + 최근/이름/생성 (T-058).
    func testSortedSessions() {
        typealias S = ChatStore.Session
        let old = S(title: "b", updatedAt: Date(timeIntervalSince1970: 100),
                    createdAt: Date(timeIntervalSince1970: 100))
        let new = S(title: "a", updatedAt: Date(timeIntervalSince1970: 200),
                    createdAt: Date(timeIntervalSince1970: 200))
        var pinned = S(title: "z", updatedAt: Date(timeIntervalSince1970: 50),
                       createdAt: Date(timeIntervalSince1970: 50), pinned: true)
        XCTAssertEqual(ChatStore.sortedSessions([old, new], by: .recent).first?.title, "a")
        XCTAssertEqual(ChatStore.sortedSessions([old, new], by: .name).first?.title, "a")
        XCTAssertEqual(ChatStore.sortedSessions([old, new], by: .created).first?.title, "a")
        XCTAssertEqual(ChatStore.sortedSessions([new, pinned], by: .recent).first?.title, "z")
        pinned.pinned = false
        XCTAssertEqual(ChatStore.sortedSessions([old, pinned], by: .recent).first?.title, "b")
    }

    /// 구 JSON 호환: 신필드 없으면 기본값 (T-058).
    func testSessionMigration() throws {
        let id = UUID()
        let json = "{\"id\":\"\(id.uuidString)\",\"title\":\"구대화\",\"updatedAt\":1789000000.0}"
        let s = try JSONDecoder().decode(ChatStore.Session.self, from: Data(json.utf8))
        XCTAssertEqual(s.id, id)
        XCTAssertEqual(s.title, "구대화")
        XCTAssertFalse(s.pinned)
        XCTAssertNil(s.customTitle)
        XCTAssertEqual(s.displayTitle, "구대화")
    }

    /// 이름 변경·고정·자동제목 보호 (T-058).
    @MainActor
    func testRenamePin() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-rename-\(UUID().uuidString).json")
        let store = ChatStore(storageURL: url)
        let id = store.ensureSessionForSend()!
        store.renameSession(id, title: "   ")
        XCTAssertNil(store.sessions.first!.customTitle)
        store.renameSession(id, title: "  회의  ")
        XCTAssertEqual(store.sessions.first!.displayTitle, "회의")
        store.messages.append(ChatStore.Message(role: "user", text: "바뀌면 안됨"))
        store.refreshTitle()
        XCTAssertEqual(store.sessions.first!.displayTitle, "회의")
        store.togglePin(id)
        XCTAssertTrue(store.sessions.first!.pinned)
        store.togglePin(id)
        XCTAssertFalse(store.sessions.first!.pinned)
        try? FileManager.default.removeItem(at: url)
    }

    /// 이름 변경 중복 가드 (T-139): 동일 ID 1초 내 재호출 무시 (allowDelete와 동일 규칙).
    func testAllowRename() {
        let id = UUID()
        XCTAssertTrue(SessionListView.allowRename(id: id, lastID: nil,
                                                  lastAt: .distantPast, now: Date()))
        let now = Date()
        XCTAssertFalse(SessionListView.allowRename(id: id, lastID: id,
                                                   lastAt: now, now: now))
        XCTAssertTrue(SessionListView.allowRename(id: id, lastID: id,
                                                  lastAt: now, now: now.addingTimeInterval(1.1)))
    }

    /// 복원 대상 (T-134): 생성순 선두가 아닌 최근 사용 세션.
    func testMostRecentSessionID() {
        typealias S = ChatStore.Session
        let old = S(title: "old", updatedAt: Date(timeIntervalSince1970: 100))
        let new = S(title: "new", updatedAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(ChatStore.mostRecentSessionID([old, new]), new.id)
        XCTAssertEqual(ChatStore.mostRecentSessionID([new, old]), new.id)
        XCTAssertNil(ChatStore.mostRecentSessionID([]))
    }

    /// 드래프트 반복 시작은 무시 (T-137): 행 추가·상태 변경 없음.
    @MainActor
    func testStartDraftIdempotent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-draft-\(UUID().uuidString).json")
        let store = ChatStore(storageURL: url)
        store.startDraft()
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNil(store.currentSessionID)
        let id = store.ensureSessionForSend()!
        store.startDraft()
        store.startDraft()
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertNil(store.currentSessionID)
        // 드래프트에서는 새로 만들고, 방이 있으면 재사용 (새 행 없음).
        let id2 = store.ensureSessionForSend()!
        XCTAssertNotEqual(id2, id)
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.ensureSessionForSend(), id2)
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.currentSessionID, id2)
        try? FileManager.default.removeItem(at: url)
    }
}
