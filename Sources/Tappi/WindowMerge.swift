/// Value-only input to the MRU merge; identity does not depend on Accessibility.
struct WindowMergeItem<Key: Equatable, PID: Hashable, Value> {
    let key: Key
    let pid: PID
    let zIndex: Int
    let value: Value
}

enum WindowMerge {
    /// Preserve history when an app cannot answer, rather than treating its
    /// missing snapshot as proof that its windows have closed. The caller only
    /// supplies unresponsive pids that are still running.
    static func merge<Key: Equatable, PID: Hashable, Value>(
        old: [WindowMergeItem<Key, PID, Value>],
        snapshot: [WindowMergeItem<Key, PID, Value>],
        unresponsivePIDs: Set<PID>,
        seeded: Bool
    ) -> [WindowMergeItem<Key, PID, Value>] {
        var remaining = snapshot
        var merged: [WindowMergeItem<Key, PID, Value>] = []
        merged.reserveCapacity(old.count + snapshot.count)

        for item in old {
            if let index = remaining.firstIndex(where: { $0.pid == item.pid && $0.key == item.key }) {
                merged.append(remaining.remove(at: index))
            } else if unresponsivePIDs.contains(item.pid) {
                merged.append(item)
            }
        }

        merged.append(contentsOf: remaining.sorted { $0.zIndex < $1.zIndex })
        // Before the first usable snapshot there is no MRU history to preserve.
        return seeded ? merged : merged.sorted { $0.zIndex < $1.zIndex }
    }
}
