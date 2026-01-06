# Interview Master - Release Build Guide

Complete guide to build, sign, and notarize Interview Master for distribution.

## Prerequisites

### 1. Apple Developer Account
- Active Apple Developer Program membership ($99/year)
- Access to https://developer.apple.com/account

### 2. Developer ID Certificate

Get your **Developer ID Application** certificate:

1. Go to https://developer.apple.com/account/resources/certificates/list
2. Click **"+"** button
3. Select **"Developer ID Application"**
4. Follow prompts to create Certificate Signing Request (CSR):
   - Open **Keychain Access** > Certificate Assistant > Request Certificate from Certificate Authority
   - Enter your email and name
   - Select "Saved to disk"
5. Upload the CSR file
6. Download and double-click the certificate to install it

**Verify installation:**
```bash
security find-identity -v -p codesigning
```

You should see something like:
```
1) ABC123XYZ "Developer ID Application: Your Name (TEAM_ID)"
```

### 3. App-Specific Password

For notarization, you need an app-specific password (NOT your Apple ID password):

1. Go to https://appleid.apple.com
2. Sign in with your Apple ID
3. Go to **Security** section
4. Under **App-Specific Passwords**, click **"Generate password..."**
5. Enter label: `Notarization Tool`
6. **Copy the generated password** (you'll use it in step 3)

### 4. Get Your Team ID

Find your Team ID:
```bash
# Option 1: From certificate
security find-identity -v -p codesigning | grep "Developer ID"
# Team ID is in parentheses: (TEAM_ID)

# Option 2: From Apple Developer portal
# Go to https://developer.apple.com/account
# Click "Membership" - Team ID is shown there
```

## Configuration

Before building, update these files with your values:

### 1. build-release.sh
```bash
DEVELOPER_ID="Developer ID Application: YOUR NAME (TEAM_ID)"
BUNDLE_ID="com.yourcompany.interviewmaster"  # Make this unique
```

### 2. create-dmg.sh
```bash
DEVELOPER_ID="Developer ID Application: YOUR NAME (TEAM_ID)"
```

### 3. notarize.sh
```bash
BUNDLE_ID="com.yourcompany.interviewmaster"  # Must match build-release.sh
APPLE_ID="your-apple-id@example.com"
TEAM_ID="YOUR_TEAM_ID"
```

## Build Process

### Step 1: Build and Sign
```bash
chmod +x build-release.sh create-dmg.sh notarize.sh
./build-release.sh
```

This will:
- Compile the Swift binary with optimizations
- Create an app bundle structure
- Generate Info.plist with privacy descriptions
- Code sign with hardened runtime
- Apply entitlements

**Output:** `build/InterviewMaster.app`

### Step 2: Create DMG
```bash
./create-dmg.sh
```

This will:
- Package the app into a DMG
- Add Applications folder symlink (for drag-to-install)
- Sign the DMG

**Output:** `build/InterviewMaster-v1.0.0.dmg`

### Step 3: Notarize
```bash
./notarize.sh
```

**First time only:** You'll be prompted to store credentials:
- Enter your Apple ID email
- Paste the app-specific password you created
- Enter your Team ID

This will:
- Upload DMG to Apple's notary service (~5-10 minutes)
- Wait for Apple to scan and approve
- Staple the notarization ticket to the DMG
- Verify the stapled ticket

**Output:** Notarized `build/InterviewMaster-v1.0.0.dmg`

## Testing

### Test Locally
```bash
# Check signature
codesign --verify --verbose=4 build/InterviewMaster.app

# Check DMG signature
codesign --verify --verbose=4 build/InterviewMaster-v1.0.0.dmg

# Check stapling
xcrun stapler validate build/InterviewMaster-v1.0.0.dmg
```

### Test Gatekeeper
1. Copy DMG to Downloads folder (or another Mac)
2. Open the DMG
3. Drag app to Applications
4. Open the app - should launch without warnings!

## Troubleshooting

### "No identity found" error
- Make sure you installed the Developer ID Application certificate
- Run: `security find-identity -v -p codesigning`
- If no certificate found, repeat Prerequisites step 2

### "Invalid signature" error
- Check that DEVELOPER_ID matches exactly: `security find-identity -v -p codesigning`
- Include the full string: `Developer ID Application: Name (TEAM_ID)`

### Notarization rejected
Common issues:
- **Hardened runtime not enabled**: Already fixed in build-release.sh
- **Missing entitlements**: Check InterviewMaster.entitlements
- **Library validation issues**: Set `com.apple.security.cs.disable-library-validation` to false

Get detailed error log:
```bash
# Find your submission ID from notarize.sh output
xcrun notarytool log <SUBMISSION_ID> --keychain-profile notarytool-password
```

### "This app is damaged" error
- User downloaded the DMG via browser that added quarantine flag
- Run: `xattr -d com.apple.quarantine /path/to/InterviewMaster.app`
- Or re-download (sometimes browsers corrupt files)

### Notarization stuck at "In Progress"
- Apple's notary service can take 5-30 minutes during peak hours
- Check status: `xcrun notarytool history --keychain-profile notarytool-password`

## Distribution

Once notarized, you can distribute `build/InterviewMaster-v1.0.0.dmg`:

- ✅ Users can download and open without warnings
- ✅ No "unidentified developer" alerts
- ✅ Passes Gatekeeper security checks
- ✅ Safe to share via email, website, or file hosting

## Security Notes

**What's protected:**
- Code signature verifies app hasn't been tampered with
- Hardened runtime prevents code injection
- Notarization proves Apple scanned for malware
- Users see your developer name in security dialogs

**Privacy permissions:**
The app requests:
- Screen Recording (for screenshot capture)
- Microphone (for voice search)
- These appear as system prompts on first launch

## Version Updates

To release a new version:

1. Update version in `build-release.sh`:
   ```bash
   VERSION="1.0.1"
   ```

2. Update DMG name in `create-dmg.sh`:
   ```bash
   DMG_NAME="InterviewMaster-v1.0.1"
   ```

3. Rebuild:
   ```bash
   ./build-release.sh
   ./create-dmg.sh
   ./notarize.sh
   ```

## Costs

- **Apple Developer Program**: $99/year (required)
- **Notarization**: Free (unlimited submissions)
- **Code Signing**: Free (included with membership)

## Resources

- [Apple Code Signing Guide](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Notarization Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/customizing_the_notarization_workflow)
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)
- [Entitlements Reference](https://developer.apple.com/documentation/bundleresources/entitlements)

## Quick Reference

```bash
# One-command release:
./build-release.sh && ./create-dmg.sh && ./notarize.sh

# Check certificate:
security find-identity -v -p codesigning

# Check notarization history:
xcrun notarytool history --keychain-profile notarytool-password

# Get detailed log:
xcrun notarytool log <SUBMISSION_ID> --keychain-profile notarytool-password

# Verify everything:
codesign --verify --verbose=4 build/InterviewMaster.app
codesign --verify --verbose=4 build/InterviewMaster-v1.0.0.dmg
xcrun stapler validate build/InterviewMaster-v1.0.0.dmg
```
