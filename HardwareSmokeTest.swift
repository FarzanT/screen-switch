import AppKit
import CoreGraphics
import Darwin

/// Optional hardware verification. This briefly disables and restores external displays.
@main struct HardwareSmokeTest {
    static func fingerprint(_ snapshot: DisplaySnapshot) -> [String] {
        snapshot.displays.filter(\.usable).map { display in
            let mode = CGDisplayCopyDisplayMode(display.id)
            return "\(display.identity):active=\(CGDisplayIsActive(display.id)),mirror=\(CGDisplayMirrorsDisplay(display.id)),bounds=\(CGDisplayBounds(display.id)),mode=\(mode?.ioDisplayModeID ?? 0)"
        }.sorted()
    }
    static func main() {
        setbuf(stdout, nil)
        let backend = MacDisplayBackend()
        let controller = DisplayController(backend: backend)
        var original: DisplaySnapshot?
        var originalFingerprint: [String] = []
        do {
            let baseline = try backend.snapshot()
            original = baseline
            originalFingerprint = fingerprint(baseline)
            guard baseline.displays.contains(where: { $0.builtIn && $0.usable }),
                  baseline.displays.contains(where: { !$0.builtIn && $0.usable }) else {
                throw DisplayFailure.unavailable("Connect an external monitor and open the laptop lid before this test.")
            }
            if CommandLine.arguments.contains("--extended") {
                let laptop = baseline.displays.first { $0.builtIn && $0.usable }!
                let external = baseline.displays.first { !$0.builtIn && $0.usable }!
                var pending: CGDisplayConfigRef?
                guard CGBeginDisplayConfiguration(&pending) == .success, let config = pending else {
                    throw DisplayFailure.unavailable("Could not prepare extended-mode test.")
                }
                let mirrorResult = CGConfigureDisplayMirrorOfDisplay(config, external.id, 0)
                let originResult = CGConfigureDisplayOrigin(config, external.id, Int32(CGDisplayBounds(laptop.id).width), 0)
                guard mirrorResult == .success, originResult == .success else {
                    CGCancelDisplayConfiguration(config)
                    throw DisplayFailure.unavailable("Could not prepare extended-mode arrangement.")
                }
                let result = CGCompleteDisplayConfiguration(config, .forAppOnly)
                guard result == .success else { throw DisplayFailure.unavailable("Extended-mode preparation failed: \(result.rawValue)") }
                usleep(700_000)
            }
            let before = try backend.snapshot()
            let expected = fingerprint(before)
            print("BEFORE: \(expected)")
            try controller.laptopOnly()
            usleep(700_000)
            let off = try backend.snapshot().displays
            guard off.contains(where: { $0.builtIn && $0.usable }),
                  !off.contains(where: { !$0.builtIn && $0.usable }) else {
                throw DisplayFailure.unavailable("The external display did not disable, or the laptop screen is unavailable.")
            }
            print("PASS: external disabled; built-in screen remains active")
            try controller.restore()
            var after = fingerprint(try backend.snapshot())
            let deadline = Date().addingTimeInterval(3)
            while after != expected && Date() < deadline {
                usleep(100_000)
                after = fingerprint(try backend.snapshot())
            }
            print("AFTER: \(after)")
            guard after == expected else { throw DisplayFailure.unavailable("Restoration differs from the saved arrangement.") }
            print("PASS: monitor restored with original mode, bounds, and mirroring")
            if CommandLine.arguments.contains("--extended") {
                try backend.restore(baseline)
                usleep(500_000)
                guard fingerprint(try backend.snapshot()) == originalFingerprint else {
                    throw DisplayFailure.unavailable("The extended-mode test did not restore the user's original arrangement.")
                }
                print("PASS: user's pre-test arrangement restored")
            }
        } catch {
            print("FAIL: \(error.localizedDescription)")
            do {
                try controller.restore()
                if let original { try backend.restore(original) }
            } catch { print("RECOVERY FAILED: \(error.localizedDescription)") }
            exit(1)
        }
    }
}
