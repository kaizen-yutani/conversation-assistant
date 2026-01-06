# Mac App Store Submission Guide
**Interview Master - Complete Checklist for App Store Approval**

---

## 🚨 Critical Requirements (Your App Needs Changes!)

### 1. **App Sandbox - MANDATORY** ⚠️
**Current Status:** ❌ NOT ENABLED
**Required:** ✅ MUST BE ENABLED

All Mac App Store apps MUST be sandboxed since June 2012.

**What needs to change:**
```xml
<!-- In InterviewMaster.entitlements - CHANGE THIS: -->
<key>com.apple.security.app-sandbox</key>
<false/>  <!-- ❌ Current (REJECTED by App Store) -->

<!-- TO THIS: -->
<key>com.apple.security.app-sandbox</key>
<true/>   <!-- ✅ Required for App Store -->
```

**Additional entitlements needed for your app:**
```xml
<!-- Screen capture (ScreenCaptureKit) -->
<key>com.apple.security.device.camera</key>
<true/>

<!-- Microphone for voice search -->
<key>com.apple.security.device.audio-input</key>
<true/>

<!-- Network for Anthropic/OpenAI API -->
<key>com.apple.security.network.client</key>
<true/>
```

### 2. **Recording Indicators - MANDATORY** ⚠️
**Current Status:** ❌ NOT IMPLEMENTED
**Required:** ✅ MUST SHOW VISIBLE INDICATOR

Your app uses screen recording and microphone. App Store requires:
- **Visible visual indicator** when recording/capturing screenshots
- Indicator cannot be disabled by user
- App cannot go blank during recording

**What to implement:**
- Add a red dot or "🔴 Recording" indicator in window when capturing
- Add "🎤 Listening" indicator when voice search is active (✅ already have this!)
- Ensure indicators are always visible and cannot be hidden

---

## 📋 Pre-Submission Checklist

### Technical Requirements

- [ ] **Xcode Version:** Build with Xcode 16 or later
- [ ] **macOS SDK:** Use latest macOS SDK (14.0+)
- [ ] **App Sandbox:** Enable `com.apple.security.app-sandbox = true`
- [ ] **Code Signing:** Sign with "Mac App Distribution" certificate (NOT Developer ID)
- [ ] **Installer:** Package as `.pkg` using `productbuild` (signed with "Mac Installer Distribution")
- [ ] **No Third-Party Installers:** Must be self-contained, single app installation bundle
- [ ] **No Auto-Launch:** Cannot auto-start at login without user consent
- [ ] **64-bit Only:** No 32-bit code
- [ ] **Hardened Runtime:** Enable with appropriate entitlements
- [ ] **No Private APIs:** Cannot use undocumented Apple APIs

### Privacy & Permissions

- [ ] **Info.plist Keys:** Include ALL usage description keys
  ```xml
  <key>NSCameraUsageDescription</key>
  <string>Interview Master uses screen capture to help you take screenshots of coding problems during technical interviews.</string>

  <key>NSMicrophoneUsageDescription</key>
  <string>Interview Master uses the microphone for voice search, allowing you to find interview notes hands-free.</string>

  <key>NSScreenCaptureDescription</key>
  <string>Interview Master captures screenshots of your screen to analyze coding problems with AI assistance during interviews.</string>
  ```

- [ ] **Privacy Manifest:** Create `PrivacyInfo.xcprivacy` file (new requirement 2024+)
- [ ] **App Privacy Details:** Complete in App Store Connect
  - Data collection practices
  - Third-party SDK data usage (Anthropic API, OpenAI API)
  - Privacy policy URL (required if collecting data)

- [ ] **Recording Indicators:** Show clear visual indicator when:
  - Screen capture is active (⚠️ MISSING - needs implementation)
  - Microphone is active (✅ already implemented)

### App Store Connect Metadata

#### Required Information

- [ ] **App Name:** "Interview Master" (or your chosen name, max 30 characters)
- [ ] **Bundle ID:** `com.nikolayprosenikov.interviewmaster`
- [ ] **Primary Category:** Productivity or Developer Tools
- [ ] **Age Rating:** Complete questionnaire (likely 4+)
- [ ] **Copyright:** © 2024 Nikolay Prosenikov

