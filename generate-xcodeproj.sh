#!/bin/bash
# Generates the Xcode project for ClaudeShell.
# Run this on macOS: bash generate-xcodeproj.sh
#
# Alternatively, use the GitHub Actions CI which handles this automatically.

set -e

PROJECT_NAME="ClaudeShell"
BUNDLE_ID="com.claudeshell.app"

echo "=== Generating $PROJECT_NAME Xcode Project ==="

# Check for xcodegen (brew install xcodegen)
if ! command -v xcodegen &> /dev/null; then
    echo "Installing xcodegen..."
    brew install xcodegen
fi

# Generate project.yml for xcodegen
cat > project.yml << 'XCODEGEN_EOF'
name: ClaudeShell
options:
  bundleIdPrefix: com.claudeshell
  deploymentTarget:
    iOS: "16.0"
  xcodeVersion: "15.0"

settings:
  base:
    SWIFT_VERSION: "5.9"
    CLANG_ENABLE_MODULES: YES
    SWIFT_OBJC_BRIDGING_HEADER: "ClaudeShell/Bridge/ClaudeShell-Bridging-Header.h"

targets:
  ClaudeShell:
    type: application
    platform: iOS
    sources:
      - path: ClaudeShell
        excludes:
          - Tests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.claudeshell.app
        INFOPLIST_FILE: ClaudeShell/Info.plist
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        TARGETED_DEVICE_FAMILY: "1,2"  # iPhone + iPad
        SWIFT_OBJC_BRIDGING_HEADER: "ClaudeShell/Bridge/ClaudeShell-Bridging-Header.h"
        CODE_SIGN_STYLE: Automatic
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        SUPPORTS_MACCATALYST: NO
        # C compilation settings for shell engine
        OTHER_CFLAGS: "-DIOS_BUILD"
        GCC_C_LANGUAGE_STANDARD: c11
    entitlements:
      path: ClaudeShell/ClaudeShell.entitlements

  ClaudeShellTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: ClaudeShell/Tests
    dependencies:
      - target: ClaudeShell
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.claudeshell.app.tests
XCODEGEN_EOF

# Create Info.plist
mkdir -p ClaudeShell
cat > ClaudeShell/Info.plist << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ClaudeShell</string>
    <key>CFBundleDisplayName</key>
    <string>ClaudeShell</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>arm64</string>
    </array>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UILaunchScreen</key>
    <dict>
        <key>UIColorName</key>
        <string>LaunchBackground</string>
    </dict>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>UIStatusBarStyle</key>
    <string>UIStatusBarStyleLightContent</string>
    <key>UIUserInterfaceStyle</key>
    <string>Dark</string>
</dict>
</plist>
PLIST_EOF

# Create entitlements
cat > ClaudeShell/ClaudeShell.entitlements << 'ENT_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
ENT_EOF

# Generate Xcode project
xcodegen generate

echo ""
echo "=== Done! ==="
echo "Open ClaudeShell.xcodeproj in Xcode"
echo ""
echo "To build and run:"
echo "  1. Open ClaudeShell.xcodeproj"
echo "  2. Select your iPhone or simulator"
echo "  3. Set your signing team (Xcode > Target > Signing & Capabilities)"
echo "  4. Press Cmd+R to run"
