import XCTest
@testable import ClaudeShell

final class ShellEngineTests: XCTestCase {

    var bridge: ShellBridge!
    var output: [String]!

    override func setUp() {
        super.setUp()
        output = []
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudeshell-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bridge = ShellBridge(sandboxRoot: tempDir.path)
        bridge.onOutput = { [weak self] text in
            self?.output.append(text)
        }
    }

    override func tearDown() {
        bridge = nil
        output = nil
        super.tearDown()
    }

    // MARK: - Basic Commands

    func testEcho() {
        bridge.execute("echo hello world")
        XCTAssertEqual(output.joined(), "hello world\n")
    }

    func testPwd() {
        bridge.execute("pwd")
        XCTAssertFalse(output.joined().isEmpty)
    }

    func testCd() {
        bridge.execute("mkdir testdir")
        bridge.execute("cd testdir")
        bridge.execute("pwd")
        XCTAssertTrue(output.joined().contains("testdir"))
    }

    // MARK: - Filesystem

    func testMkdirAndLs() {
        bridge.execute("mkdir mydir")
        output.removeAll()
        bridge.execute("ls")
        XCTAssertTrue(output.joined().contains("mydir"))
    }

    func testTouchAndCat() {
        bridge.execute("echo 'test content' > testfile.txt")
        output.removeAll()
        bridge.execute("cat testfile.txt")
        XCTAssertTrue(output.joined().contains("test content"))
    }

    func testCpAndRm() {
        bridge.execute("touch original.txt")
        bridge.execute("cp original.txt copy.txt")
        output.removeAll()
        bridge.execute("ls")
        let listing = output.joined()
        XCTAssertTrue(listing.contains("original.txt"))
        XCTAssertTrue(listing.contains("copy.txt"))

        bridge.execute("rm copy.txt")
        output.removeAll()
        bridge.execute("ls")
        XCTAssertFalse(output.joined().contains("copy.txt"))
    }

    // MARK: - Environment Variables

    func testSetAndGetEnv() {
        bridge.execute("MY_VAR=hello123")
        bridge.execute("echo $MY_VAR")
        XCTAssertTrue(output.joined().contains("hello123"))
    }

    func testExport() {
        bridge.execute("export FOO=bar")
        output.removeAll()
        bridge.execute("env")
        XCTAssertTrue(output.joined().contains("FOO=bar"))
    }

    // MARK: - Shell Features

    func testAndOperator() {
        bridge.execute("true && echo success")
        XCTAssertTrue(output.joined().contains("success"))
    }

    func testOrOperator() {
        bridge.execute("false || echo fallback")
        XCTAssertTrue(output.joined().contains("fallback"))
    }

    func testQuotedStrings() {
        bridge.execute("echo \"hello world\"")
        XCTAssertEqual(output.joined(), "hello world\n")
    }

    func testSingleQuotesNoExpansion() {
        bridge.execute("MY_VAR=test")
        output.removeAll()
        bridge.execute("echo '$MY_VAR'")
        XCTAssertEqual(output.joined(), "$MY_VAR\n")
    }

    func testExitCode() {
        bridge.execute("false")
        bridge.execute("echo $?")
        XCTAssertTrue(output.joined().contains("1"))
    }

    // MARK: - Text Processing

    func testGrep() {
        bridge.execute("echo 'apple\nbanana\napricot' > fruits.txt")
        output.removeAll()
        bridge.execute("grep ap fruits.txt")
        let result = output.joined()
        XCTAssertTrue(result.contains("apple"))
        XCTAssertTrue(result.contains("apricot"))
        XCTAssertFalse(result.contains("banana"))
    }

    func testWc() {
        bridge.execute("echo 'one two three' > count.txt")
        output.removeAll()
        bridge.execute("wc -w count.txt")
        XCTAssertTrue(output.joined().contains("3"))
    }

    func testHead() {
        bridge.execute("echo 'line1\nline2\nline3\nline4\nline5' > lines.txt")
        output.removeAll()
        bridge.execute("head -n 2 lines.txt")
        let result = output.joined()
        XCTAssertTrue(result.contains("line1"))
        XCTAssertTrue(result.contains("line2"))
        XCTAssertFalse(result.contains("line3"))
    }

    // MARK: - Help & System

    func testHelp() {
        bridge.execute("help")
        let result = output.joined()
        XCTAssertTrue(result.contains("ClaudeShell"))
    }

    func testWhich() {
        bridge.execute("which echo")
        XCTAssertTrue(output.joined().contains("builtin"))
    }

    func testDate() {
        bridge.execute("date")
        XCTAssertFalse(output.joined().isEmpty)
    }
}

final class ClaudeEngineTests: XCTestCase {

    func testAPIClientCreation() {
        let client = APIClient(apiKey: "test-key")
        XCTAssertNotNil(client)
    }

    func testTaskRunnerParsesCommand() {
        let runner = TaskRunner()
        let parsed = runner.parseClaudeCommand("claude ask 'what is 2+2'")
        XCTAssertEqual(parsed.subcommand, "ask")
        XCTAssertEqual(parsed.argument, "what is 2+2")
    }
}

final class TerminalEmulatorTests: XCTestCase {

    func testANSIColorParsing() {
        let parser = ANSIParser()
        let segments = parser.parse("\u{1b}[32mgreen text\u{1b}[0m normal")
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "green text")
        XCTAssertEqual(segments[1].text, " normal")
    }

    func testInputHandlerHistory() {
        let handler = InputHandler()
        handler.addToHistory("ls")
        handler.addToHistory("pwd")
        XCTAssertEqual(handler.previousCommand(), "pwd")
        XCTAssertEqual(handler.previousCommand(), "ls")
        XCTAssertEqual(handler.nextCommand(), "pwd")
    }
}
