#!/bin/bash
# Run this on a Mac to set up the Xcode project for ClaudeShell
# Requires: Xcode 15+, macOS 14+

set -e

echo "=== ClaudeShell Xcode Project Setup ==="

# Check for Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "Error: Xcode not found. Install Xcode from the App Store."
    exit 1
fi

# Create Xcode project using swift package
echo "Generating Xcode project..."
swift package generate-xcodeproj 2>/dev/null || true

# If SPM project generation doesn't work, create manually
if [ ! -d "ClaudeShell.xcodeproj" ]; then
    echo "Creating Xcode project manually..."

    mkdir -p ClaudeShell.xcodeproj

    cat > ClaudeShell.xcodeproj/project.pbxproj << 'PBXPROJ'
// !$*UTF8*$!
{
    archiveVersion = 1;
    classes = {};
    objectVersion = 56;
    objects = {
        /* This is a placeholder. Open in Xcode and add files manually, or use: */
        /* File > New > Project > iOS App > ClaudeShell */
        /* Then drag in the ClaudeShell/ folder */
    };
    rootObject = "";
}
PBXPROJ

    echo ""
    echo "NOTE: The auto-generated project needs manual setup."
    echo ""
    echo "Easiest approach:"
    echo "  1. Open Xcode"
    echo "  2. File > New > Project > iOS > App"
    echo "  3. Name: ClaudeShell, Interface: SwiftUI, Language: Swift"
    echo "  4. Delete the auto-generated ContentView.swift"
    echo "  5. Drag the ClaudeShell/ folder into the project navigator"
    echo "  6. In Build Settings:"
    echo "     - Set 'Objective-C Bridging Header' to:"
    echo "       ClaudeShell/Bridge/ClaudeShell-Bridging-Header.h"
    echo "     - Set 'iOS Deployment Target' to 16.0"
    echo "  7. Build & Run on device or simulator"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To build and run:"
echo "  open ClaudeShell.xcodeproj"
echo "  # Or: xcodebuild -scheme ClaudeShell -destination 'platform=iOS Simulator,name=iPhone 15'"
echo ""
echo "To set up Claude API:"
echo "  1. Run the app"
echo "  2. Type: export ANTHROPIC_API_KEY=sk-ant-your-key-here"
echo "  3. Type: claude ask \"hello world\""
