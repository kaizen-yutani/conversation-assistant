# Interview Master - Support & Help

## Getting Help

If you need assistance with Interview Master, here are your options:

### 📧 Email Support
For general questions, bug reports, or feature requests:
- **Email:** n.prosenikov@gmail.com
- **Response time:** Usually within 1-2 business days

### 🐛 Bug Reports
If you encounter a bug, please include:
- macOS version (e.g., macOS 14.0 Sonoma)
- Interview Master version (found in Info.plist)
- Steps to reproduce the issue
- Screenshots if applicable

### 💡 Feature Requests
Have an idea to improve Interview Master? Send it to the email above with:
- Description of the feature
- Use case (how it would help you)
- Priority (nice-to-have vs. essential)

---

## Frequently Asked Questions

### Setup & Installation

**Q: What macOS version do I need?**
A: macOS 14.0 (Sonoma) or later. Interview Master requires modern ScreenCaptureKit APIs.

**Q: How do I get an Anthropic API key?**
A:
1. Visit [https://console.anthropic.com](https://console.anthropic.com)
2. Sign up or log in
3. Go to API Keys section
4. Create a new API key
5. Copy it into Interview Master settings (⚙️ API Key button)

**Q: Do I need an OpenAI API key?**
A: No, voice search feature has been removed. Only Anthropic API key is required.

**Q: The app asks for screen recording permission. Why?**
A: Interview Master needs this to capture screenshots (⌘S) of coding problems. This is required by macOS for any screen capture functionality.

### Using the App

**Q: How do I hide/show the window during interviews?**
A: Press ⌘L to toggle window visibility instantly.

**Q: Can interviewers see this app during screen sharing?**
A: The app attempts to be invisible during screen sharing. For maximum privacy, share a specific window (not entire screen) in Zoom/Teams.

**Q: How do I capture a screenshot?**
A:
1. Switch to Coding tab (⌘2)
2. Press ⌘S to capture a screenshot
3. Repeat up to 7 times per session
4. Press ⌘Enter to analyze all screenshots

**Q: What analysis modes are available?**
A:
- **Problem Solving (⌘M):** Get approach, solution, and complexity analysis
- **Code Review:** Find bugs, security issues, and improvements

**Q: How do I search my notes?**
A: Press ⌘F to open search, type your query, and see highlighted results.

**Q: How do I clear screenshots?**
A: Press ⌘G to clear all screenshots and analysis in the Coding tab.

### Troubleshooting

**Q: Screenshots are not capturing**
A:
1. Check System Settings → Privacy & Security → Screen Recording
2. Ensure Interview Master has permission
3. Restart the app if needed

**Q: AI analysis isn't working**
A:
1. Verify your Anthropic API key is entered correctly (⚙️ API Key)
2. Check your internet connection
3. Ensure you have API credits in your Anthropic account
4. Try capturing screenshots again

**Q: The app won't open**
A:
1. Check if you have macOS 12.3 or later
2. Try: `xattr -cr /path/to/InterviewMaster.app` to remove quarantine attributes
3. Verify code signature: `codesign --verify --verbose InterviewMaster.app`

**Q: How do I move the window?**
A: Use ⌘ + Arrow Keys to move the window around your screen.

**Q: Can I customize the keyboard shortcuts?**
A: Currently, keyboard shortcuts are fixed. Custom shortcuts may be added in future versions.

### Privacy & Security

**Q: Where is my data stored?**
A:
- Notes: Stored locally on your Mac only
- Screenshots: Temporarily in memory, sent to Anthropic API for analysis, then deleted
- API Keys: Stored in memory only (not saved to disk)

**Q: What data is sent to Anthropic?**
A: Only screenshots when you press "Analyze" (⌘Enter). Your notes are never sent.

**Q: Is my API key secure?**
A: Your API key is stored in memory only and cleared when you quit the app. It's never saved to disk.

**Q: Can I use this on multiple Macs?**
A: Yes, but you'll need to enter your API key on each Mac (it's not synced).

### Pricing & Licensing

**Q: Is Interview Master free?**
A: The app itself is free. You need your own Anthropic API key, which has usage-based pricing from Anthropic.

**Q: How much does Anthropic API cost?**
A: Claude Haiku 4.5 costs approximately $0.25 per million input tokens. A typical analysis might cost $0.01-0.05. Check [Anthropic Pricing](https://www.anthropic.com/pricing) for current rates.

---

## Keyboard Shortcuts Reference

| Shortcut | Action |
|----------|--------|
| ⌘L | Hide/Show window |
| ⌘1 | Switch to Notes tab |
| ⌘2 | Switch to Coding tab |
| ⌘F | Search notes |
| ⌘S | Capture screenshot (Coding tab) |
| ⌘Enter | Analyze screenshots (Coding tab) |
| ⌘M | Toggle analysis mode (Coding tab) |
| ⌘G | Clear all screenshots (Coding tab) |
| ⌘←→↑↓ | Move window |
| ESC | Close search |

---

## System Requirements

- **Operating System:** macOS 14.0 (Sonoma) or later
- **Architecture:** Apple Silicon (M1/M2/M3) or Intel
- **RAM:** 4GB minimum, 8GB recommended
- **Internet:** Required for AI analysis
- **Permissions:** Screen Recording access

---

## Uninstalling

To completely remove Interview Master:
1. Quit the app
2. Delete `/Applications/InterviewMaster.app` (or wherever you installed it)
3. All data is removed (nothing left behind in system files)

---

## Version History

### Version 1.0.0 (Current)
- Initial release
- Interview Notes tab with markdown support
- Coding Task tab with AI analysis
- Screenshot capture and analysis
- Claude Haiku 4.5 integration
- Text search functionality
- Keyboard shortcuts for quick access

---

## Credits

**Interview Master** is developed by Nikolay Prosenikov.

**Technologies Used:**
- Swift & SwiftUI
- ScreenCaptureKit (Apple)
- Claude AI (Anthropic)
- Markdown rendering

---

## Contact & Links

- **Email:** n.prosenikov@gmail.com
- **Privacy Policy:** [PRIVACY_POLICY.md](PRIVACY_POLICY.md)
- **App Store:** [Coming soon]

---

*Need more help? Email n.prosenikov@gmail.com - we're here to help you succeed in your interviews!*
