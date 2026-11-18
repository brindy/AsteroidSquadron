import AppKit

final class FlightHelp: NSWindow {
    private struct Shortcut {
        let keys: String
        let title: String
        let detail: String?
        let spokenKeys: String

        init(_ keys: String, _ title: String, _ detail: String? = nil, spokenAs spokenKeys: String? = nil) {
            self.keys = keys
            self.title = title
            self.detail = detail
            self.spokenKeys = spokenKeys ?? keys
        }
    }

    private final class DocumentView: NSView {
        override var isFlipped: Bool { true }
    }

    private static let ink = NSColor(srgbRed: 0.90, green: 0.95, blue: 0.96, alpha: 1)
    private static let muted = NSColor(srgbRed: 0.65, green: 0.74, blue: 0.78, alpha: 1)
    private static let accent = NSColor(srgbRed: 0.48, green: 0.86, blue: 0.90, alpha: 1)
    private static let edge = NSColor(srgbRed: 0.20, green: 0.31, blue: 0.36, alpha: 1)

    static func present(attachedTo parent: NSWindow, completion: (() -> Void)? = nil) {
        guard parent.attachedSheet == nil else { return }
        let width = min(704, parent.frame.width - 24)
        let height = min(parent.frame.height, parent.screen?.visibleFrame.height ?? parent.frame.height) - 48
        let sheet = FlightHelp(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                               styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        sheet.title = "Flight Controls"
        sheet.titleVisibility = .hidden
        sheet.titlebarAppearsTransparent = true
        sheet.appearance = NSAppearance(named: .darkAqua)
        sheet.backgroundColor = NSColor(srgbRed: 0.045, green: 0.065, blue: 0.082, alpha: 1)
        sheet.isReleasedWhenClosed = false
        sheet.buildContents(width: width, maximumHeight: height)
        parent.beginSheet(sheet) { _ in completion?() }
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    @objc private func dismiss() { sheetParent?.endSheet(self, returnCode: .OK) }

    private func buildContents(width: CGFloat, maximumHeight: CGFloat) {
        let compact = width < 600
        let inset: CGFloat = compact ? 14 : 24
        let gap: CGFloat = 12
        let bodyWidth = width - 2 * inset
        let cardWidth = compact ? bodyWidth : (bodyWidth - gap) / 2

        let camera = card("Camera & Flight", width: cardWidth, entries: [
            Shortcut("C / N / →", "Next camera", spokenAs: "C, N, or Right Arrow"),
            Shortcut("A", "Automatic camera", "Follow the fight and cut to major events."),
            Shortcut("Space / P", "Pause or resume flight", spokenAs: "Space or P"),
            Shortcut("F", "Full screen", "Press Escape to leave full screen."),
            Shortcut("H / U", "Show or hide overlay", spokenAs: "H or U")
        ])
        let arena = card("Arena & Encounters", width: cardWidth, entries: [
            Shortcut("T", "Next sector", "Wipe to a new setting and keep the music playing."),
            Shortcut("R", "Restart the arena", "Generate a new arena, reset Ace records and restart the music."),
            Shortcut("B", "Change planet biome", "Generate a new world in a planet sector."),
            Shortcut("S", "Queue the Atlantis siege", "Start after the next eligible squadron victory.")
        ])
        let media = card("Soundtrack & Recording", width: cardWidth, entries: [
            Shortcut("⌘O", "Choose a soundtrack", "Automatic cameras cut to musical cues between major events.", spokenAs: "Command O"),
            Shortcut("M", "Cycle soundtrack profile", "You can also click the profile beside the waveform."),
            Shortcut("×", "Remove soundtrack", "Use the button beside the waveform to stop playback.", spokenAs: "Remove Soundtrack button"),
            Shortcut("V", "Record the window and soundtrack", "Press V again to stop and choose where to save the video.")
        ], footnote: "Choose MP3, WAV, M4A, FLAC or other formats macOS can play.")
        let display = card("Window & Display", width: cardWidth, entries: [
            Shortcut("K", "Keep computer and display awake"),
            Shortcut("J", "Switch between 30 and 60 fps"),
            Shortcut("⌘Q", "Quit and release keep awake", spokenAs: "Command Q")
        ], footnote: "Set a window resolution or fit an aspect ratio from the Window menu before recording. Drag the scene to move the window or double-click to fill or restore it. Automatic pause is in Flight → Pause When Unfocused.")

        let document = DocumentView(frame: .zero)
        let rows = compact ? [[camera], [arena], [media], [display]] : [[camera, arena], [media, display]]
        var y: CGFloat = 0
        for row in rows {
            let height = row.map(\.fittingSize.height).max() ?? 0
            for (column, card) in row.enumerated() {
                card.frame = NSRect(x: CGFloat(column) * (cardWidth + gap), y: y, width: cardWidth, height: height)
                document.addSubview(card)
            }
            y += height + gap
        }
        let bodyHeight = y - gap
        document.frame.size = NSSize(width: bodyWidth, height: bodyHeight)

        let headerHeight: CGFloat = 82
        let footerHeight: CGFloat = 62
        let totalHeight = min(maximumHeight, headerHeight + bodyHeight + footerHeight)
        setContentSize(NSSize(width: width, height: totalHeight))
        guard let content = contentView else { return }

        let scroll = NSScrollView(frame: NSRect(x: inset, y: footerHeight, width: bodyWidth,
                                                height: totalHeight - headerHeight - footerHeight))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = bodyHeight > scroll.frame.height
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.documentView = document
        content.addSubview(scroll)

        let appIcon = NSImageView(image: NSApp.applicationIconImage)
        appIcon.frame = NSRect(x: inset-4, y: totalHeight-65, width: 51, height: 51)
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.setAccessibilityElement(false)
        content.addSubview(appIcon)
        let title = text("Flight Controls", size: 25, weight: .semibold, color: Self.ink)
        title.frame.origin = NSPoint(x: inset+57, y: totalHeight-47)
        content.addSubview(title)
        let appName = text("Asteroid Squadron", size: 11, weight: .medium, color: Self.accent, mono: true)
        appName.frame.origin = NSPoint(x: title.frame.minX, y: totalHeight-63)
        content.addSubview(appName)

        let done = NSButton(title: "Back to the Dogfight", target: self, action: #selector(dismiss))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.sizeToFit()
        done.frame.origin = NSPoint(x: width-inset-done.frame.width, y: 16)
        content.addSubview(done)
        defaultButtonCell = done.cell as? NSButtonCell

        var accessibilityChildren: [Any] = [title, appName, scroll]
        if !compact {
            let footer = text("? opens Flight Controls", size: 11, color: Self.muted, mono: true)
            footer.frame.origin = NSPoint(x: inset, y: round(done.frame.midY-footer.frame.height/2))
            footer.setAccessibilityLabel("Question mark opens Flight Controls")
            content.addSubview(footer)
            accessibilityChildren.append(footer)
        }
        accessibilityChildren.append(done)
        content.setAccessibilityChildren(accessibilityChildren)
    }

    private func card(_ title: String, width: CGFloat, entries: [Shortcut], footnote: String? = nil) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(srgbRed: 0.079, green: 0.118, blue: 0.141, alpha: 1).cgColor
        view.layer?.borderColor = Self.edge.cgColor
        view.layer?.borderWidth = 1
        view.layer?.cornerRadius = 11

        let inset: CGFloat = 14
        let keyWidth: CGFloat = 68
        let columnWidth = width - 2 * inset
        let heading = text(title.uppercased(), size: 10, weight: .semibold, color: Self.accent, mono: true)
        heading.setAccessibilityLabel(title)
        let rule = NSBox()
        rule.boxType = .separator
        rule.widthAnchor.constraint(equalToConstant: columnWidth).isActive = true
        rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let cards = entries.map { entry in
            shortcut(entry, keyWidth: keyWidth, textWidth: columnWidth-keyWidth-10)
        }
        var items = [heading, rule] + cards
        if let footnote {
            items.append(paragraph(footnote, width: columnWidth))
        }

        let list = NSStackView(views: items)
        list.translatesAutoresizingMaskIntoConstraints = false
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 8
        view.addSubview(list)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            list.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            list.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            list.topAnchor.constraint(equalTo: view.topAnchor, constant: inset),
            list.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -inset)
        ])
        return view
    }

    private func shortcut(_ entry: Shortcut, keyWidth: CGFloat, textWidth: CGFloat) -> NSView {
        let key = text(entry.keys, size: 10, weight: .medium, color: Self.ink, mono: true)
        key.alignment = .center
        let keyHeight: CGFloat = 18
        // Keep the keycap background taller than the baseline without stretching the text field.
        let cap = NSView(frame: NSRect(x: 0, y: 0, width: keyWidth, height: keyHeight))
        cap.widthAnchor.constraint(equalToConstant: keyWidth).isActive = true
        cap.heightAnchor.constraint(equalToConstant: keyHeight).isActive = true
        cap.wantsLayer = true
        cap.layer?.backgroundColor = NSColor(srgbRed: 0.13, green: 0.19, blue: 0.23, alpha: 1).cgColor
        cap.layer?.borderColor = Self.edge.cgColor
        cap.layer?.borderWidth = 1
        cap.layer?.cornerRadius = 4
        key.frame = NSRect(x: 0, y: round((keyHeight-key.frame.height)/2), width: keyWidth, height: key.frame.height)
        cap.addSubview(key)

        let headline = paragraph(entry.title, width: textWidth)
        headline.font = .systemFont(ofSize: 12, weight: .medium)
        headline.textColor = Self.ink
        var lines: [NSView] = [headline]
        if let detail = entry.detail {
            lines.append(paragraph(detail, width: textWidth))
        }
        let action = NSStackView(views: lines)
        action.orientation = .vertical
        action.alignment = .leading
        action.spacing = 2

        let row = NSStackView(views: [cap, action])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.staticText)
        let description = [entry.title + ".", entry.detail, entry.spokenKeys].compactMap { $0 }.joined(separator: " ")
        row.setAccessibilityLabel(description)
        return row
    }

    private func paragraph(_ string: String, width: CGFloat) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: string)
        field.font = .systemFont(ofSize: 11)
        field.textColor = Self.muted
        field.preferredMaxLayoutWidth = width
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }

    private func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular,
                      color: NSColor, mono: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = mono ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.sizeToFit()
        return field
    }
}
