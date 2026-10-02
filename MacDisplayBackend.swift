import AppKit
import CoreGraphics
import IOKit
import Darwin

private struct LayoutDisplay {
    let id: CGDirectDisplayID
    let identity: String
    let mode: CGDisplayMode?
    let origin: CGPoint
    let mirror: CGDirectDisplayID
}

final class MacDisplayBackend: DisplayBackend {
    private typealias ConfigureEnabled = @convention(c) (CGDisplayConfigRef, UInt32, Bool) -> Int32
    private let library: UnsafeMutableRawPointer?
    private let configureEnabled: ConfigureEnabled?
    private var disabledIDs: Set<CGDirectDisplayID> = []

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        library = handle
        if let handle,
           let symbol = dlsym(handle, "SLSConfigureDisplayEnabled") ?? dlsym(handle, "CGSConfigureDisplayEnabled") {
            configureEnabled = unsafeBitCast(symbol, to: ConfigureEnabled.self)
        } else { configureEnabled = nil }
    }
    deinit { if let library { dlclose(library) } }
    var supported: Bool { configureEnabled != nil }

    private func checked(_ result: CGError, _ operation: String) throws {
        guard result == .success else {
            throw DisplayFailure.unavailable("\(operation) failed (macOS error \(result.rawValue)).")
        }
    }
    private func identity(_ id: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "id:\(id)" }
        return CFUUIDCreateString(nil, uuid) as String
    }
    private func onlineIDs() throws -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        try checked(CGGetOnlineDisplayList(0, nil, &count), "Reading displays")
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        try checked(CGGetOnlineDisplayList(count, &ids, &count), "Reading displays")
        return Array(ids.prefix(Int(count)))
    }
    private func lidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, nil, 0)?
            .takeRetainedValue() as? Bool ?? false
    }
    func snapshot() throws -> DisplaySnapshot {
        let ids = try onlineIDs()
        let closed = lidClosed()
        let states = ids.map { id -> DisplayState in
            let builtIn = CGDisplayIsBuiltin(id) != 0
            let screen = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }
            return DisplayState(id: id, identity: identity(id),
                                name: screen?.localizedName ?? (builtIn ? "Laptop screen" : "External display \(id)"),
                                builtIn: builtIn,
                                usable: (CGDisplayIsActive(id) != 0 || CGDisplayMirrorsDisplay(id) != 0)
                                    && !(builtIn && closed))
        }
        let layout = states.filter(\.usable).map(\.id).map {
            LayoutDisplay(id: $0, identity: identity($0), mode: CGDisplayCopyDisplayMode($0),
                          origin: CGDisplayBounds($0).origin, mirror: CGDisplayMirrorsDisplay($0))
        }
        return DisplaySnapshot(displays: states, payload: layout)
    }

    private func transaction(_ apply: (CGDisplayConfigRef, ConfigureEnabled) throws -> Void) throws {
        guard let enabled = configureEnabled else {
            throw DisplayFailure.unavailable("This macOS version does not expose the required display control API.")
        }
        var pending: CGDisplayConfigRef?
        try checked(CGBeginDisplayConfiguration(&pending), "Starting display configuration")
        guard let config = pending else { throw DisplayFailure.unavailable("macOS returned no display configuration.") }
        do { try apply(config, enabled) }
        catch { CGCancelDisplayConfiguration(config); throw error }
        // Use temporary scope, but explicitly restore enablement: private display
        // disconnects do not reliably revert when the process exits on this Mac.
        try checked(CGCompleteDisplayConfiguration(config, .forAppOnly), "Applying display configuration")
    }

    private func setEnabled(_ id: CGDirectDisplayID, _ value: Bool,
                            config: CGDisplayConfigRef, function: ConfigureEnabled) throws {
        let result = function(config, id, value)
        guard result == 0 else {
            throw DisplayFailure.unavailable("macOS could not \(value ? "enable" : "disable") display \(id) (error \(result)).")
        }
    }

    func disableExternal(_ ids: [UInt32], keeping builtIn: UInt32) throws {
        let current = try snapshot()
        guard current.displays.contains(where: { $0.id == builtIn && $0.builtIn && $0.usable }),
              ids.allSatisfy({ id in current.displays.contains { $0.id == id && !$0.builtIn && $0.usable } }) else {
            throw DisplayFailure.unavailable("The display connection changed. Restore and try again with the laptop lid open.")
        }
        disabledIDs.formUnion(ids)
        try transaction { config, function in
            // Only change enablement for the external targets. Redundantly enabling
            // an already-enabled display makes this transaction fail with error 1001.
            for id in ids { try setEnabled(id, false, config: config, function: function) }
        }
    }

    func restore(_ snapshot: DisplaySnapshot) throws {
        guard let layout = snapshot.payload as? [LayoutDisplay] else {
            throw DisplayFailure.unavailable("No original display arrangement is available.")
        }
        let online = try onlineIDs()
        // Prefer UUIDs if reconnecting changed display IDs. Never apply a saved mode to a different monitor.
        var mapped: [CGDirectDisplayID: CGDirectDisplayID] = [:]
        for display in layout {
            if let matching = online.first(where: { identity($0) == display.identity }) {
                mapped[display.id] = matching
            } else if !online.contains(display.id) && disabledIDs.contains(display.id) {
                // macOS hides the disabled display's UUID. Its cached ID is the
                // reconnect handle until it is enabled again. Allow only IDs this
                // backend actually targeted, never a generic scan of guessed IDs.
                mapped[display.id] = display.id
            } else {
                throw DisplayFailure.unavailable("A display was unplugged or its identity changed. Reconnect the monitor or dock, then try Restore again.")
            }
        }
        let offline = layout.map { mapped[$0.id]! }.filter { !online.contains($0) }
        if !offline.isEmpty {
            try transaction { config, function in
                for id in offline { try setEnabled(id, true, config: config, function: function) }
            }
            let deadline = Date().addingTimeInterval(3)
            while !offline.allSatisfy({ CGDisplayIsOnline($0) != 0 }) && Date() < deadline { usleep(50_000) }
            guard offline.allSatisfy({ CGDisplayIsOnline($0) != 0 }) else {
                throw DisplayFailure.unavailable("macOS accepted the reconnect request but the monitor did not return.")
            }
        }
        for display in layout {
            guard identity(mapped[display.id]!) == display.identity else {
                throw DisplayFailure.unavailable("The reconnected monitor has a different identity. Reconnect the original monitor and try Restore again.")
            }
        }
        // Re-enabling often restores the complete previous mirror/layout itself.
        // Do not manufacture an unnecessary unmirror/reconfigure transaction.
        let alreadyRestored = layout.allSatisfy { display in
            let id = mapped[display.id]!
            return CGDisplayBounds(id).origin == display.origin
                && CGDisplayMirrorsDisplay(id) == (mapped[display.mirror] ?? kCGNullDirectDisplay)
                && CGDisplayCopyDisplayMode(id)?.ioDisplayModeID == display.mode?.ioDisplayModeID
        }
        if alreadyRestored { disabledIDs.removeAll(); return }
        try transaction { config, _ in
            for display in layout where CGDisplayMirrorsDisplay(mapped[display.id]!) != 0 {
                try checked(CGConfigureDisplayMirrorOfDisplay(config, mapped[display.id]!, kCGNullDirectDisplay), "Restoring displays")
            }
            // A mirrored follower's synthetic mode belongs to its mirror source.
            // Restore the source mode/origin, then attach followers to that source.
            for display in layout where display.mirror == kCGNullDirectDisplay {
                let id = mapped[display.id]!
                if let mode = display.mode {
                    try checked(CGConfigureDisplayWithDisplayMode(config, id, mode, nil), "Restoring resolution")
                }
                try checked(CGConfigureDisplayOrigin(config, id, Int32(display.origin.x), Int32(display.origin.y)), "Restoring arrangement")
            }
            for display in layout where display.mirror != kCGNullDirectDisplay {
                guard let source = mapped[display.mirror] else {
                    throw DisplayFailure.unavailable("The original mirrored display is unavailable.")
                }
                try checked(CGConfigureDisplayMirrorOfDisplay(config, mapped[display.id]!, source), "Restoring mirroring")
            }
        }
        disabledIDs.removeAll()
    }
}
