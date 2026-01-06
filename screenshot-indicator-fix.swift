// Add this to your InterviewMasterDelegate class

// 1. ADD NEW PROPERTY (with other var declarations)
var captureIndicator: NSTextField!

// 2. IN setupUI(), add this indicator to the coding content view:
func setupUI() {
    // ... existing code ...

    // Screenshot capture indicator (shown during capture)
    captureIndicator = NSTextField(frame: NSRect(
        x: codingContentView.frame.width / 2 - 75,
        y: codingContentView.frame.height - 95,
        width: 150,
        height: 30
    ))
    captureIndicator.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
    captureIndicator.stringValue = "🔴 Capturing Screen"
    captureIndicator.isEditable = false
    captureIndicator.isBordered = false
    captureIndicator.drawsBackground = true
    captureIndicator.backgroundColor = NSColor.systemRed.withAlphaComponent(0.9)
    captureIndicator.textColor = .white
    captureIndicator.font = .systemFont(ofSize: 13, weight: .bold)
    captureIndicator.alignment = .center
    captureIndicator.isHidden = true  // Hidden by default
    captureIndicator.wantsLayer = true
    captureIndicator.layer?.cornerRadius = 8
    codingContentView.addSubview(captureIndicator)
}

// 3. UPDATE captureScreenshot() to show/hide indicator:
func captureScreenshot() async {
    // Check if we've reached the maximum
    if screenshots.count >= maxScreenshots {
        return
    }

    // ✅ SHOW INDICATOR BEFORE CAPTURE
    await MainActor.run {
        captureIndicator.isHidden = false

        // Add pulse animation for extra visibility
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            captureIndicator.layer?.transform = CATransform3DMakeScale(1.1, 1.1, 1.0)
        })
    }

    do {
        // Use ScreenCaptureKit
        let content = try await SCShareableContent.current

        guard let display = content.displays.first else {
            await MainActor.run {
                captureIndicator.isHidden = true  // ✅ Hide on error
                showAlert(title: "Error", message: "No display found")
            }
            return
        }

        // Configure capture
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.scalesToFit = false

        // Capture screenshot
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        // Convert to NSImage
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        // Generate thumbnail
        let thumbnailSize = NSSize(width: 62, height: 35)
        let thumbnail = generateThumbnail(from: nsImage, size: thumbnailSize)

        // Add to screenshots array
        let screenshotId = UUID()
        screenshots.append((id: screenshotId, image: nsImage))

        // Add thumbnail to UI
        await MainActor.run {
            addThumbnailToUI(thumbnail: thumbnail, id: screenshotId)
            updateScreenshotCounter()

            // ✅ HIDE INDICATOR AFTER SUCCESSFUL CAPTURE
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                captureIndicator.layer?.transform = CATransform3DIdentity
            }, completionHandler: {
                self.captureIndicator.isHidden = true
            })

            // Visual feedback (keep the beep)
            NSSound.beep()
        }

    } catch {
        // ✅ HIDE INDICATOR ON ERROR
        await MainActor.run {
            captureIndicator.isHidden = true
            showAlert(title: "Screenshot Failed", message: "Error: \(error.localizedDescription)")
        }
    }
}

// ALTERNATIVE: Simpler version without animation
func captureScreenshot_Simple() async {
    if screenshots.count >= maxScreenshots {
        return
    }

    // ✅ Show indicator
    await MainActor.run {
        captureIndicator.isHidden = false
    }

    do {
        // ... existing screenshot code ...

        // ✅ Hide indicator on success
        await MainActor.run {
            captureIndicator.isHidden = true
            NSSound.beep()
        }
    } catch {
        // ✅ Hide indicator on error
        await MainActor.run {
            captureIndicator.isHidden = true
            showAlert(title: "Screenshot Failed", message: "Error: \(error.localizedDescription)")
        }
    }
}
