# App Store Submission Guide

## Pre-Submission Checklist

### Code & Build Requirements

- [x] App Sandbox enabled (`com.apple.security.app-sandbox`)
- [x] Hardened Runtime enabled
- [x] Privacy Manifest (`PrivacyInfo.xcprivacy`) with required reason APIs
- [x] Correct Info.plist keys (NSScreenCaptureUsageDescription, LSApplicationCategoryType)
- [x] Standard macOS menu bar (File, Edit, View, Window, Help)
- [x] Privacy Policy accessible in app (Help menu + About dialog)
- [x] Data consent dialog before sending to third-party API
- [x] API keys stored in Keychain (not UserDefaults)
- [x] No unused dependencies or frameworks

### Build Commands

```bash
# Build release version
./build-release.sh

# Create DMG for distribution
./create-dmg.sh

# Notarize for distribution outside App Store
./notarize.sh
```

---

## App Store Connect Configuration

### App Information

| Field | Value |
|-------|-------|
| **App Name** | Interview Master |
| **Subtitle** | AI-Powered Interview Assistant |
| **Bundle ID** | com.nikolayprosenikov.interviewmaster |
| **SKU** | interviewmaster001 |
| **Category** | Developer Tools |
| **Secondary Category** | Productivity |
| **Content Rights** | Does not contain third-party content |

### Pricing

| Field | Value |
|-------|-------|
| **Price** | Free (or your chosen price) |
| **In-App Purchases** | None |

### Age Rating Questionnaire

| Question | Answer |
|----------|--------|
| Cartoon/Fantasy Violence | None |
| Realistic Violence | None |
| Sexual Content | None |
| Profanity | None |
| Drugs | None |
| Gambling | None |
| Horror/Fear | None |
| Mature/Suggestive | None |
| Medical/Treatment | None |
| Alcohol/Tobacco | None |
| Contests | None |
| Unrestricted Web Access | No |
| **Result** | 4+ |

---

## Privacy Section (App Store Connect)

### Data Collection Disclosure

#### Data Types Collected

| Data Type | Collected | Linked to User | Used for Tracking |
|-----------|-----------|----------------|-------------------|
| Photos or Videos | Yes | No | No |
| User Content | No | - | - |
| Identifiers | No | - | - |
| Usage Data | No | - | - |
| Diagnostics | No | - | - |

#### Purpose for Photos/Videos Collection

- **App Functionality**: Screenshots are sent to Anthropic's Claude AI for analysis

### Privacy Policy URL

```
https://github.com/nikolayprosenikov/interview-master/blob/main/PRIVACY.md
```

### Privacy Nutrition Label Summary

```
Data Used to Track You: None
Data Linked to You: None
Data Not Linked to You: Photos or Videos (for app functionality)
```

---

## Required Screenshots

### macOS Screenshots (Required Sizes)

