/// A quit request belongs to a window identity, not its mutable tile index or
/// app PID. There is no clock: only consecutive physical Q presses can confirm.
struct QuitConfirmation<Target: Equatable> {
    enum Event {
        case quit(target: Target?, isRepeat: Bool)
        case otherKey
        case selectionChanged(Target?)
        case sessionEnded
    }
    enum Decision: Equatable { case none, showHint, quit }

    private var pendingTarget: Target?
    var isPending: Bool { pendingTarget != nil }

    init() {}

    @discardableResult
    mutating func handle(_ event: Event) -> Decision {
        switch event {
        case let .quit(target, isRepeat):
            guard let target else { pendingTarget = nil; return .none }
            guard !isRepeat else { return .none }
            if pendingTarget == target {
                pendingTarget = nil
                return .quit
            }
            pendingTarget = target
            return .showHint
        case let .selectionChanged(target):
            if pendingTarget != target { pendingTarget = nil }
        case .otherKey, .sessionEnded:
            pendingTarget = nil
        }
        return .none
    }
}
