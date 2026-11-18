import AppKit

// The canopy stays attached to the camera while the pilot and the view bank together.
final class CockpitOverlay: NSView {
    private var faction: Faction?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
        autoresizingMask = [.width, .height]
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setFaction(_ faction: Faction?) {
        guard faction != self.faction else { return }
        self.faction = faction
        isHidden = faction == nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let faction, bounds.width > 0, bounds.height > 0 else { return }
        let palette = Palette(faction)
        let unit = min(bounds.width, bounds.height)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        switch faction {
        case .empire: drawTIECanopy(palette)
        case .cylon, .shadow, .wraith: drawOrganicCanopy(faction, palette)
        case .goauld: drawGliderCanopy(palette)
        default: drawFramedCanopy(faction, palette)
        }

        drawConsole(faction, palette)
        drawSight(palette.accent, size: unit)
    }

    private struct Palette {
        let metal: NSColor
        let edge: NSColor
        let accent: NSColor

        init(_ faction: Faction) {
            switch faction {
            case .rebel:
                metal = shade(0.105, 0.111, 0.109)
                edge = shade(0.30, 0.32, 0.30)
                accent = shade(1, 0.57, 0.24)
            case .empire:
                metal = shade(0.048, 0.057, 0.063)
                edge = shade(0.23, 0.27, 0.28)
                accent = shade(0.46, 0.91, 0.57)
            case .colonial:
                metal = shade(0.075, 0.082, 0.085)
                edge = shade(0.27, 0.30, 0.31)
                accent = shade(0.94, 0.40, 0.29)
            case .earth:
                metal = shade(0.065, 0.071, 0.085)
                edge = shade(0.25, 0.30, 0.35)
                accent = shade(0.44, 0.77, 0.96)
            case .tauri:
                metal = shade(0.065, 0.073, 0.070)
                edge = shade(0.24, 0.29, 0.26)
                accent = shade(0.42, 0.94, 0.57)
            case .goauld:
                metal = shade(0.15, 0.105, 0.045)
                edge = shade(0.58, 0.43, 0.18)
                accent = shade(1, 0.73, 0.25)
            case .cylon:
                metal = shade(0.056, 0.055, 0.056)
                edge = shade(0.26, 0.25, 0.25)
                accent = shade(1, 0.20, 0.15)
            case .shadow:
                metal = shade(0.025, 0.020, 0.032)
                edge = shade(0.18, 0.13, 0.21)
                accent = shade(0.76, 0.35, 0.90)
            case .wraith:
                metal = shade(0.045, 0.065, 0.055)
                edge = shade(0.24, 0.34, 0.28)
                accent = shade(0.36, 0.90, 0.65)
            }
        }
    }

