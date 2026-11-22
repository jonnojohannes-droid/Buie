import XCTest
@testable import BuieCore

final class BuieCoreTests: XCTestCase {
    func testProjectAndZip() throws {
        let project = try GeneratedProject.parse(#"{"files":[{"path":"src/main.swift","content":"print(1)\n"},{"path":"README.md","content":"Hallo"}]}"#)
        XCTAssertEqual(project.files.count, 2)
        let zip = try project.zipData()
        XCTAssertEqual(Array(zip.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
        XCTAssertEqual(Array(zip.suffix(22).prefix(4)), [0x50, 0x4b, 0x05, 0x06])
    }

    func testRejectsUnsafeAndConflictingPaths() throws {
        for path in ["../secret", "/absolute", "a//b", "a/./b", "a\\b", "C:/file"] {
            let data = try JSONSerialization.data(withJSONObject: ["files": [["path": path, "content": "x"]]])
            XCTAssertThrowsError(try GeneratedProject.parse(String(decoding: data, as: UTF8.self)))
        }
        XCTAssertThrowsError(try GeneratedProject.parse(#"{"files":[{"path":"a","content":""},{"path":"a/b","content":""}]}"#))
        XCTAssertThrowsError(try GeneratedProject.parse(#"{"files":[{"path":"A","content":""},{"path":"a","content":""}]}"#))
    }

    func testRejectsIncompleteOutputAndAcceptsFence() throws {
        XCTAssertThrowsError(try GeneratedProject.parse(#"{"files":["#))
        XCTAssertThrowsError(try GeneratedProject.parse(#"{"files":[]}"#))
        XCTAssertEqual(try GeneratedProject.parse("```json\n{\"files\":[{\"path\":\"x\",\"content\":\"y\"}]}\n```").files.first?.path, "x")
    }
}
