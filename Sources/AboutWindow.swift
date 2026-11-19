import AppKit

final class AboutWindow: NSWindow {
    private static var sharedWindow: AboutWindow?
    private static let ink = NSColor(srgbRed: 0.91, green: 0.96, blue: 0.96, alpha: 1)
    private static let muted = NSColor(srgbRed: 0.63, green: 0.73, blue: 0.77, alpha: 1)
    private static let accent = NSColor(srgbRed: 0.48, green: 0.85, blue: 0.89, alpha: 1)

    static func show() {
        let screen = NSApp.mainWindow?.screen ?? NSScreen.main
        let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let window: AboutWindow
        if let existing = sharedWindow {
            window = existing
        } else {
            window = AboutWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                                 backing: .buffered, defer: false)
            window.title = "About Asteroid Squadron"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(srgbRed: 0.035, green: 0.055, blue: 0.073, alpha: 1)
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenAuxiliary]
            sharedWindow = window
        }
        if !window.isVisible {
            window.buildContents(available: available)
            window.setFrameOrigin(NSPoint(x: available.midX - window.frame.width / 2,
                                          y: available.midY - window.frame.height / 2))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func cancelOperation(_ sender: Any?) { close() }

    private func buildContents(available: NSRect) {
        let compact = available.height < 620
        let width = min(480, max(280, available.width - 40))
        let inset: CGFloat = width < 380 ? 22 : 32
        let bodyWidth = width - 2 * inset
        let content = AboutBackdrop()
        contentView = content

        let iconSize: CGFloat = compact ? 76 : 108
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(false)
        content.addSubview(icon)

        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Asteroid Squadron"
        let title = text(name, width: bodyWidth, size: width < 380 ? 26 : 30, weight: .semibold, color: Self.ink)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let versionText = build.isEmpty || build == version ? "Version \(version)" : "Version \(version) (\(build))"
        let metadata = text(versionText, width: bodyWidth, size: 11, weight: .medium, color: Self.accent, mono: true)
        let description = text("An endless, procedural crossover starfighter dogfight.", width: bodyWidth,
                               size: 15, color: Self.ink)
        let purpose = text("Built for quiet company while your agents work.", width: bodyWidth,
                           size: 12, color: Self.muted)

        let attribution = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Unofficial fan project. Star Wars, Battlestar Galactica, Babylon 5 and Stargate belong to their respective owners."
        let ownership = text(attribution, width: bodyWidth - 28, size: 10.5, color: Self.muted)
        let credits = NSView()
        credits.wantsLayer = true
        credits.layer?.backgroundColor = NSColor(srgbRed: 0.065, green: 0.100, blue: 0.122, alpha: 1).cgColor
        credits.layer?.borderColor = NSColor(srgbRed: 0.18, green: 0.28, blue: 0.32, alpha: 1).cgColor
        credits.layer?.borderWidth = 0.5
        credits.layer?.cornerRadius = 10
        credits.addSubview(ownership)
        content.addSubview(credits)
        for field in [title, metadata, description, purpose] { content.addSubview(field) }

        let done = NSButton(title: "Back to the Dogfight", target: self, action: #selector(dismiss))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.sizeToFit()
        defaultButtonCell = done.cell as? NSButtonCell
        content.addSubview(done)

        var top: CGFloat = compact ? 24 : 34
        icon.frame = NSRect(x: (width - iconSize) / 2, y: top, width: iconSize, height: iconSize)
        top += iconSize + (compact ? 12 : 16)
        title.frame.origin = NSPoint(x: inset, y: top)
        top += title.frame.height + 4
        metadata.frame.origin = NSPoint(x: inset, y: top)
        top += metadata.frame.height + (compact ? 17 : 22)
        description.frame.origin = NSPoint(x: inset, y: top)
        top += description.frame.height + 8
        purpose.frame.origin = NSPoint(x: inset, y: top)
        top += purpose.frame.height + (compact ? 20 : 26)
        credits.frame = NSRect(x: inset, y: top, width: bodyWidth, height: ownership.frame.height + 26)
        ownership.frame.origin = NSPoint(x: 14, y: 13)
        top += credits.frame.height + 22
        done.frame.origin = NSPoint(x: (width - done.frame.width) / 2, y: top)
        top += done.frame.height + 22
        setContentSize(NSSize(width: width, height: top))
        content.frame = NSRect(x: 0, y: 0, width: width, height: top)
        content.setAccessibilityChildren([title, metadata, description, purpose, ownership, done])
    }

    private func text(_ string: String, width: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
                      color: NSColor, mono: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: string)
        field.font = mono ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.alignment = .center
        field.preferredMaxLayoutWidth = width
        field.maximumNumberOfLines = 0
        let height = field.attributedStringValue.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                                             options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        field.frame = NSRect(x: 0, y: 0, width: width, height: ceil(height) + 3)
        return field
    }

    @objc private func dismiss() { close() }
}

private final class AboutBackdrop: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let upper = NSColor(srgbRed: 0.060, green: 0.104, blue: 0.128, alpha: 1)
        let lower = NSColor(srgbRed: 0.027, green: 0.043, blue: 0.057, alpha: 1)
        NSGradient(starting: upper, ending: lower)?.draw(in: bounds, angle: -90)
    }
}
