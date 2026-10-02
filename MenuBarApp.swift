import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let backend = MacDisplayBackend()
    private lazy var controller = DisplayController(backend: backend)
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenuBar()
    }

    func installMenuBar() {
        guard statusItem == nil else { return }
        if UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position LaptopOnly") == nil {
            UserDefaults.standard.set(0, forKey: "NSStatusItem Preferred Position LaptopOnly")
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "LaptopOnly"
        statusItem.isVisible = true
        statusItem.button?.title = "Screen"
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "ScreenSwitch")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "ScreenSwitch — external display control"
        menu.delegate = self
        statusItem.menu = menu
        refreshMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            NSLog("LaptopOnly status visible=%@ frame=%@", self.statusItem.isVisible.description,
                  NSStringFromRect(self.statusItem.button?.window?.frame ?? .zero))
        }
    }

    private func item(_ title: String, action: Selector?, enabled: Bool = true) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self; entry.isEnabled = enabled
        menu.addItem(entry)
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    private func refreshMenu() {
        menu.removeAllItems()
        item("ScreenSwitch", action: nil, enabled: false)
        let displays = (try? backend.snapshot().displays) ?? []
        let internalAvailable = displays.contains { $0.builtIn && $0.usable }
        let externalCount = displays.filter { !$0.builtIn && $0.usable }.count
        if controller.saved != nil {
            item("Original arrangement saved", action: nil, enabled: false)
        } else {
            item("\(externalCount) external display\(externalCount == 1 ? "" : "s") available", action: nil, enabled: false)
        }
        menu.addItem(.separator())
        item("Laptop screen only", action: #selector(laptopOnly),
             enabled: backend.supported && internalAvailable && externalCount > 0 && controller.saved == nil)
        item("Restore external screen", action: #selector(restore), enabled: controller.saved != nil)
        if !internalAvailable { item("Open the laptop lid to switch", action: nil, enabled: false) }
        if !backend.supported { item("Display control unavailable on this macOS", action: nil, enabled: false) }
        menu.addItem(.separator())
        item("Display Settings…", action: #selector(displaySettings))
        item("About ScreenSwitch…", action: #selector(about))
        menu.addItem(.separator())
        item(controller.saved == nil ? "Quit" : "Restore and Quit", action: #selector(quit))
        statusItem.button?.image = NSImage(systemSymbolName: controller.switchApplied ? "laptopcomputer" : "display",
                                         accessibilityDescription: "ScreenSwitch")
        statusItem.button?.image?.isTemplate = true
    }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let dialog = NSAlert()
        dialog.messageText = title; dialog.informativeText = message
        dialog.addButton(withTitle: "OK")
        dialog.runModal()
    }

    @objc private func laptopOnly() {
        if !UserDefaults.standard.bool(forKey: "hasSeenCompatibilityNotice") {
            NSApp.activate(ignoringOtherApps: true)
            let notice = NSAlert()
            notice.messageText = "Use the laptop screen only?"
            notice.informativeText = "This app disconnects external displays from the desktop while keeping the laptop screen enabled. Dock compatibility varies. If Restore cannot bring your monitor back, unplug and reconnect its display cable or the dock."
            notice.addButton(withTitle: "Use Laptop Screen")
            notice.addButton(withTitle: "Cancel")
            guard notice.runModal() == .alertFirstButtonReturn else { return }
            UserDefaults.standard.set(true, forKey: "hasSeenCompatibilityNotice")
        }
        do { try controller.laptopOnly() }
        catch {
            alert("Could not switch displays", error.localizedDescription + "\n\nUse Restore external screen to recover the original arrangement.")
            refreshMenu()
            return
        }
        refreshMenu()
        // Some private API calls report success without actually changing the desktop.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.controller.switchApplied else { return }
            do {
                let displays = try self.backend.snapshot().displays
                if displays.contains(where: { !$0.builtIn && $0.usable }) {
                    self.alert("External display is still active", "macOS did not fully disconnect the external display. Use Restore external screen. This dock may need a different control method.")
                }
            } catch { self.alert("Could not verify display state", error.localizedDescription) }
            self.refreshMenu()
        }
    }

    @objc private func restore() {
        do { try controller.restore() }
        catch {
            alert("Could not restore the external screen", error.localizedDescription + "\n\nUnplug and reconnect the monitor cable or dock, then try Restore again.")
        }
        refreshMenu()
    }

    @objc private func displaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func about() {
        alert("ScreenSwitch • Version 0.3", "A free local menu bar app. Choose Laptop screen only to disconnect external displays, and Restore external screen to return to the saved arrangement.\n\nNo network access, paid dependency, or login item. Display control uses an undocumented macOS API and may need updating after an OS upgrade.\n\nRestore explicitly reconnects the monitor. Quit attempts restoration. If the app crashes while a monitor is disabled, reconnect its cable or dock. The source is included beside the app.")
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do { try controller.restore(); return .terminateNow }
        catch {
            NSApp.activate(ignoringOtherApps: true)
            let dialog = NSAlert()
            dialog.messageText = "The external screen could not be restored"
            dialog.informativeText = error.localizedDescription + "\n\nKeep the app open to retry, or reconnect the monitor cable or dock. Quitting alone may leave the external display disabled."
            dialog.addButton(withTitle: "Keep App Open")
            dialog.addButton(withTitle: "Quit Anyway")
            return dialog.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
        }
    }
}

@main struct LaptopOnlyApp {
    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            let backend = MacDisplayBackend()
            print("Display control symbol available: \(backend.supported)")
            do {
                for display in try backend.snapshot().displays {
                    print("\(display.name): id=\(display.id), built-in=\(display.builtIn), usable=\(display.usable)")
                }
                print("Read-only diagnostics complete; no display configuration changed.")
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        delegate.installMenuBar()
        withExtendedLifetime(delegate) { app.run() }
    }
}
