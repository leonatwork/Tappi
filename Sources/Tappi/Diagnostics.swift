import Foundation

/// A menu bar app has nowhere to print to, which makes "it says it has no
/// permission" impossible to investigate. Everything interesting about startup
/// therefore goes to a file the user can just open.
enum Diagnostics {
    static let url = Settings.directory.appendingPathComponent("diagnostics.log")

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Start each launch with a clean file so it never grows without bound.
    static func reset() {
        try? Data().write(to: url)
    }

    static func log(_ message: String) {
        NSLog("Tappi: %@", message)
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