#### Description (4000 characters max)
```
Interview Master - Your Private AI Interview Assistant

Ace your technical interviews with a secure, screen-share-invisible note-taking app.

🔒 INVISIBLE TO SCREEN SHARING
Interview Master is hidden from Zoom, Teams, and all screen sharing apps. Your notes and AI assistance remain completely private during virtual interviews.

📝 TWO POWERFUL MODES

Interview Notes Tab:
• Quick-access interview prep notes and answers
• Markdown formatting with syntax highlighting
• Voice search - say "hashmap" to instantly find relevant notes
• Searchable knowledge base (⌘F)
• Beautiful glass UI that's easy to read

Coding Task Tab:
• Capture screenshots of coding problems (⌘S)
• AI-powered analysis with Claude Haiku 4.5
• Two analysis modes:
  - Problem Solving: Get approach, solution, complexity analysis
  - Code Review: Find bugs, security issues, get improvements
• Store up to 7 screenshots per session
• Streaming AI responses for fast feedback

⌨️ KEYBOARD SHORTCUTS
• ⌘L - Hide/Show window
• ⌘1/⌘2 - Switch tabs
• ⌘S - Screenshot (Coding tab)
• ⌘Enter - Analyze with AI
• ⌘F - Search notes
• ⌘V - Voice search

🎯 PERFECT FOR:
• Software engineering interviews
• Coding assessments
• Technical phone screens
• Live coding challenges
• System design discussions

🛡️ PRIVACY & SECURITY
• All data stored locally only
• API keys stored in memory (not on disk)
• No telemetry or tracking
• Screen share exclusion built-in

REQUIREMENTS:
• Anthropic API key for AI analysis
• OpenAI API key for voice search (optional)

Interview Master gives you the confidence of having your best answers at your fingertips, without compromising interview integrity.
```

#### Keywords (100 characters max)
```
interview,coding,notes,AI,assistant,developer,programming,technical,preparation,study
```

#### Support URL (required)
- Create a simple support page or GitHub repo

#### Marketing URL (optional)
- Your product website

#### Privacy Policy URL
- **Required if you collect/transmit data**
- Since you're using Anthropic/OpenAI APIs, you MUST have a privacy policy
- Must explain:
  - What data is sent to third parties (screenshots, voice recordings)
  - How API keys are stored
  - Data retention policies

### Screenshots (Required - macOS)

**Minimum:** 1 screenshot
**Maximum:** 5 screenshots
**Formats:** .jpeg, .jpg, .png
**Recommended Sizes:**
- 1280 x 800 pixels
- 1440 x 900 pixels
- 2560 x 1600 pixels (Retina)
- 2880 x 1800 pixels (Retina)

**Screenshot Ideas:**
1. Main window showing Interview Notes tab with markdown formatting
2. Coding tab with screenshot thumbnails and AI analysis
3. Voice search in action (show the indicator)
4. Settings/API key configuration
5. Search functionality demonstration

**Tips:**
- Show the app in use, not just empty screens
- Include text/content in screenshots
- Highlight unique features (invisible to screen sharing, AI analysis)
- Use macOS light mode for better visibility

### App Preview Video (Optional but Recommended)

**Resolution:** 1920 x 1080 pixels (16:9)
**Duration:** 15-30 seconds
**Format:** .mov, .m4v, .mp4
**Maximum:** 3 videos

**Video Ideas:**
- Quick demo of capturing screenshots and getting AI analysis
- Voice search in action
- Show invisibility to screen sharing (Zoom demo)

---

## 🚧 Code Changes Required for App Store

### 1. Update Entitlements for Sandbox

**File:** `InterviewMaster.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- ✅ ENABLE APP SANDBOX (REQUIRED!) -->
    <key>com.apple.security.app-sandbox</key>
    <true/>

    <!-- Screen capture permission -->
    <key>com.apple.security.device.camera</key>
    <true/>

    <!-- Microphone for voice search -->
    <key>com.apple.security.device.audio-input</key>
    <true/>

    <!-- Network access for API calls -->
    <key>com.apple.security.network.client</key>
    <true/>

    <!-- Hardened Runtime -->
    <key>com.apple.security.cs.allow-jit</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <false/>
    <key>com.apple.security.cs.disable-executable-page-protection</key>
    <false/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <false/>
</dict>
</plist>
```

### 2. Add Recording Indicator for Screenshots

**Add to `interview_master.swift`:**

```swift
// Add a recording indicator view
var recordingIndicator: NSTextField!

// In setupUI(), add this indicator:
recordingIndicator = NSTextField(frame: NSRect(x: codingContentView.frame.width - 120, y: codingContentView.frame.height - 30, width: 100, height: 20))
recordingIndicator.autoresizingMask = [.minXMargin, .minYMargin]
recordingIndicator.stringValue = "🔴 Capturing"
recordingIndicator.isEditable = false
recordingIndicator.isBordered = false
recordingIndicator.backgroundColor = .clear
recordingIndicator.textColor = .systemRed
recordingIndicator.font = .systemFont(ofSize: 11, weight: .semibold)
recordingIndicator.alignment = .center
recordingIndicator.isHidden = true
codingContentView.addSubview(recordingIndicator)

// In captureScreenshot(), show indicator:
func captureScreenshot() async {
    // Show recording indicator
    await MainActor.run {
        recordingIndicator.isHidden = false
    }

    // ... existing screenshot code ...

    // Hide indicator when done
    await MainActor.run {
        recordingIndicator.isHidden = true
    }
}
```

