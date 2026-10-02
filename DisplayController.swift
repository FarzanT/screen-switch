import Foundation

struct DisplayState {
    let id: UInt32
    let identity: String
    let name: String
    let builtIn: Bool
    let usable: Bool
}

struct DisplaySnapshot {
    let displays: [DisplayState]
    let payload: Any?
}

protocol DisplayBackend {
    func snapshot() throws -> DisplaySnapshot
    func disableExternal(_ ids: [UInt32], keeping builtIn: UInt32) throws
    func restore(_ snapshot: DisplaySnapshot) throws
}

enum DisplayFailure: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): return message }
    }
}

final class DisplayController {
    let backend: DisplayBackend
    private(set) var saved: DisplaySnapshot?
    private(set) var switchApplied = false
    init(backend: DisplayBackend) { self.backend = backend }
    func laptopOnly() throws {
        guard saved == nil else { return }
        let current = try backend.snapshot()
        guard let laptop = current.displays.first(where: { $0.builtIn && $0.usable }) else {
            throw DisplayFailure.unavailable("Open the laptop lid and make sure its screen is available first.")
        }
        let external = current.displays.filter { !$0.builtIn && $0.usable }.map(\.id)
        guard !external.isEmpty else { return }
        // Retain the original arrangement even if macOS partially applies a change.
        saved = current
        try backend.disableExternal(external, keeping: laptop.id)
        switchApplied = true
    }
    func restore() throws {
        guard let original = saved else { return }
        try backend.restore(original)
        saved = nil
        switchApplied = false
    }
}
