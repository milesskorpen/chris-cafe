import Foundation

/// Rechecks installation without user clicks; a slow probe never overlaps itself.
public final class SetupMonitor {
    public private(set) var ready = false
    public private(set) var checking = false
    public private(set) var hasChecked = false
    public var changed: (() -> Void)?
    public var shouldCheck: () -> Bool = { true }
    private let probe: () -> Bool
    private let interval: TimeInterval
    private let readyInterval: TimeInterval
    private var lastCheck = Date.distantPast
    private var timer: Timer?

    public init(interval: TimeInterval = 5, readyInterval: TimeInterval = 30,
                probe: @escaping () -> Bool) {
        self.interval = interval
        self.readyInterval = readyInterval
        self.probe = probe
    }
    public func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refresh()
    }
    public func stop() { timer?.invalidate(); timer = nil }
    public func refresh() {
        guard !checking, shouldCheck(),
              Date().timeIntervalSince(lastCheck) >= (ready ? readyInterval : interval) else { return }
        checking = true
        if !hasChecked { changed?() }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.probe()
            DispatchQueue.main.async {
                let visibleChange = !self.hasChecked || self.ready != result
                self.ready = result
                self.hasChecked = true
                self.checking = false
                self.lastCheck = Date()
                if visibleChange { self.changed?() }
            }
        }
    }
    deinit { timer?.invalidate() }
}
