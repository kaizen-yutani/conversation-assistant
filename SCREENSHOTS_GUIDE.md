# Screenshot Guide for App Store Submission

## Requirements

**Minimum:** 1 screenshot
**Maximum:** 5 screenshots
**Recommended:** 3-5 screenshots

**Formats:** .jpeg, .jpg, .png

**Recommended Sizes:**
- 1280 x 800 pixels
- 1440 x 900 pixels
- 2560 x 1600 pixels (Retina - BEST)
- 2880 x 1800 pixels (Retina)

---

## Screenshot Ideas

### Screenshot 1: Main Window - Notes Tab ⭐ (MUST HAVE)
**What to show:**
- Interview Notes tab active (with ⌘1 visible)
- Sample interview prep content visible (questions & answers)
- Show markdown formatting (code blocks, bold, headings)
- Highlight keyboard shortcuts at top
- Show the glass/transparent visionOS-style UI

**Caption idea:** "Quick-access interview notes with markdown formatting and instant search"

---

### Screenshot 2: Coding Task Tab with Screenshots ⭐ (MUST HAVE)
**What to show:**
- Coding tab active (with ⌘2 visible)
- 3-4 screenshot thumbnails captured in the top bar
- AI analysis visible in the main area with formatted code
- Show "🧩 Problem Solving" mode selected
- Capture/Analyze buttons visible

**Caption idea:** "Capture coding problems and get instant AI-powered analysis"

---

### Screenshot 3: AI Analysis in Action ⭐ (RECOMMENDED)
**What to show:**
- Full analysis result from Claude
- Show well-formatted response with:
  - Code syntax highlighting
  - Bullet points
  - Clear approach/solution breakdown
  - Time/space complexity analysis
- Make it look professional and readable

**Caption idea:** "AI-powered code analysis with approach, solution, and complexity breakdown"

---

### Screenshot 4: Search Functionality (OPTIONAL)
**What to show:**
- Search bar open (⌘F) with a search term
- Highlighted results in notes
- Results counter showing matches
- Clean, focused view

**Caption idea:** "Instant search across all your interview notes"

---

### Screenshot 5: Settings/API Key (OPTIONAL)
**What to show:**
- Settings dialog open
- API key input field (with placeholder or masked key)
- Clean, simple interface
- Maybe show both Anthropic field

**Caption idea:** "Simple setup - just add your Anthropic API key"

---

## How to Take Screenshots

### Option 1: Use macOS Screenshot Tool
1. Open Interview Master
2. Set up the view you want to capture
3. Press ⌘⇧4 then Space
4. Click on the Interview Master window
5. Screenshot saved to Desktop

### Option 2: Use Built-in Tool (Best for exact sizing)
1. Open Screenshot.app (⌘⇧5)
2. Choose "Capture Selected Window"
3. Click Interview Master window
4. Edit/crop as needed

### Option 3: Full Screen (for Retina displays)
1. Make Interview Master full screen or large
2. Press ⌘⇧3 for full screen
3. Crop to just the app window in Preview

---

## Preparing Screenshots

### 1. Take at 2x Retina size (2560x1600 or larger)
```bash
# Check screenshot size
sips -g pixelWidth -g pixelHeight screenshot.png
```

### 2. Add realistic content
- Don't use "Lorem ipsum" or placeholder text
- Use real interview questions (JavaScript, React, System Design)
- Show actual code in the analysis
- Make it look production-ready

### 3. Clean up the UI
- Remove any test/debug content
- Hide personal information
- Ensure text is readable
- Check for typos

### 4. Optimize file size
```bash
# Optimize PNG (reduces file size)
pngquant screenshot.png --quality=85-95 --output screenshot-optimized.png

# Or use ImageOptim app (drag & drop)
```

### 5. Name files descriptively
```
screenshot-01-notes-tab.png
screenshot-02-coding-analysis.png
screenshot-03-ai-results.png
screenshot-04-search.png
screenshot-05-settings.png
```

---

## Screenshot Checklist

Before uploading, verify each screenshot:

- [ ] Resolution is at least 1280x800 (preferably 2560x1600)
- [ ] File format is PNG or JPEG
- [ ] File size is under 8MB
- [ ] Content is clear and readable
- [ ] No placeholder or test text
- [ ] No personal information visible
- [ ] UI looks polished (no debug info)
- [ ] Shows actual app functionality
- [ ] Highlights a unique feature
- [ ] Text is legible (not too small)

---

## Example Screenshot Setup

### Notes Tab Content (Copy/Paste Ready)

```markdown
# Common Interview Questions

## JavaScript/TypeScript

**Q: What is the difference between `let`, `const`, and `var`?**
A: `var` is function-scoped, `let` and `const` are block-scoped. `const` cannot be reassigned.

**Q: Explain closures**
A: Functions that have access to variables from outer scope even after outer function returns.

**Q: What is event delegation?**
A: Handling events at parent level using event bubbling instead of adding listeners to each child.

## System Design

**Q: Design a URL shortener**
- Hash function (MD5/Base62)
- Database: key-value store (Redis)
- Cache layer
- Load balancer
- Analytics tracking

## React

**Q: useEffect vs useLayoutEffect?**
A: useEffect runs after paint, useLayoutEffect runs synchronously before paint.

**Q: What are React keys?**
A: Unique identifiers to help React identify which items changed/added/removed in lists.

---

## Code Example: Two Sum

```python
def two_sum(nums, target):
    seen = {}
    for i, num in enumerate(nums):
        complement = target - num
        if complement in seen:
            return [seen[complement], i]
        seen[num] = i
    return []
```

Time: O(n), Space: O(n)
```

---

## Tips for Great Screenshots

1. **Use light mode** - Easier to see in App Store thumbnails
2. **Show actual content** - Not empty screens
3. **Highlight unique features** - What makes your app special?
4. **Tell a story** - Screenshots should flow from setup → use → results
5. **Keep UI consistent** - All screenshots should match visually

---

## Upload to App Store Connect

1. Go to App Store Connect
2. Select your app
3. Go to "App Store" tab
4. Scroll to "App Preview and Screenshots"
5. Click "+" to add screenshots
6. Drag & drop your PNG files
7. Arrange in desired order
8. Add captions (optional but recommended)

---

## Next Steps After Screenshots

Once screenshots are ready:
1. ✅ Privacy policy (done - PRIVACY_POLICY.md)
2. ✅ Support URL (done - SUPPORT.md)
3. 📸 Screenshots (in progress)
4. ✍️ App description
5. 🏷️ Keywords
6. 📧 Contact info

---

*Good screenshots can make or break your App Store presence. Take your time and make them look professional!*
