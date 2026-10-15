import XCTest
@testable import SailCore

final class SetupMonitorTests: XCTestCase {
    private final class Counter {
        private let lock = NSLock()
        private var count = 0
        func next() -> Int {
            lock.lock(); defer { lock.unlock() }
            count += 1; return count
        }
    }

    func testDetectsInstallationAfterFailedCheckWithoutUserAction() {
        let detected = expectation(description: "Installation detected automatically")
        let counter = Counter()
        let monitor = SetupMonitor(interval: 0.02, probe: { counter.next() >= 2 })
        monitor.changed = {
            XCTAssertTrue(Thread.isMainThread)
            if monitor.ready { detected.fulfill() }
        }
        monitor.start()
        wait(for: [detected], timeout: 2)
        monitor.stop(); monitor.changed = nil
        XCTAssertTrue(monitor.ready)
    }

    func testSlowSetupCheckNeverOverlapsAnotherCheck() {
        let began = expectation(description: "Probe started")
        let completed = expectation(description: "Probe completed")
        let release = DispatchSemaphore(value: 0)
        let counter = Counter()
        let monitor = SetupMonitor(interval: 0.01, probe: {
            XCTAssertEqual(counter.next(), 1)
            began.fulfill()
            _ = release.wait(timeout: .now() + 2)
            return true
        })
        monitor.changed = { if monitor.ready { completed.fulfill() } }
        monitor.start()
        wait(for: [began], timeout: 1)
        for _ in 0..<10 { monitor.refresh() }
        release.signal()
        wait(for: [completed], timeout: 2)
        monitor.stop(); monitor.changed = nil
    }

    func testDetectsRemovedSupportAfterItWasReady() {
        let missing = expectation(description: "Removed support detected")
        let counter = Counter()
        let monitor = SetupMonitor(interval: 0.01, readyInterval: 0.02,
                                   probe: { counter.next() == 1 })
        var wasReady = false
        monitor.changed = {
            if monitor.ready { wasReady = true }
            if wasReady && !monitor.ready { missing.fulfill() }
        }
        monitor.start()
        wait(for: [missing], timeout: 2)
        monitor.stop(); monitor.changed = nil
    }
}