    private static func shade(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height)
    }

    private func polygon(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: point(first.0, first.1))
        for p in points.dropFirst() { path.line(to: point(p.0, p.1)) }
        path.close()
        return path
    }

    private func drawFrame(_ path: NSBezierPath, _ palette: Palette) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 7
        shadow.set()
        palette.metal.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let light = palette.edge.blended(withFraction: 0.52, of: palette.metal) ?? palette.edge
        NSGradient(starting: light, ending: palette.metal)?.draw(in: bounds, angle: -75)
        NSGraphicsContext.restoreGraphicsState()
        palette.edge.withAlphaComponent(0.82).setStroke()
        path.lineWidth = max(0.8, min(bounds.width, bounds.height) / 950)
        path.stroke()
    }

    private func drawFramedCanopy(_ faction: Faction, _ palette: Palette) {
        let shoulder: CGFloat = faction == .earth ? 0.22 : (faction == .tauri ? 0.14 : 0.18)
        let crown: CGFloat = faction == .colonial ? 0.36 : (faction == .earth ? 0.19 : 0.28)
        for mirrored in [false, true] {
            let coordinates: [(CGFloat, CGFloat)] = [
                (-0.04, -0.04), (0.045, -0.04), (shoulder, 0.40), (crown, 1.04),
                (crown - 0.023, 1.04), (shoulder - 0.034, 0.41)
            ]
            let hull = polygon(coordinates.map { (mirrored ? 1 - $0.0 : $0.0, $0.1) })
            drawFrame(hull, palette)
            let outer = polygon([(-0.03, 0.76), (0.022, 0.81), (0.105, 1.03), (-0.03, 1.03)]
                .map { (mirrored ? 1 - $0.0 : $0.0, $0.1) })
            drawFrame(outer, palette)
        }
        if faction == .earth {
            drawFrame(polygon([(0.15, 1.01), (0.85, 1.01), (0.81, 0.965), (0.19, 0.965)]), palette)
        }
        if faction == .tauri {
            let combiner = polygon([(0.40, 0.34), (0.60, 0.34), (0.59, 0.61), (0.41, 0.61)])
            palette.accent.withAlphaComponent(0.018).setFill()
            combiner.fill()
            palette.accent.withAlphaComponent(0.19).setStroke()
            combiner.lineWidth = 0.8
            combiner.stroke()
        }
    }

    private func drawTIECanopy(_ palette: Palette) {
        let outer = polygon([(-0.03, -0.03), (1.03, -0.03), (1.03, 1.03), (-0.03, 1.03)])
        let aperture = polygon([(0.19, 0.14), (0.04, 0.37), (0.04, 0.76), (0.24, 0.98),
                                (0.76, 0.98), (0.96, 0.76), (0.96, 0.37), (0.81, 0.14)])
        outer.append(aperture)
        outer.windingRule = .evenOdd
        drawFrame(outer, palette)
        for mirrored in [false, true] {
            for upper in [false, true] {
                let rail: [(CGFloat, CGFloat)] = upper
                    ? [(0.15, 1.03), (0.172, 1.03), (0.343, 0.763), (0.331, 0.752)]
                    : [(0.025, 0.12), (0.035, 0.10), (0.345, 0.349), (0.340, 0.367)]
                drawFrame(polygon(rail.map { (mirrored ? 1 - $0.0 : $0.0, $0.1) }), palette)
            }
        }
        let centerFrame = polygon([(0.332, 0.77), (0.668, 0.77), (0.712, 0.60), (0.712, 0.43),
                                   (0.668, 0.342), (0.332, 0.342), (0.288, 0.43), (0.288, 0.60)])
        centerFrame.append(polygon([(0.339, 0.761), (0.661, 0.761), (0.704, 0.60), (0.704, 0.433),
                                    (0.662, 0.351), (0.338, 0.351), (0.296, 0.433), (0.296, 0.60)]))
        centerFrame.windingRule = .evenOdd
        drawFrame(centerFrame, palette)
    }

    private func drawGliderCanopy(_ palette: Palette) {
        for mirrored in [false, true] {
            NSGraphicsContext.saveGraphicsState()
            if mirrored {
                NSGraphicsContext.current?.cgContext.translateBy(x: bounds.width, y: 0)
                NSGraphicsContext.current?.cgContext.scaleBy(x: -1, y: 1)
            }
            let arch = NSBezierPath()
            arch.move(to: point(-0.03, -0.03))
            arch.line(to: point(0.08, -0.03))
            arch.curve(to: point(0.26, 1.04), controlPoint1: point(0.12, 0.50), controlPoint2: point(0.10, 0.80))
            arch.line(to: point(0.22, 1.04))
            arch.curve(to: point(-0.03, 0.02), controlPoint1: point(0.055, 0.76), controlPoint2: point(0.08, 0.35))
            arch.close()
            drawFrame(arch, palette)
            let inset = NSBezierPath()
            inset.move(to: point(0.028, 0.11))
            inset.curve(to: point(0.245, 1.01), controlPoint1: point(0.115, 0.53), controlPoint2: point(0.075, 0.77))
            palette.accent.withAlphaComponent(0.23).setStroke()
            inset.lineWidth = 1.4
            inset.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawOrganicCanopy(_ faction: Faction, _ palette: Palette) {
        let ribs = faction == .shadow ? 5 : 3
        for mirrored in [false, true] {
            NSGraphicsContext.saveGraphicsState()
            if mirrored {
                NSGraphicsContext.current?.cgContext.translateBy(x: bounds.width, y: 0)
                NSGraphicsContext.current?.cgContext.scaleBy(x: -1, y: 1)
            }
            let skin = NSBezierPath()
            skin.move(to: point(-0.03, -0.03))
            skin.line(to: point(0.19, -0.03))
            skin.curve(to: point(0.07, 0.56), controlPoint1: point(0.15, 0.16), controlPoint2: point(0.015, 0.30))
            skin.curve(to: point(0.31, 1.04), controlPoint1: point(0.10, 0.84), controlPoint2: point(0.29, 0.89))
            skin.line(to: point(-0.03, 1.04))
            skin.close()
            drawFrame(skin, palette)
            skin.addClip()
            for index in 0..<ribs {
                let t = CGFloat(index) / CGFloat(ribs)
                let rib = NSBezierPath()
                rib.move(to: point(-0.015, 0.19 + t * 0.65))
                rib.curve(to: point(0.07 + t * 0.12, 0.14 + t * 0.72),
                          controlPoint1: point(0.08 + t * 0.04, 0.23 + t * 0.61),
                          controlPoint2: point(0.12 + t * 0.06, 0.14 + t * 0.66))
                palette.edge.withAlphaComponent(0.5).setStroke()
                rib.lineWidth = 2
                rib.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawConsole(_ faction: Faction, _ palette: Palette) {
        let height = min(bounds.height * 0.20, bounds.width * 0.22)
        let y = height / bounds.height
        let organic = faction == .cylon || faction == .shadow || faction == .wraith
        let console = NSBezierPath()
        console.move(to: point(-0.03, -0.03))
        console.line(to: point(1.03, -0.03))
        console.line(to: point(1.03, y * 0.9))
        if organic {
            console.curve(to: point(0.5, y * 0.73), controlPoint1: point(0.80, y * 1.35), controlPoint2: point(0.64, y * 0.48))
            console.curve(to: point(-0.03, y * 0.9), controlPoint1: point(0.36, y * 0.48), controlPoint2: point(0.20, y * 1.35))
        } else {
            console.line(to: point(0.79, y * 1.06))
            console.line(to: point(0.65, y * 0.75))
            console.line(to: point(0.35, y * 0.75))
            console.line(to: point(0.21, y * 1.06))
            console.line(to: point(-0.03, y * 0.9))
        }
        console.close()
        drawFrame(console, palette)

        for mirrored in [false, true] {
            let panelWidth = min(115, bounds.width * 0.14)
            let panelHeight = min(43, height * 0.42)
            let center = bounds.width * (mirrored ? 0.79 : 0.21)
            let panel = NSRect(x: center - panelWidth / 2, y: height * 0.32, width: panelWidth, height: panelHeight)
            drawInstrument(in: panel, palette: palette, organic: organic, mirrored: mirrored)
            if !organic {
                for index in 0..<3 {
                    let lamp = NSRect(x: panel.minX + CGFloat(index) * panel.width * 0.19,
                                      y: panel.minY - 9, width: max(2, panel.width * 0.07), height: 2)
                    palette.accent.withAlphaComponent(index == 1 ? 0.50 : 0.18).setFill()
                    lamp.fill()
                }
            }
        }

        if faction == .cylon {
            let slot = NSRect(x: bounds.midX - bounds.width * 0.11, y: height * 0.48,
                              width: bounds.width * 0.22, height: max(2, height * 0.022))
            palette.accent.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: slot, xRadius: 2, yRadius: 2).fill()
        }
    }

    private func drawInstrument(in rect: NSRect, palette: Palette, organic: Bool, mirrored: Bool) {
        NSColor.black.withAlphaComponent(0.72).setFill()
        let screen = NSBezierPath(roundedRect: rect, xRadius: organic ? rect.height * 0.4 : 3, yRadius: organic ? rect.height * 0.4 : 3)
        screen.fill()
        palette.edge.withAlphaComponent(0.6).setStroke()
        screen.lineWidth = 1
        screen.stroke()
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.height * 0.30
        let scope = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        palette.accent.withAlphaComponent(0.4).setStroke()
        scope.lineWidth = 0.7
        scope.stroke()
        let marks = NSBezierPath()
        marks.move(to: NSPoint(x: rect.minX + rect.width * 0.13, y: center.y))
        marks.line(to: NSPoint(x: rect.maxX - rect.width * 0.13, y: center.y))
        marks.move(to: NSPoint(x: center.x, y: rect.minY + rect.height * 0.16))
        marks.line(to: NSPoint(x: center.x, y: rect.maxY - rect.height * 0.16))
        palette.accent.withAlphaComponent(0.21).setStroke()
        marks.lineWidth = 0.6
        marks.stroke()
        if mirrored {
            let inner = NSBezierPath(ovalIn: NSRect(x: center.x - radius * 0.5, y: center.y - radius * 0.5, width: radius, height: radius))
            palette.accent.withAlphaComponent(0.5).setStroke()
            inner.stroke()
        }
    }

    private func drawSight(_ accent: NSColor, size: CGFloat) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = max(7, size * 0.014)
        let sight = NSBezierPath()
        sight.appendArc(withCenter: center, radius: radius, startAngle: 32, endAngle: 148)
        sight.move(to: NSPoint(x: center.x - radius * 1.6, y: center.y))
        sight.line(to: NSPoint(x: center.x - radius * 0.72, y: center.y))
        sight.move(to: NSPoint(x: center.x + radius * 0.72, y: center.y))
        sight.line(to: NSPoint(x: center.x + radius * 1.6, y: center.y))
        sight.move(to: NSPoint(x: center.x, y: center.y - radius * 1.5))
        sight.line(to: NSPoint(x: center.x, y: center.y - radius * 0.8))
        accent.withAlphaComponent(0.38).setStroke()
        sight.lineWidth = 0.8
        sight.stroke()
    }
}
