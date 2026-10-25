#!/bin/zsh
set -eu
cd "${0:A:h}/.."
swift build -c release
APP="dist/Graphical Circuits.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/GraphicalCircuits "$APP/Contents/MacOS/GraphicalCircuits"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GraphicalCircuits</string>
<key>CFBundleIdentifier</key><string>com.kavrous.graphical-circuits</string>
<key>CFBundleName</key><string>Graphical Circuits</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
