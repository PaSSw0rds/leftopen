import XCTest
@testable import LeftOpenCore

final class ProjectDetectionTests: XCTestCase {
    func testFindsProjectUnderPrivateTmpWithoutRewritingPath() throws {
        let root = "/private/tmp/leftopen-project-\(UUID().uuidString)"
        let nested = root + "/apps/web"
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        try #"{"name":"sample-library"}"#.write(toFile: root + "/package.json", atomically: true, encoding: .utf8)

        for cwd in [root, nested] {
            let project = Scanner.findProject(cwd)
            XCTAssertEqual(project?.name, "sample-library")
            XCTAssertEqual(project?.root, root)
        }
    }
}
