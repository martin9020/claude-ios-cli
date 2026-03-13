import XCTest
@testable import ClaudeShell

final class ShellEngineTests: XCTestCase {

    var bridge: ShellBridge!
    var outputCapture: String!

    override func setUp() {
        super.setUp()
        outputCapture = ""
        bridge = ShellBridge()
        // Capture output via the published outputBuffer
    }

    override func tearDown() {
        bridge = nil
        outputCapture = nil
        super.tearDown()
    }

    private func runAndCapture(_ command: String) -> String {
        bridge.clearOutput()
        // Small delay to let clear propagate
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        bridge.execute(command)
        // Give output time to propagate through DispatchQueue.main
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        return bridge.outputBuffer
    }

    // MARK: - Basic Commands

    func testEcho() {
        let output = runAndCapture("echo hello world")
        XCTAssertTrue(output.contains("hello world"))
    }

    func testPwd() {
        let output = runAndCapture("pwd")
        XCTAssertFalse(output.isEmpty)
    }

    func testHelp() {
        let output = runAndCapture("help")
        XCTAssertTrue(output.contains("ClaudeShell"))
    }

    func testWhich() {
        let output = runAndCapture("which echo")
        XCTAssertTrue(output.contains("builtin"))
    }

    func testDate() {
        let output = runAndCapture("date")
        XCTAssertFalse(output.isEmpty)
    }

    // MARK: - Filesystem

    func testMkdirAndLs() {
        _ = runAndCapture("mkdir test_ls_dir")
        let output = runAndCapture("ls")
        XCTAssertTrue(output.contains("test_ls_dir"))
    }

    // MARK: - Environment Variables

    func testSetAndGetEnv() {
        _ = runAndCapture("MY_VAR=hello123")
        let output = runAndCapture("echo $MY_VAR")
        XCTAssertTrue(output.contains("hello123"))
    }

    // MARK: - Claude Engine

    func testClaudeEngineCreation() {
        let engine = ClaudeEngine.shared
        XCTAssertNotNil(engine)
    }

    // MARK: - ANSI Parser

    func testANSIStripping() {
        let parser = ANSIParser()
        let result = parser.stripANSI("\u{1b}[32mgreen text\u{1b}[0m normal")
        XCTAssertEqual(result, "green text normal")
    }
}
