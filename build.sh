#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
output_dir="$source_dir/build"
final_app_dir="$output_dir/ScreenSwitch.app"
staging_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/laptop-only-build.XXXXXX")"
app_dir="$staging_dir/ScreenSwitch.app"
trap '/bin/rm -rf "$staging_dir"' EXIT
build_dir="$source_dir/.build"
developer_dir="$(/usr/bin/xcode-select -p)"
compiler="$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
if [ ! -x "$compiler" ]; then compiler="$(/usr/bin/xcrun --find swiftc)"; fi
sdk_dir="$developer_dir/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
if [ ! -d "$sdk_dir" ]; then sdk_dir="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"; fi
arch="$(/usr/bin/uname -m)"
mkdir -p "$build_dir" "$output_dir" "$app_dir/Contents/MacOS"
"$compiler" -sdk "$sdk_dir" -target "$arch-apple-macosx14.0" \
  "$source_dir/DisplayController.swift" "$source_dir/ControllerTests.swift" \
  -o "$build_dir/controller-tests"
"$build_dir/controller-tests"
"$compiler" -sdk "$sdk_dir" -target "$arch-apple-macosx14.0" -O \
  "$source_dir/DisplayController.swift" "$source_dir/MacDisplayBackend.swift" \
  "$source_dir/MenuBarApp.swift" -framework AppKit -framework CoreGraphics -framework IOKit \
  -o "$app_dir/Contents/MacOS/LaptopOnly"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ScreenSwitch</string>
<key>CFBundleDisplayName</key><string>ScreenSwitch</string>
<key>CFBundleIdentifier</key><string>io.github.farzant.screenswitch</string>
<key>CFBundleExecutable</key><string>LaptopOnly</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$app_dir/Contents/Info.plist"
# Sign outside Documents: File Provider continually adds FinderInfo to live .app
# bundles there, which makes signing/strict verification race with its metadata.
/usr/bin/codesign --force --sign - "$app_dir"
/usr/bin/codesign --verify --strict "$app_dir"
"$app_dir/Contents/MacOS/LaptopOnly" --diagnose
if [ "${1:-}" = "--hardware-test" ]; then
  "$compiler" -sdk "$sdk_dir" -target "$arch-apple-macosx14.0" \
    "$source_dir/DisplayController.swift" "$source_dir/MacDisplayBackend.swift" \
    "$source_dir/HardwareSmokeTest.swift" -framework AppKit -framework CoreGraphics -framework IOKit \
    -o "$build_dir/hardware-smoke-test"
  "$build_dir/hardware-smoke-test"
  "$build_dir/hardware-smoke-test" --extended
fi
/usr/bin/ditto --norsrc --noextattr "$app_dir" "$final_app_dir"
/usr/bin/xattr -dr com.apple.FinderInfo "$final_app_dir" 2>/dev/null || true
printf '\nBuilt: %s\n' "$final_app_dir"