### 3. Create Privacy Manifest (New 2024 Requirement)

**File:** `PrivacyInfo.xcprivacy` (place in Resources folder)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>

    <key>NSPrivacyTrackingDomains</key>
    <array/>

    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeOtherData</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
    </array>

    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

### 4. Use Mac App Distribution Certificate

**For App Store submission, you need a DIFFERENT certificate:**

1. Go to https://developer.apple.com/account/resources/certificates/list
2. Create **"Mac App Distribution"** certificate (NOT Developer ID)
3. Create **"Mac Installer Distribution"** certificate

**Update build script to use App Store certificate:**
```bash
# For App Store builds, use:
DEVELOPER_ID="Mac App Distribution: Nikolay Prosenikov (2Q562K9C7N)"

# Package as .pkg (required for App Store):
productbuild --component build/InterviewMaster.app /Applications \
    --sign "Mac Installer Distribution: Nikolay Prosenikov (2Q562K9C7N)" \
    build/InterviewMaster.pkg
```

---

## 📤 Submission Process

### Step 1: Prepare Build

1. **Enable App Sandbox** in entitlements
2. **Add recording indicators** for screen capture
3. **Create privacy manifest**
4. **Build with Xcode** (use "Archive" → "Distribute App" → "App Store Connect")

### Step 2: Create App Store Connect Listing

1. Login to https://appstoreconnect.apple.com
2. Click **"My Apps"** → **"+"** → **"New App"**
3. Fill in:
   - Platform: macOS
   - Name: Interview Master
   - Primary Language: English
   - Bundle ID: Select `com.nikolayprosenikov.interviewmaster`
   - SKU: `interviewmaster-001` (unique identifier)
   - User Access: Full Access

### Step 3: Complete App Information

1. **App Privacy** (required)
   - Complete data collection questionnaire
   - Link privacy policy URL

2. **Pricing and Availability**
   - Free or Paid ($0.99 - $999.99)
   - Countries/regions

3. **App Information**
   - Category
   - Age rating
   - Copyright

4. **Version Information**
   - Screenshots (at least 1, max 5)
   - Description
   - Keywords
   - Support URL
   - Marketing URL (optional)
   - Version notes

### Step 4: Upload Build

**Using Xcode:**
1. Open project in Xcode
2. Product → Archive
3. Distribute App → App Store Connect
4. Upload
5. Wait for processing (10-30 minutes)

**Using Application Loader (alternative):**
1. Export `.pkg` from Xcode
2. Open Application Loader (Xcode → Open Developer Tool → Application Loader)
3. Upload `.pkg`

### Step 5: Submit for Review

1. In App Store Connect, select your build
2. Answer export compliance questions:
   - Does your app use encryption? **YES** (HTTPS for API calls)
   - Export compliance documentation: Upload if required
3. Click **"Submit for Review"**

### Step 6: Wait for Review

- **Typical timeline:** 1-3 days
- Check status in App Store Connect
- Respond quickly to any App Review questions

---

## 🚫 Common Rejection Reasons & How to Avoid

### 1. Missing App Sandbox
**Error:** "Your app does not meet the macOS App Sandbox requirements"
**Fix:** Set `com.apple.security.app-sandbox = true`

### 2. Missing Recording Indicator
**Error:** "Your app records video/audio without a clear visible indicator"
**Fix:** Add visible "🔴 Recording" indicator (see code changes above)

### 3. Incomplete Privacy Descriptions
**Error:** "Missing NSCameraUsageDescription in Info.plist"
**Fix:** Add ALL privacy usage description keys

### 4. Unnecessary Entitlements
**Error:** "Your app requests entitlements not necessary for app functionality"
**Fix:** Only request minimum required entitlements (camera, microphone, network)

### 5. Privacy Policy Missing
**Error:** "Apps that collect user data must have a privacy policy"
**Fix:** Create and link privacy policy (explain API usage)

### 6. Screen Recording Without Justification
**Error:** "Guideline 2.5.14 - Your app uses screen recording without clear justification"
**Fix:** Clearly explain in description why screen recording is essential for app functionality

