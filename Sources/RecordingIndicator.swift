import AppKit

// Owned by the app and updated on the main thread with the recorder state.
final class RecordingIndicator: NSObject {
    var onStop: (() -> Void)?

    private var item: NSStatusItem?
    private var timer: Timer?
    private var currentFrame: Int?
    private static let framesPerSecond = 16.0
    private static let frameCount = 24
    private lazy var stillImage = Self.makeImage(pulse: nil)
    private lazy var frames = (0..<Self.frameCount).map { index in
        Self.makeImage(pulse: CGFloat(index) / CGFloat(Self.frameCount))
    }

    func show() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "Asteroid Squadron is recording"
        item.button?.setAccessibilityLabel("Asteroid Squadron is recording")

        let menu = NSMenu()
        menu.addItem(withTitle: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "").target = self
        item.menu = menu

        let startTime = ProcessInfo.processInfo.systemUptime
        updateImage(elapsed: 0)
        let timer = Timer(timeInterval: 1 / Self.framesPerSecond, repeats: true) { [weak self] _ in
            self?.updateImage(elapsed: ProcessInfo.processInfo.systemUptime - startTime)
        }
        timer.tolerance = 0.015
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        currentFrame = nil
    }

    deinit { hide() }

    private func updateImage(elapsed: TimeInterval) {
        let frame = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? -1
            : Int(elapsed * Self.framesPerSecond) % Self.frameCount
        guard frame != currentFrame else { return }
        currentFrame = frame
        item?.button?.image = frame < 0 ? stillImage : frames[frame]
    }

    private static func makeImage(pulse: CGFloat?) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let red = NSColor(srgbRed: 1, green: 0.20, blue: 0.27, alpha: 1)
        let image = NSImage(size: size, flipped: false) { bounds in
            let dot = bounds.insetBy(dx: 5, dy: 5)
            red.setFill()
            NSBezierPath(ovalIn: dot).fill()

            let radius = pulse.map { 5 + 3 * $0 } ?? 6.75
            let opacity = pulse.map { 0.9 * (1 - $0) } ?? 0.85
            red.withAlphaComponent(opacity).setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: bounds.midX - radius, dy: bounds.midY - radius))
            ring.lineWidth = 1.2
            ring.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    @objc private func stopRecording() { onStop?() }
}
