import AppKit
import SailCore

final class EngineController {
    private(set) var session = Session()
    private(set) var process: Process?
    private var stream: Pipe?
    private var buffer = EventBuffer()
    private var requestedStop = false
    private var deadline: Date?
    private var timer: Timer?
    var changed: (() -> Void)?
    var finished: (() -> Void)?
    var isRunning: Bool { process != nil }

    func start(minutes: Int?) {
        guard process == nil, session.state != .uncertain else { return }
        session.begin(); requestedStop = false; buffer = EventBuffer()
        deadline = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        changed?()
        guard let script = Bundle.main.url(forResource: "chris-cafe", withExtension: nil),
              let python = Self.python else {
            session.failed("Python 3 is required. Install Python 3, then reopen Full Sail.")
            changed?(); return
        }
        let child = Process(), pipe = Pipe()
        child.executableURL = python
        child.arguments = ["-u", script.path, "--events-json", "--parent-pid", String(getpid())]
        child.standardError = pipe
        child.standardOutput = FileHandle.nullDevice
        process = child; stream = pipe
        do {
            try child.run()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    DispatchQueue.main.async { self?.consume(data) }
                }
                child.waitUntilExit()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.timer?.invalidate(); self.timer = nil; self.deadline = nil
                    self.session.ended(status: child.terminationStatus, requested: self.requestedStop)
                    self.process = nil; self.stream = nil
                    self.changed?(); self.finished?()
                }
            }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, let deadline = self.deadline, Date() >= deadline else { return }
                self.stop()
            }
        } catch {
            process = nil; stream = nil; deadline = nil
            session.failed(error.localizedDescription); changed?()
        }
    }
    private func consume(_ data: Data) {
        for event in buffer.append(data) { session.receive(event) }
        changed?()
    }
    func stop() {
        guard let process, process.isRunning, !requestedStop else { return }
        requestedStop = true
        timer?.invalidate(); timer = nil
        session.stopping(); changed?()
        process.terminate()
    }
    var remaining: String? {
        guard let deadline else { return nil }
        let minutes = max(1, Int(ceil(deadline.timeIntervalSinceNow / 60)))
        return "\(minutes) min remaining"
    }
    static var python: URL? {
        ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }
    func restore() {
        guard process == nil, session.state == .uncertain else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let success = Self.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"])
            DispatchQueue.main.async {
                if success { self.session.restored() }
                self.changed?()
            }
        }
    }
    // Read-only policy probes also have bounded time; no password prompts.
    static func run(_ path: String, _ arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path); task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        let limit = Date().addingTimeInterval(10)
        while task.isRunning, Date() < limit { Thread.sleep(forTimeInterval: 0.05) }
        if task.isRunning { task.terminate(); return false }
        return task.terminationStatus == 0
    }
    static func supportReady() -> Bool {
        let vectors = [
            ["/usr/bin/pmset", "-a", "disablesleep", "1"],
            ["/usr/bin/pmset", "-a", "disablesleep", "0"],
            ["/usr/bin/pmset", "sleepnow"],
            ["/usr/bin/powermetrics", "-n", "1", "-i", "200", "--samplers", "thermal"]
        ]
        return python != nil && vectors.allSatisfy { run("/usr/bin/sudo", ["-k", "-n", "-l"] + $0) }
            && run("/bin/launchctl", ["print", "system/com.chrispennello.chris-cafe.reset"])
    }
}
