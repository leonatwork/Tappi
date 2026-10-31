import Foundation

/// Decisions are independent of AppKit, settings and the system-wide hot keys.
enum InstanceLifecycle {
    enum StartupDecision: Equatable { case start, wait, exit }

    static func startup(hasPeer: Bool, restartRemaining: TimeInterval?) -> StartupDecision {
        // Check the peer first: an exit at the deadline must not discard both copies.
        guard hasPeer else { return .start }
        guard let remaining = restartRemaining, remaining > 0 else { return .exit }
        return .wait
    }

    static func shouldTerminateForRestart(launchSucceeded: Bool, replacementReady: Bool,
                                          replacementRunning: Bool, remaining: TimeInterval) -> Bool {
        launchSucceeded && replacementReady && replacementRunning && remaining > 0
    }

    static func shouldRestore(ownsLifecycle: Bool, suppressedByUs: Bool, force: Bool) -> Bool {
        ownsLifecycle && (suppressedByUs || force)
    }
}

/// A per-attempt temporary directory isolates restarts without touching settings.
struct RestartRequest: Equatable {
    static let argument = "--tappi-restart"
    static let timeout: TimeInterval = 5
    static let pollInterval: TimeInterval = 0.05

    enum Decision: String { case accepted, cancelled }

    let token: String
    let parentPID: Int32
    /// Shared monotonic clock, so launch time is included in the bounded wait.
    let deadline: TimeInterval

    private var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Tappi-restart-\(token)", isDirectory: true)
    }
    private var readyURL: URL { directory.appendingPathComponent("ready") }
    private var decisionURL: URL { directory.appendingPathComponent("decision") }

    var isReady: Bool { FileManager.default.fileExists(atPath: readyURL.path) }
    var decision: Decision? {
        guard let value = try? FileManager.default.destinationOfSymbolicLink(atPath: decisionURL.path) else {
            return nil
        }
        return Decision(rawValue: value)
    }
    // Once accepted, allow a separate bounded interval for AppKit's cleanup/exit.
    var waitDeadline: TimeInterval { deadline + (decision == .accepted ? Self.timeout : 0) }

    var arguments: [String] { [Self.argument, token, String(parentPID), String(deadline)] }

    init(token: String, parentPID: Int32, deadline: TimeInterval) {
        self.token = token
        self.parentPID = parentPID
        self.deadline = deadline
    }

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: Self.argument),
              arguments.count > index + 3,
              UUID(uuidString: arguments[index + 1]) != nil,
              let pid = Int32(arguments[index + 2]), pid > 0,
              let deadline = TimeInterval(arguments[index + 3]), deadline.isFinite else { return nil }
        self.init(token: arguments[index + 1], parentPID: pid, deadline: deadline)
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
    }

    func announceReady() -> Bool {
        isReady || FileManager.default.createFile(atPath: readyURL.path, contents: Data())
    }

    /// Symlink creation is exclusive/atomic. Acceptance and timeout compete for
    /// the same name, so neither process can reverse the other's decision.
    @discardableResult
    func decide(_ value: Decision) -> Decision? {
        try? FileManager.default.createSymbolicLink(atPath: decisionURL.path,
                                                   withDestinationPath: value.rawValue)
        return decision
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
