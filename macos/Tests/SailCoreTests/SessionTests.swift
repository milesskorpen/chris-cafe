import XCTest
@testable import SailCore

final class SessionTests: XCTestCase {
    func testOriginalEmojisDescribeActiveGuardAndThermalStop() {
        var session = Session()
        XCTAssertEqual(session.statusEmoji, "🛌")
        session.begin()
        session.receive(.init(kind: "☕", message: "sleep disabled"))
        XCTAssertEqual(session.statusEmoji, "☕")
        session.receive(.init(kind: "🔌", message: "thermal safeguard off, because the machine is on AC power"))
        XCTAssertEqual(session.guardEmoji, "🔌")
        session.receive(.init(kind: "🔥", message: "thermal pressure Critical; going to sleep"))
        session.receive(.init(kind: "🛌", message: "sleep enabled"))
        session.ended(status: 125, requested: false)
        XCTAssertEqual(session.statusEmoji, "🔥")
        session.begin()
        XCTAssertEqual(session.statusEmoji, "☕")
    }
    func testOnlyConfirmedHoldRaisesSails() {
        var session = Session()
        session.begin()
        XCTAssertEqual(session.state, .starting)
        session.receive(.init(kind: "starting", message: "taking the sleep override"))
        XCTAssertTrue(session.mayHoldOverride)
        XCTAssertEqual(session.state, .starting)
        session.receive(.init(kind: "☕", message: "sleep disabled"))
        XCTAssertEqual(session.state, .on)
    }
    func testQuitDuringStartupDoesNotRaiseIconAgain() {
        var session = Session()
        session.begin(); session.stopping()
        session.receive(.init(kind: "☕", message: "sleep disabled"))
        XCTAssertEqual(session.state, .stopping)
        session.receive(.init(kind: "🛌", message: "sleep enabled"))
        session.ended(status: 143, requested: true)
        XCTAssertEqual(session.state, .off)
    }
    func testCrashAfterHoldRequiresRecovery() {
        var session = Session()
        session.begin()
        session.receive(.init(kind: "starting", message: "taking the sleep override"))
        session.ended(status: 9, requested: false)
        XCTAssertEqual(session.state, .uncertain)
        session.restored()
        XCTAssertEqual(session.state, .off)
        XCTAssertFalse(session.mayHoldOverride)
    }
    func testFailedReleaseCannotShowOff() {
        var session = Session()
        session.begin()
        session.receive(.init(kind: "☕", message: "sleep disabled"))
        session.receive(.init(kind: "❗", message: "sleep is still disabled"))
        session.ended(status: 1, requested: true)
        XCTAssertEqual(session.state, .uncertain)
        XCTAssertTrue(session.releaseFailed)
    }
    func testFailedReassertionShowsWarningUntilConfirmedAgain() {
        var session = Session()
        session.begin()
        session.receive(.init(kind: "☕", message: "sleep disabled"))
        session.receive(.init(kind: "❗", message: "could not set the override again"))
        XCTAssertEqual(session.state, .uncertain)
        session.receive(.init(kind: "☕", message: "sleep disabled again"))
        XCTAssertEqual(session.state, .on)
    }
    func testDenialBeforeHoldIsSafe() {
        var session = Session()
        session.begin()
        session.receive(.init(kind: "⛔", message: "another instance holds the override"))
        session.ended(status: 1, requested: false)
        XCTAssertEqual(session.state, .off)
        XCTAssertTrue(session.detail.contains("another instance"))
    }
    func testHotShutdownPreservesReasonAfterCleanup() {
        var session = Session()
        session.begin()
        session.receive(.init(kind: "☕", message: "sleep disabled"))
        session.receive(.init(kind: "🔥", message: "thermal pressure Critical; going to sleep"))
        session.receive(.init(kind: "🛌", message: "sleep enabled"))
        session.ended(status: 125, requested: false)
        XCTAssertEqual(session.state, .off)
        XCTAssertTrue(session.detail.contains("Critical"))
    }
    func testJSONSplitAtEveryByteIncludesMultibyteEmoji() throws {
        let event = EngineEvent(kind: "☕", message: "sleep disabled")
        let data = try JSONEncoder().encode(event) + Data([10])
        var buffer = EventBuffer()
        var events: [EngineEvent] = []
        for byte in data { events += buffer.append(Data([byte])) }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].kind, "☕")
    }
    func testMultipleLinesAndNonJSONDiagnostics() {
        var buffer = EventBuffer()
        let data = Data("diagnostic\n{\"kind\":\"🛌\",\"message\":\"sleep enabled\"}\n".utf8)
        XCTAssertEqual(buffer.append(data).count, 1)
    }
}
