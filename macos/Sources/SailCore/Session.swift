import Foundation

public struct EngineEvent: Codable {
    public let kind: String
    public let message: String
    public init(kind: String, message: String) { self.kind = kind; self.message = message }
}

public enum SailState: Equatable {
    case off, starting, on, stopping, uncertain
}

/// The icon reflects confirmed backend events, never just a button press.
public struct Session {
    public private(set) var state: SailState = .off
    public private(set) var detail = "Your Mac follows its usual sleep settings."
    public private(set) var guardDetail = "Temperature protection is automatic."
    public private(set) var guardEmoji = "🦺"
    public private(set) var lastProblemEmoji: String?
    public private(set) var mayHoldOverride = false
    public private(set) var releaseFailed = false
    public private(set) var lastProblem: String?
    public init() {}

    public var statusEmoji: String {
        switch state {
        case .on, .starting, .stopping: return "☕"
        case .uncertain: return "❗"
        case .off: return lastProblemEmoji ?? "🛌"
        }
    }

    public mutating func begin() {
        state = .starting
        detail = "Raising sails (turning on)…"
        releaseFailed = false
        lastProblem = nil
        lastProblemEmoji = nil
    }
    public mutating func stopping() { state = .stopping; detail = "Lowering sails (turning off)…" }
    public mutating func receive(_ event: EngineEvent) {
        switch event.kind {
        case "starting": mayHoldOverride = true
        case "☕":
            mayHoldOverride = true
            if event.message == "sleep disabled again" { lastProblem = nil; lastProblemEmoji = nil }
            if state != .stopping { state = .on; detail = "Your Mac stays awake, even with the lid closed." }
        case "🛌":
            mayHoldOverride = false
            releaseFailed = false
            state = .off
            detail = "Your Mac follows its usual sleep settings."
        case "🦺", "💻", "🔌", "📺", "🤷":
            guardDetail = event.message
            guardEmoji = event.kind
        case "❗":
            lastProblem = event.message
            if event.message == "could not set the override again" {
                state = .uncertain
                detail = "Keep-awake could not be restored. Lower Sails (turn off) or wait for a retry."
            }
            if event.message == "sleep is still disabled" {
                releaseFailed = true
                mayHoldOverride = true
                state = .uncertain
                detail = "Normal sleep could not be restored."
            }
        case "⛔", "🙈", "🔥", "🌙", "❌":
            lastProblem = event.message
            lastProblemEmoji = event.kind
        default: break
        }
    }
    public mutating func ended(status: Int32, requested: Bool) {
        if mayHoldOverride {
            state = .uncertain
            detail = "Check sleep settings — the session ended without confirming cleanup."
        } else {
            state = .off
            detail = lastProblem ?? (requested ? "Your Mac follows its usual sleep settings." :
                (status == 0 ? "Session complete." : "Session stopped (\(status))."))
        }
    }
    public mutating func restored() {
        mayHoldOverride = false
        releaseFailed = false
        lastProblem = nil
        lastProblemEmoji = nil
        state = .off
        detail = "Normal sleep restored."
    }
    public mutating func failed(_ message: String) { state = .off; detail = message }
}

/// Pipe reads may split JSON anywhere, including inside a multibyte emoji.
public struct EventBuffer {
    private var pending = Data()
    public init() {}
    public mutating func append(_ data: Data) -> [EngineEvent] {
        pending.append(data)
        var result: [EngineEvent] = []
        while let end = pending.firstIndex(of: 10) {
            let line = pending[..<end]
            if let event = try? JSONDecoder().decode(EngineEvent.self, from: line) { result.append(event) }
            pending.removeSubrange(...end)
        }
        if pending.count > 65_536 { pending.removeAll() }
        return result
    }
}
