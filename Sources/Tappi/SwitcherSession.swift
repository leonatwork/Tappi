/// The session's decisions, independent of event taps, panels and window APIs.
/// Keep only scalars here: the controller already owns the displayed MRU prefix,
/// and cycling must not copy or rebuild it on the hotkey path.
struct SwitcherSession {
    enum State: Equatable { case idle, holding, sticky }

    private(set) var state: State = .idle
    var selection = 0

    @discardableResult
    mutating func begin(count: Int, backwards: Bool, sticky: Bool, capacity: Int? = nil) -> Bool {
        guard count > 1 else { return false }
        let displayedCount = min(count, capacity ?? count)
        guard displayedCount > 0 else { return false }
        selection = backwards ? displayedCount - 1 : min(1, displayedCount - 1)
        state = sticky ? .sticky : .holding
        return true
    }

    mutating func step(_ delta: Int, count: Int) {
        guard state != .idle, count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    /// Sticky sessions deliberately outlive the held modifier.
    mutating func releaseModifier(count: Int) -> Int? {
        guard state == .holding else { return nil }
        return commit(count: count)
    }

    /// Returning the index leaves focus and MRU updates to the controller, after
    /// the session ends. Cycling and cancelling can never promote a window.
    mutating func commit(count: Int) -> Int? {
        guard state != .idle else { return nil }
        let target = (0..<count).contains(selection) ? selection : nil
        cancel()
        return target
    }

    mutating func cancel() {
        state = .idle
        selection = 0
    }
}

enum MRUOrdering {
    static func promote<Entry>(at index: Int, in entries: inout [Entry]) {
        guard entries.indices.contains(index), index != 0 else { return }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
    }
}
