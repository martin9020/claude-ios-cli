# Installing ClaudeShell on iPhone

## Overview of Options

| Method | Cost | Mac needed? | Time to install | Limits |
|--------|------|-------------|-----------------|--------|
| **TestFlight** (recommended) | $99/yr Apple Dev | No (cloud build) | ~30 min | 10,000 testers |
| **Sideload (AltStore)** | Free | No | ~15 min | Resign every 7 days |
| **Sideload (Xcode)** | Free Apple ID | Yes (or cloud) | ~10 min | 3 apps, 7-day resign |
| **App Store** | $99/yr Apple Dev | No (cloud build) | 1-7 days (review) | Public release |

---

## Option 1: TestFlight (Best for personal use)

TestFlight lets you install the app directly on your iPhone without App Store review.
Lasts 90 days per build. Up to 10,000 testers.

### Prerequisites
- Apple Developer account ($99/year) → https://developer.apple.com/programs/
- GitHub account (free)

### Steps

1. **Fork/push this repo to GitHub**
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   gh repo create claude-ios-cli --private --push
   ```

2. **Set up GitHub Secrets** (Settings → Secrets → Actions):
   ```
   APPSTORE_API_KEY          # App Store Connect API key ID
   APPSTORE_API_ISSUER       # API issuer ID
   CODE_SIGN_IDENTITY        # "Apple Distribution: Your Name (TEAMID)"
   PROVISIONING_PROFILE      # Profile name from developer portal
   DEVELOPMENT_TEAM          # Your 10-char team ID
   APPLE_CERTIFICATE_P12     # Base64-encoded .p12 certificate
   APPLE_CERTIFICATE_PASSWORD # Certificate password
   ```

3. **Create App ID in Apple Developer Portal**
   - Go to https://developer.apple.com/account/resources/identifiers
   - Register new App ID: `com.yourname.claudeshell`
   - Enable capabilities: Network (Client)

4. **Create provisioning profile**
   - Type: App Store Distribution
   - Select your App ID
   - Download and base64-encode for GitHub secrets

5. **Push to trigger build**
   ```bash
   git push origin main
   ```
   GitHub Actions will build, sign, and upload to App Store Connect.

6. **Set up TestFlight**
   - Go to https://appstoreconnect.apple.com
   - Your app → TestFlight tab
   - Add yourself as internal tester
   - Download TestFlight app on iPhone
   - Accept invite → Install

### Updating
Just push to `main`. GitHub Actions rebuilds and uploads automatically.
TestFlight notifies you of new builds.

---

## Option 2: Sideload with AltStore (Free, no Mac)

AltStore lets you sideload apps using just a Windows PC and your iPhone.

### Prerequisites
- Windows PC (you have this)
- iPhone on same WiFi network
- Free Apple ID

### Steps

1. **Install AltServer on Windows**
   - Download from https://altstore.io
   - Install AltServer
   - Install iCloud for Windows (from Apple, NOT Microsoft Store)
   - Install iTunes for Windows (from Apple, NOT Microsoft Store)

2. **Install AltStore on iPhone**
   - Connect iPhone via USB
   - Open AltServer (system tray)
   - Click "Install AltStore" → Select your iPhone
   - Enter Apple ID when prompted
   - Trust the developer profile on iPhone:
     Settings → General → VPN & Device Management → Trust

3. **Build the IPA** (use GitHub Actions or cloud Mac)
   - Trigger the GitHub Actions build
   - Download the .ipa artifact from the Actions run

4. **Install via AltStore**
   - Open AltStore on iPhone
   - My Apps → + → Select ClaudeShell.ipa
   - Wait for installation

### ⚠️ Limitation
- Free Apple ID: must re-sign every **7 days** (AltStore does this automatically if your PC is on and iPhone is on same WiFi)
- Max 3 sideloaded apps with free account

---

## Option 3: Sideload with Xcode (Requires Mac)

If you have access to a Mac (even temporarily):

```bash
# Clone the project
git clone https://github.com/youruser/claude-ios-cli.git
cd claude-ios-cli

# Open in Xcode
open ClaudeShell.xcodeproj

# In Xcode:
# 1. Select your iPhone as the build target
# 2. Set Signing Team to your Apple ID (free or paid)
# 3. Click Run (⌘R)
```

---

## Option 4: App Store (Public Release)

For distributing to others.

### App Store Review Considerations

Apple will review the app. Key points to pass review:

1. **No arbitrary code execution claims** — Frame it as a "file manager with AI assistant", not a "terminal emulator that runs code"

2. **Required App Store metadata**:
   - App name: "ClaudeShell - AI Dev Assistant"
   - Category: Developer Tools
   - Age rating: 4+
   - Screenshots (6.7" and 6.1" sizes)
   - Privacy policy URL

3. **Potential rejection reasons & mitigations**:
   - ❌ "App duplicates built-in functionality" → Emphasize Claude AI integration as unique value
   - ❌ "Hidden features" → Be transparent about all capabilities
   - ❌ "Runs arbitrary code" → Commands run in sandboxed environment, no system access

4. **App Store Connect setup**:
   ```
   1. Create app in App Store Connect
   2. Fill in all metadata
   3. Upload build via GitHub Actions (or Transporter app)
   4. Submit for review
   5. Wait 1-7 days
   ```

### Automated Publishing Pipeline

The GitHub Actions workflow handles:
```
git push → Build on macOS runner → Sign → Upload to App Store Connect
```

You just need to manually submit for review in App Store Connect (or use the API to automate that too).

---

## Testing Without a Device

### iOS Simulator (via GitHub Actions)

The CI pipeline runs tests on an iPhone simulator automatically on every push.
No hardware needed. Check the Actions tab for test results.

### Local Testing on Windows

You can test the C shell engine locally:
```bash
cd ClaudeShell/Shell
gcc -o shell_test shell.c environment.c builtins.c \
    ../Commands/cmd_filesystem.c \
    ../Commands/cmd_text.c \
    ../Commands/cmd_system.c \
    ../Commands/cmd_network.c \
    -DTEST_MODE
./shell_test
```

This compiles and runs the shell engine natively on Windows (via MinGW/MSYS2)
to test command parsing, environment variables, etc. without needing iOS.

---

## Quick Start Checklist

- [ ] Create Apple Developer account (if using TestFlight/App Store)
- [ ] Push repo to GitHub
- [ ] Add GitHub secrets for code signing
- [ ] Trigger build via `git push`
- [ ] Install via your chosen method
- [ ] Set Claude API key in app settings
