import XCTest
@testable import TerminautApp

final class TerminautAppTests: XCTestCase {
    func testDefaultStateHasHomePath() {
        let client = MockCoreClient()
        let state = AppState(coreClient: client)
        XCTAssertTrue(state.currentPath.contains("~"), "defaults to home path placeholder")
    }
}

private final class MockCoreClient: CoreClientProtocol {
    func normalize(path: String) throws -> String { path }
    func listDirectory(path: String) throws -> [DirectoryEntry] { [] }
    func listFavorites() throws -> [String] { [] }
    func addFavorite(path: String) throws {}
    func removeFavorite(path: String) throws {}
    func listRecents() throws -> [RecentEntry] { [] }
    func touchRecent(path: String) throws {}
    func detectProjects(path: String) throws -> [ProjectRoot] { [] }
}
