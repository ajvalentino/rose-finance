#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/module-cache dist/'Rose Finance.app'/Contents/MacOS
SDK=$(xcrun --show-sdk-path)
for ARCH in arm64 x86_64; do
    swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macosx13.0" -module-cache-path .build/module-cache Sources/*.swift -o ".build/RoseFinance-$ARCH"
done
lipo -create .build/RoseFinance-arm64 .build/RoseFinance-x86_64 -output 'dist/Rose Finance.app/Contents/MacOS/RoseFinance'
cat > 'dist/Rose Finance.app/Contents/Info.plist' <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RoseFinance</string>
<key>CFBundleIdentifier</key><string>local.rosefinance.mac</string>
<key>CFBundleName</key><string>Rose Finance</string>
<key>CFBundleDisplayName</key><string>Rose Finance</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - 'dist/Rose Finance.app'
ditto -c -k --keepParent 'dist/Rose Finance.app' 'dist/Rose Finance-Mac.zip'
printf 'Built companion/dist/Rose Finance.app and Mac zip (Apple Silicon + Intel, macOS 13+).\n'
