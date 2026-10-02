import Foundation

final class FakeBackend: DisplayBackend {
    var displays = [DisplayState(id: 1, identity: "internal", name: "Laptop", builtIn: true, usable: true),
                    DisplayState(id: 2, identity: "external", name: "Monitor", builtIn: false, usable: true)]
    var disabled: [UInt32] = []
    var kept: UInt32?
    var captured = 0
    var restored: DisplaySnapshot?
    var failDisable = false
    var failRestore = false
    func snapshot() throws -> DisplaySnapshot {
        captured += 1
        return DisplaySnapshot(displays: displays, payload: nil)
    }
    func disableExternal(_ ids: [UInt32], keeping builtIn: UInt32) throws {
        disabled = ids; kept = builtIn
        if failDisable { throw DisplayFailure.unavailable("disable failed") }
    }
    func restore(_ snapshot: DisplaySnapshot) throws {
        if failRestore { throw DisplayFailure.unavailable("restore failed") }
        restored = snapshot
    }
}

@main struct Tests {
    static func main() {
        var failures = 0
        func test(_ name: String, _ body: () throws -> Bool) {
            do {
                if try body() { print("PASS: \(name)") }
                else { print("FAIL: \(name)"); failures += 1 }
            } catch { print("FAIL: \(name): \(error)"); failures += 1 }
        }
        test("only external displays are disabled; laptop stays enabled") {
            let b = FakeBackend(); let c = DisplayController(backend: b)
            try c.laptopOnly()
            return b.disabled == [2] && b.kept == 1 && c.saved != nil
        }
        test("no usable built-in display rejects switching") {
            let b = FakeBackend(); b.displays.removeFirst()
            let c = DisplayController(backend: b)
            do { try c.laptopOnly(); return false }
            catch { return b.disabled.isEmpty && c.saved == nil }
        }
        test("already laptop-only does not overwrite restoration snapshot") {
            let b = FakeBackend(); let c = DisplayController(backend: b)
            try c.laptopOnly(); b.displays.removeLast(); try c.laptopOnly()
            try c.restore()
            return b.captured == 1 && b.restored?.displays.count == 2 && c.saved == nil
        }
        test("failed restoration retains snapshot for retry") {
            let b = FakeBackend(); let c = DisplayController(backend: b)
            try c.laptopOnly(); b.failRestore = true
            do { try c.restore(); return false }
            catch { return c.saved != nil }
        }
        test("failed disable retains snapshot for explicit recovery") {
            let b = FakeBackend(); b.failDisable = true
            let c = DisplayController(backend: b)
            do { try c.laptopOnly(); return false }
            catch { return c.saved?.displays.count == 2 }
        }
        test("no external display is a harmless no-op") {
            let b = FakeBackend(); b.displays.removeLast()
            let c = DisplayController(backend: b); try c.laptopOnly()
            return c.saved == nil && b.disabled.isEmpty
        }
        test("failed switch never schedules a success verification") {
            let b = FakeBackend(); b.failDisable = true
            let c = DisplayController(backend: b)
            do { try c.laptopOnly(); return false }
            catch { return c.saved != nil && !c.switchApplied }
        }
        test("successful switch is eligible for verification until restored") {
            let b = FakeBackend(); let c = DisplayController(backend: b)
            try c.laptopOnly(); guard c.switchApplied else { return false }
            try c.restore(); return !c.switchApplied
        }
        print("\(8 - failures)/8 tests passed")
        exit(failures == 0 ? 0 : 1)
    }
}
