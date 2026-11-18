import AppKit

enum WindowPreset: Equatable {
    case resolution(width: Int, height: Int)
    case aspectRatio(width: Int, height: Int)

    static let resolutions: [Self] = [
        .resolution(width: 800, height: 600),
        .resolution(width: 1024, height: 768),
        .resolution(width: 1280, height: 720),
        .resolution(width: 1920, height: 1080),
        .resolution(width: 1080, height: 1080),
        .resolution(width: 1080, height: 1920)
    ]

    static let aspectRatios: [Self] = [
        .aspectRatio(width: 16, height: 9),
        .aspectRatio(width: 4, height: 3),
        .aspectRatio(width: 1, height: 1),
        .aspectRatio(width: 9, height: 16)
    ]

    var title: String {
        switch self {
        case let .resolution(width, height): return "\(width) × \(height)"
        case let .aspectRatio(width, height): return "\(width):\(height)"
        }
    }

    var captureSize: NSSize? {
        guard case let .resolution(width, height) = self else { return nil }
        return NSSize(width: width, height: height)
    }

    func frame(for window: NSWindow, in visibleFrame: NSRect) -> NSRect {
        // The scene uses the whole content view, including the transparent title bar.
        let viewSize = window.contentView?.bounds.size ?? window.contentRect(forFrameRect: window.frame).size
        let chromeWidth = max(0, window.frame.width - viewSize.width)
        let chromeHeight = max(0, window.frame.height - viewSize.height)
        let availableWidth = visibleFrame.width - chromeWidth
        let availableHeight = visibleFrame.height - chromeHeight

        let unitWidth: CGFloat, unitHeight: CGFloat, maximumScale: CGFloat
        switch self {
        case let .resolution(width, height):
            var divisor = width
            var remainder = height
            while remainder != 0 {
                (divisor, remainder) = (remainder, divisor % remainder)
            }
            unitWidth = CGFloat(width / divisor)
            unitHeight = CGFloat(height / divisor)
            maximumScale = CGFloat(divisor)
        case let .aspectRatio(width, height):
            unitWidth = CGFloat(width)
            unitHeight = CGFloat(height)
            maximumScale = .greatestFiniteMagnitude
        }

        // Whole units keep the exact aspect ratio after AppKit rounds window dimensions.
        let scale = floor(min(maximumScale, availableWidth / unitWidth, availableHeight / unitHeight))
        guard scale > 0 else { return window.frame }
        let frameWidth = unitWidth * scale + chromeWidth
        let frameHeight = unitHeight * scale + chromeHeight
        return NSRect(x: visibleFrame.minX + floor((visibleFrame.width - frameWidth) / 2),
                      y: visibleFrame.minY + floor((visibleFrame.height - frameHeight) / 2),
                      width: frameWidth,
                      height: frameHeight)
    }
}
