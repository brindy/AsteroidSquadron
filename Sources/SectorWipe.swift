import AppKit

final class SectorWipeView: NSView {
    var coverage: CGFloat = 0 { didSet { if coverage != oldValue { needsDisplay = true } } }
    var opening = false { didSet { if opening != oldValue { needsDisplay = true } } }
    var style = 0 { didSet { if style != oldValue { needsDisplay = true } } }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard coverage>0 else { return }
        let dark = color(0.003,0.006,0.012)
        if coverage>=1 { dark.setFill(); NSBezierPath(rect:bounds).fill(); return }
        let t = coverage*coverage*(3-2*coverage)
        let w = bounds.width, h = bounds.height
        let path = NSBezierPath(), rim = NSBezierPath()
        if style.isMultiple(of:2) {
            let edge = -0.23+1.48*t
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x:(opening ? 1-x : x)*w,y:y*h)
            }
            rim.move(to:point(edge+0.09,-0.04))
            rim.curve(to:point(edge+0.07,0.33),controlPoint1:point(edge+0.14,0.10),controlPoint2:point(edge-0.06,0.28))
            rim.curve(to:point(edge-0.10,0.72),controlPoint1:point(edge+0.17,0.42),controlPoint2:point(edge-0.13,0.59))
            rim.curve(to:point(edge-0.16,1.04),controlPoint1:point(edge-0.07,0.86),controlPoint2:point(edge-0.22,0.95))
            path.append(rim)
            path.line(to:point(-0.30,1.04)); path.line(to:point(-0.30,-0.04)); path.close()
        } else {
            let radius = (1-t)*0.88
            let center = NSPoint(x:w*(opening ? 0.52 : 0.46),y:h*0.53)
            let oval = NSRect(x:center.x-w*radius,y:center.y-h*radius*1.22,width:w*radius*2,height:h*radius*2.44)
            rim.appendOval(in:oval)
            path.appendRect(bounds); path.append(rim)
            path.windingRule = .evenOdd
        }
        // Feather the edge without a full-frame flash or a hard black cut.
        for width: CGFloat in [28,14,5] {
            rim.lineWidth = width
            color(0.13,0.23,0.33,0.075*min(1,5*t,5*(1-t))).setStroke()
            rim.stroke()
        }
        dark.setFill(); path.fill()
    }
}