### 7. Using Private APIs
**Error:** "Your app uses non-public APIs"
**Fix:** Ensure you're only using public ScreenCaptureKit APIs

---

## 📊 App Store Review Guidelines Compliance

### Guideline 2.5.14 - Recording
✅ **Your app:** Uses screen recording for core functionality (screenshot capture)
✅ **Required:** Clear visual indicator when recording (needs implementation)
✅ **Required:** Explicit user consent via system permission dialog (macOS handles this)

### Guideline 5.1.1 - Privacy
✅ **Your app:** Collects screenshots and voice data
✅ **Required:** Privacy policy explaining third-party API usage
✅ **Required:** Clear privacy usage descriptions
✅ **Required:** Privacy manifest file

### Guideline 2.4.5 - Software Requirements
✅ **Your app:** Uses ScreenCaptureKit (public API, macOS 12.3+)
✅ **Required:** Minimum OS version in Info.plist (LSMinimumSystemVersion = 12.3)
✅ **Required:** App Sandbox enabled

---

## 🔐 Certificates Needed

### For Direct Distribution (DMG - Current):
- ✅ **Developer ID Application** (you already have this)
- ✅ Notarization (completed via `notarize.sh`)

### For Mac App Store Submission (Additional):
- ⚠️ **Mac App Distribution** certificate (need to create)
- ⚠️ **Mac Installer Distribution** certificate (need to create)
- ⚠️ **Provisioning Profile** (created automatically in Xcode)

---

## 📝 Privacy Policy Template

You MUST create a privacy policy. Here's a simple template:

```markdown
# Privacy Policy for Interview Master

**Last Updated: [Date]**

## Data Collection

Interview Master collects the following data:

1. **Screenshots:** When you use the Coding Task feature, screenshots are captured and sent to Anthropic's Claude AI for analysis. Screenshots are not stored permanently and are only used for the duration of your analysis session.

2. **Voice Recordings:** When you use voice search, audio is recorded and sent to OpenAI's Whisper API for transcription. Audio is not stored permanently.

3. **API Keys:** Your Anthropic and OpenAI API keys are stored in memory only and never transmitted to our servers. We do not collect or store your API keys.

## Third-Party Services

- **Anthropic Claude AI:** Screenshots are sent to Anthropic for AI-powered code analysis. See Anthropic's privacy policy: https://www.anthropic.com/privacy
- **OpenAI Whisper:** Voice recordings are sent to OpenAI for transcription. See OpenAI's privacy policy: https://openai.com/privacy

## Data Storage

- All notes and data are stored locally on your device only
- No data is transmitted to our servers
- API keys are stored in memory and cleared when the app quits

## Data Retention

- Screenshots and voice recordings are deleted after analysis
- Your notes remain on your device until you delete them manually

## Contact

For privacy questions: n.prosenikov@gmail.com
```

Host this at: GitHub Pages, your website, or https://privacypolicygenerator.info

---

## ✅ Final Checklist Before Submission

- [ ] App Sandbox enabled (`com.apple.security.app-sandbox = true`)
- [ ] Recording indicators implemented for screenshot capture
- [ ] All Info.plist privacy keys added with clear descriptions
- [ ] Privacy manifest file (`PrivacyInfo.xcprivacy`) created
- [ ] Privacy policy created and URL added to App Store Connect
- [ ] Build with "Mac App Distribution" certificate
- [ ] Package as signed `.pkg` with "Mac Installer Distribution" certificate
- [ ] Upload build via Xcode or Application Loader
- [ ] Add at least 1 screenshot (recommended 3-5)
- [ ] Complete App Privacy questionnaire in App Store Connect
- [ ] Set pricing (free or paid)
- [ ] Export compliance: Answer encryption questions
- [ ] Submit for review

---

## 🆘 If You Get Rejected

1. **Read the rejection reason carefully** - Apple provides specific guideline violations
2. **Common fixes:**
   - Add missing entitlements/privacy keys
   - Implement recording indicators
   - Update privacy policy
   - Remove unnecessary entitlements
3. **Respond via Resolution Center** in App Store Connect
4. **Resubmit** after fixing issues

---

## 📞 Resources

- **App Store Connect:** https://appstoreconnect.apple.com
- **App Review Guidelines:** https://developer.apple.com/app-store/review/guidelines/
- **Sandboxing Guide:** https://developer.apple.com/documentation/security/app_sandbox
- **Privacy Manifest:** https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
- **Developer Support:** https://developer.apple.com/contact/

---

**Good luck with your submission! 🚀**

If you run into issues, refer to this checklist and the App Review Guidelines. Most rejections can be fixed by adding proper privacy descriptions and implementing recording indicators.
