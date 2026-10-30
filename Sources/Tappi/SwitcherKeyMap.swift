/// Build once per layout change; the tap only reads the resulting action table.
struct SwitcherKeyMap {
    enum Action: Equatable { case closeWindow, quitApp }

    private var actions: [Int64: Action] = [:]

    init(currentCharacters: [Int64: String], asciiCharacters: [Int64: String]? = nil) {
        let reserved = KeyCode.aboveTab.union([
            KeyCode.tab, KeyCode.escape, KeyCode.ret, KeyCode.space,
            KeyCode.left, KeyCode.right, KeyCode.up, KeyCode.down,
            KeyCode.backspace, KeyCode.forwardDelete
        ])
        let current = currentCharacters.filter { !reserved.contains($0.key) }
        let ascii = (asciiCharacters ?? currentCharacters).filter { !reserved.contains($0.key) }
        let letters: [(String, Int64, Action)] = [("w", KeyCode.w, .closeWindow), ("q", KeyCode.q, .quitApp)]
        for (letter, fallback, action) in letters {
            // AC-5 explicitly requires ANSI for non-Latin layouts, even if TIS's
            // ASCII source remembers a previously used AZERTY/Dvorak layout.
            let hasLatinLetter = current.values.contains { $0.lowercased() == letter }
            let keys = hasLatinLetter ? ascii.filter { $0.value.lowercased() == letter }.map(\.key) : []
            if keys.isEmpty { actions[fallback] = action }
            else { for key in keys { actions[key] = action } }
        }
        actions[KeyCode.backspace] = .closeWindow
        actions[KeyCode.forwardDelete] = .closeWindow
    }

    subscript(keyCode: Int64) -> Action? { actions[keyCode] }
}
