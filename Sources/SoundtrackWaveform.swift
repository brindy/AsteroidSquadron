import AppKit

final class SoundtrackWaveform: NSView {
    private let nameLabel = label("", size: 11, weight: .medium, color: color(0.81, 0.90, 0.92))
    private let removeButton = NSButton(title: "×", target: nil, action: nil)
    private let profileButton = NSButton(title: "", target: nil, action: nil)
    private var levels: [Float] = []
    private var waveformPath: CGPath?
    private var waveformPathRect = NSRect.zero

    var onRemove: (() -> Void)?
    var onCycleProfile: (() -> Void)?
    var progress: Double = 0 {
        didSet {
            let pixels = waveRect.width * (window?.backingScaleFactor ?? 1)
            if floor(position(oldValue) * pixels) != floor(position(progress) * pixels) {
                setNeedsDisplay(waveRect.insetBy(dx: -1, dy: -1))
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(nameLabel)

        style(removeButton)
        let symbol = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        if let symbol {
            removeButton.image = symbol.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
            removeButton.imagePosition = .imageOnly
        }
        removeButton.contentTintColor = color(0.72, 0.84, 0.88)
        removeButton.setAccessibilityLabel("Remove soundtrack")
        removeButton.toolTip = "Stop playback and remove the soundtrack"
        removeButton.target = self
        removeButton.action = #selector(removeTrack)
        addSubview(removeButton)

        style(profileButton)
        profileButton.setAccessibilityLabel("Cycle soundtrack profile")
        profileButton.setAccessibilityHelp("Cycles through Default, Calm, Intense and Trailer Cue")
        profileButton.target = self
        profileButton.action = #selector(cycleProfile)
        setProfile(title: "Default")
        addSubview(profileButton)
    }

    required init?(coder: NSCoder) { nil }

    private func style(_ button: NSButton) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = color(0.12, 0.20, 0.25, 0.68).cgColor
        button.layer?.borderColor = color(0.47, 0.70, 0.76, 0.30).cgColor
        button.layer?.borderWidth = 0.5
        button.layer?.cornerRadius = 5
    }

    func setProfile(title: String) {
        profileButton.attributedTitle = NSAttributedString(string: "\(title)  ↻", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: color(0.78, 0.91, 0.94)
        ])
        profileButton.setAccessibilityValue(title)
        profileButton.toolTip = "Click to cycle the soundtrack profile (currently \(title))"
    }

    func setTrack(name: String, waveform: [Float]) {
        nameLabel.stringValue = name
        nameLabel.toolTip = name
        levels = waveform
        waveformPath = nil
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let removeFrame = NSRect(x: bounds.width - 32, y: bounds.height - rowInset - 17, width: 23, height: 17)
        nameLabel.frame = NSRect(x: 12, y: removeFrame.minY + 1, width: max(0, removeFrame.minX - 20), height: 15)
        removeButton.frame = removeFrame
        profileButton.frame = profileFrame
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === removeButton || hit === profileButton ? hit : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let plate = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        color(0.025, 0.063, 0.083, 0.90).setFill()
        plate.fill()
        color(0.44, 0.73, 0.80, 0.26).setStroke()
        plate.lineWidth = 1
        plate.stroke()

        let rect = waveRect
        guard rect.width > 0, rect.height > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        if waveformPath == nil || waveformPathRect != rect {
            waveformPath = makeWaveformPath(in: rect)
            waveformPathRect = rect
        }
        guard let waveformPath else { return }
        context.setFillColor(color(0.35, 0.55, 0.62).cgColor)
        context.addPath(waveformPath)
        context.fillPath()

        let progressWidth = rect.width * position(progress)
        if progressWidth > 0 {
            context.saveGState()
            context.clip(to: CGRect(x: rect.minX, y: rect.minY, width: progressWidth, height: rect.height))
            context.setFillColor(cyan.cgColor)
            context.addPath(waveformPath)
            context.fillPath()
            context.restoreGState()

            if progressWidth < rect.width {
                context.setFillColor(color(0.84, 0.98, 1, 0.90).cgColor)
                context.fill(CGRect(x: rect.minX + progressWidth - 0.5, y: rect.minY, width: 1, height: rect.height))
            }
        }
    }

    private var rowInset: CGFloat { bounds.height < 48 ? 4 : 7 }

    private var profileFrame: NSRect {
        let height: CGFloat = bounds.height < 48 ? 17 : 20
        return NSRect(x: bounds.width - 91, y: rowInset, width: 82, height: height)
    }

    private var waveRect: NSRect {
        NSRect(x: 12, y: profileFrame.minY + 2, width: max(0, profileFrame.minX - 20), height: profileFrame.height - 4)
    }

    private func makeWaveformPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let count = max(1, min(192, Int(rect.width / 2)))
        let spacing = rect.width / CGFloat(count)
        let width = min(1.5, spacing * 0.65)
        for index in 0..<count {
            let first = index * levels.count / count
            let end = (index + 1) * levels.count / count
            let amplitude = levels.isEmpty ? 0 : levels[first..<max(first + 1, end)].max() ?? 0
            let height = max(1, rect.height * CGFloat(amplitude))
            let center = rect.minX + (CGFloat(index) + 0.5) * spacing
            path.addRoundedRect(in: CGRect(x: center - width / 2, y: rect.midY - height / 2, width: width, height: height),
                                cornerWidth: width / 2, cornerHeight: min(width, height) / 2)
        }
        return path
    }

    private func position(_ value: Double) -> CGFloat {
        value.isFinite ? CGFloat(min(1, max(0, value))) : 0
    }

    @objc private func removeTrack() { onRemove?() }
    @objc private func cycleProfile() { onCycleProfile?() }
}
