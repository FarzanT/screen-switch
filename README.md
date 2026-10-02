# ScreenSwitch 0.3 — free menu bar app

An experimental, free utility written in Swift and AppKit.

This small native app puts a monitor icon with a **Screen** label in the macOS menu bar, positioned toward the clock. It has two main actions:

- **Laptop screen only:** disconnect external displays from the desktop while keeping the laptop screen enabled.
- **Restore external screen:** restore the captured resolution, position, and mirror relationships.

## Try it

1. Build the source using the instructions below, then open **ScreenSwitch.app** in `build/`. Look for **Screen** with a monitor icon toward the right of the menu bar. Launching does not change your displays.
2. Keep your laptop lid open. Click the icon and choose **Laptop screen only**. The first click shows a compatibility notice.
3. Choose **Restore external screen** to bring back your previous arrangement.
4. **Restore and Quit** attempts to restore the displays before closing the app.

Move the app to `/Applications` (or `~/Applications`) for a stable installation. To start it automatically, add that installed copy under System Settings → General → Login Items & Extensions → Open at Login. The app survives restarts as a file; it does not start at login unless you add it. Launch does not automatically disable any screens, and the saved Restore arrangement is held in memory for the current run.

## What has been verified

The build script compiles and runs eight controller tests for built-in-screen protection, external-only targeting, original-arrangement retention, harmless switching with no external screen, recovery state after errors, and avoiding a success-verification alert after a failed switch. It compiles and locally signs the app, verifies the signature, and runs read-only display diagnostics.

**An actual display off/on cycle passed on this Mac with the Dell U2718Q, in both mirrored and extended mode.** The hardware test checked that the external display disappeared while the built-in screen stayed active, then compared the original and restored screen identities, modes, bounds, and mirror relationships. The test also restored the user's arrangement after temporarily testing extended mode. This evidence covers this Mac and connected monitor; it does not establish compatibility with every dock or OS version.

macOS display control uses an undocumented SkyLight API, dynamically loaded at runtime. Its behavior can change with macOS updates and vary by monitor/dock. If restoration fails, unplug and reconnect the monitor cable or dock. Display changes request CoreGraphics' app-only scope rather than permanent display settings, but **private display disconnects did not automatically revert when the test process exited on this Mac**. Restore and normal Quit explicitly re-enable the saved external display IDs. If the app crashes or is force-quit while an external display is disabled, cable reconnection may be needed.

Version 0.2 fixes error 1001 by changing only external display enablement: redundant requests to enable an already-enabled display were rejected. It restores disabled displays using their cached IDs because macOS hides their UUIDs until they are enabled again. It avoids a second, misleading verification alert after a failed switch.

This disconnects the display from the Mac desktop. It does not send a hardware power-button command: whether the monitor enters standby or shows a no-signal message depends on the monitor. Dock USB and charging are not intentionally changed. The app does not preserve individual app window positions or virtual desktops. DisplayLink or other USB graphics drivers may need a different implementation.

The app has no network code, paid dependency, administrator requirement, or automatic login-item registration. The current local build is for Apple Silicon and requires macOS 14 or later. Public distribution initially provides source; no notarized release is available. The script can compile for the host architecture, but Intel hardware operation has not been verified. It is locally signed, not notarized for general distribution.

## Rebuild

With Xcode or its Command Line Tools installed, clone the repository and build:

```bash
git clone https://github.com/FarzanT/screen-switch.git
cd screen-switch
```

Then run:

```bash
bash build.sh
```

Run this command from the repository root. It builds `build/ScreenSwitch.app` for the current Mac's architecture. To list displays without changing them, run the app executable with `--diagnose`.

To repeat the optional hardware verification, run `bash build.sh --hardware-test`. This briefly changes display configurations, tests disable/restore in the current arrangement and in extended mode, and restores the original arrangement. Keep the laptop lid open and the external monitor connected.

Files:

- `DisplayController.swift`: switching safety and recovery state.
- `MacDisplayBackend.swift`: checked CoreGraphics transactions and private API lookup.
- `MenuBarApp.swift`: AppKit menu bar UI.
- `ControllerTests.swift`: eight controller tests using a simulated display backend.
- `HardwareSmokeTest.swift`: optional off/on verification on real hardware; it changes displays and restores them.
- `build.sh`: build, tests, bundle creation, signing, and read-only diagnostics.

API approach researched from [displayplacer](https://github.com/jakehilborn/displayplacer), its [reconnect discussion](https://github.com/jakehilborn/displayplacer/issues/137), [LightsOut](https://github.com/AlonX2/LightsOut), and Apple's [app-scoped configuration option](https://developer.apple.com/documentation/coregraphics/cgconfigureoption/forapponly). These apps informed the API approach; they are not bundled dependencies.

## Sharing and open source

Licensed under MIT; see [LICENSE](LICENSE). You can build, modify, and share this app. Retain license notices when redistributing. The source can be published on GitHub independently of distributing a ready-to-run app.

The build is ad-hoc signed, not Developer ID signed or notarized. A copy downloaded by someone else may be blocked by Gatekeeper. For a convenient public binary release, use your own Developer ID signing identity and Apple's notarization process. Building from source on the recipient's Mac avoids relying on our locally built binary. No signing certificate or credentials are included here.

### Relationship to LightsOut

[LightsOut](https://github.com/AlonX2/LightsOut) is an existing free, MIT-licensed menu bar utility with the same core display-disable capability, including individual-monitor controls and an optional mirror-based method. ScreenSwitch focuses on one action that disables all external screens while keeping the built-in screen available, plus explicit restoration. Both rely on private macOS display APIs. This is not a claim that ScreenSwitch is generally safer or more compatible. Only the documented hardware tests are established.

If your goal is an existing general display utility, evaluate LightsOut. This repository is useful as a small, inspectable implementation and a basis for contributions. See [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md) for API references consulted during development.