| Size | Description |
|------|-------------|
| 1280 x 800 | Minimum size |
| 1440 x 900 | Recommended |
| 2560 x 1600 | Retina |
| 2880 x 1800 | Retina (15") |

### Suggested Screenshots

1. **Notes Tab** - Show markdown formatting with interview questions
2. **Coding Tab** - Show screenshot thumbnails and analysis area
3. **AI Analysis** - Show Claude analyzing a coding problem
4. **Settings** - Show API key configuration
5. **Privacy Features** - Show "hidden from screen sharing" hint

---

## App Description

### Short Description (Subtitle - 30 chars max)

```
AI-Powered Interview Assistant
```

### Full Description

```
Interview Master is your secret weapon for technical interviews. Capture coding problems with a single keystroke and get instant AI-powered analysis from Claude.

KEY FEATURES

• Screenshot Capture - Press ⌘S to capture coding problems instantly
• AI Analysis - Get solution approaches, code reviews, and explanations
• Privacy First - Window is hidden from screen sharing by default
• Markdown Notes - Keep interview prep notes with rich formatting
• Global Hotkeys - Works even when the app is in the background

HOW IT WORKS

1. During an interview, press ⌘S to capture the coding problem
2. Press ⌘Enter to analyze with Claude AI
3. Get instant solution approaches or code reviews
4. Use ⌘L to toggle visibility anytime

PRIVACY & SECURITY

• Your window is invisible to Zoom, Meet, and other screen sharing apps
• API keys are stored securely in macOS Keychain
• Screenshots are only sent when you explicitly request analysis
• No tracking, no analytics, no data collection

REQUIREMENTS

• macOS 14.0 (Sonoma) or later
• Anthropic API key (get one at console.anthropic.com)
• Screen Recording permission

Perfect for software engineers preparing for or taking technical interviews. Stay confident knowing your helper is invisible to interviewers.
```

### Keywords (100 chars max)

```
interview,coding,leetcode,ai,claude,programming,developer,technical,practice,assistant
```

### What's New (Version 1.0.0)

```
Initial release featuring:
• AI-powered screenshot analysis
• Privacy-focused floating window
• Markdown note-taking
• Global keyboard shortcuts
```

---

## Support Information

| Field | Value |
|-------|-------|
| **Support URL** | https://github.com/nikolayprosenikov/interview-master/issues |
| **Marketing URL** | https://github.com/nikolayprosenikov/interview-master |
| **Privacy Policy URL** | https://github.com/nikolayprosenikov/interview-master/blob/main/PRIVACY.md |

---

## Review Notes for Apple

Include these notes when submitting:

```
DEMO ACCOUNT / API KEY

This app requires an Anthropic API key to function. For review purposes:
1. Get a free API key at https://console.anthropic.com
2. Enter it in the app via the "API Key" button or ⌘,

SCREEN RECORDING PERMISSION

The app uses ScreenCaptureKit and requires Screen Recording permission.
This is used solely to capture screenshots of coding problems for AI analysis.

PRIVACY FEATURES

The app window is intentionally hidden from screen sharing (sharingType = .none)
to protect users during video interviews. This is a core privacy feature,
not an attempt to hide functionality.

DATA HANDLING

Screenshots are sent to Anthropic's Claude API only when the user explicitly
presses the Analyze button. A consent dialog is shown on first use.
No data is collected, stored, or tracked by the app itself.
```

---

## Compliance Checklist

### App Review Guidelines

| Guideline | Status | Notes |
|-----------|--------|-------|
| 2.4.5 macOS Apps | ✅ | Sandboxed, no auto-launch, Mac App Store updates only |
| 2.5.14 Recording | ✅ | Alert shown on screenshot capture |
| 5.1.1 Privacy Policy | ✅ | Link in app and App Store Connect |
| 5.1.2 Data Consent | ✅ | Explicit consent before API calls |

### Privacy Manifest Requirements

| API Category | Reason Code | Justification |
|--------------|-------------|---------------|
| UserDefaults | CA92.1 | App-only data storage for notes |

### Entitlements

| Entitlement | Value | Purpose |
|-------------|-------|---------|
| com.apple.security.app-sandbox | true | Required for App Store |
| com.apple.security.network.client | true | Anthropic API calls |
| com.apple.security.files.user-selected.read-write | true | Export notes feature |

---

## Post-Submission

### Expected Timeline

- **Review Start**: Within 24-48 hours
- **Review Duration**: 24-48 hours (average)
- **Total**: 2-5 business days

### Common Rejection Reasons to Avoid

1. ❌ Missing privacy policy
2. ❌ Unclear data collection practices
3. ❌ App crashes on launch
4. ❌ Placeholder content
5. ❌ Missing required permissions descriptions
6. ❌ Incomplete functionality without explanation

### If Rejected

1. Read the rejection reason carefully
2. Fix the specific issue mentioned
3. Reply in Resolution Center with explanation
4. Resubmit for review

---

## Files Modified for App Store Compliance

| File | Changes |
|------|---------|
| `build-release.sh` | Info.plist with correct keys, Security framework |
| `interview_master.swift` | Menu bar, Keychain, consent dialog, privacy links |
| `PrivacyInfo.xcprivacy` | UserDefaults declaration with CA92.1 |
| `InterviewMaster.entitlements` | Sandbox, network, file access |
| `MarkdownRenderer.swift` | Fixed formatting issues |
| `KeychainApiKeyStore.swift` | Custom service name support |
