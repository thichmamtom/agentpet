import XCTest
@testable import AgentPetCore

final class TranscriptUsageTests: XCTestCase {

    private var path: String!

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "agentpet-usage-\(UUID().uuidString).jsonl"
        TranscriptReader.clearCache()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: path)
        super.tearDown()
    }

    private func append(_ lines: [String]) {
        let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(data)
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private func assistantLine(input: Int, output: Int) -> String {
        #"{"type":"assistant","message":{"usage":{"input_tokens":\#(input),"output_tokens":\#(output)},"content":[{"type":"text","text":"hi"}]}}"#
    }

    private func codexTokenCountLine(total: Int, input: Int = 0, output: Int = 0) -> String {
        #"{"timestamp":"2026-06-24T08:43:29.999Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":999,"output_tokens":111,"total_tokens":1110},"last_token_usage":{"input_tokens":\#(input),"cached_input_tokens":0,"output_tokens":\#(output),"reasoning_output_tokens":0,"total_tokens":\#(total)},"model_context_window":258400},"rate_limits":{"limit_id":"codex"}}}"#
    }

    func testSumsUsageAcrossLines() {
        append([
            #"{"type":"user","message":{"content":"do the thing"}}"#,
            assistantLine(input: 1_000, output: 250),
            assistantLine(input: 2_000, output: 750),
        ])
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 4_000)
    }

    func testSecondCallReturnsOnlyTheDelta() {
        append([assistantLine(input: 500, output: 100)])
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 600)
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 0, "nothing new yet")
        append([assistantLine(input: 300, output: 50)])
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 350)
    }

    func testIgnoresLinesWithoutUsage() {
        append([
            #"{"type":"user","message":{"content":"hello"}}"#,
            #"{"type":"summary","summary":"A chat"}"#,
        ])
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 0)
    }

    func testSumsCodexTokenCountEvents() {
        append([
            #"{"timestamp":"2026-06-24T08:43:20.000Z","type":"response_item","payload":{"type":"message"}}"#,
            codexTokenCountLine(total: 20_565, input: 19_901, output: 664),
            codexTokenCountLine(total: 5_100, input: 5_000, output: 100),
        ])
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 25_665)
    }

    func testCodexTokenCountFallsBackToInputPlusOutput() {
        append([
            #"{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":3000,"output_tokens":250}}}}"#,
        ])
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 3_250)
    }

    func testPartialTrailingLineIsLeftForNextCall() {
        append([assistantLine(input: 100, output: 100)])
        // A torn line with no trailing newline must not be consumed.
        let torn = #"{"type":"assistant","message":{"usage":{"input_tokens":9999"#
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(torn.data(using: .utf8)!)
        }
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 200)
        // Complete the torn line: now it should be picked up.
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(#","output_tokens":1}}}"#.data(using: .utf8)!)
            handle.write("\n".data(using: .utf8)!)
        }
        XCTAssertEqual(TranscriptReader.newUsageTokens(at: path), 10_000)
    }

    func testUnreadableFileReturnsNil() {
        XCTAssertNil(TranscriptReader.newUsageTokens(at: "/nonexistent/nope.jsonl"))
    }
}
