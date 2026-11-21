import Foundation

/// A stand-in for an AX window. Like a real macOS window, it refuses to grow past the
/// bottom of the visible frame, and it can have a minimum size.
struct FakeWindow {
    var frame: CGRect                       // AX coordinates (top-left origin, y downward)
    var minSize = CGSize.zero
    let visibleFrame: CGRect
    let primaryH: CGFloat

    mutating func setPosition(_ p: CGPoint) { frame.origin = p }

    mutating func setSize(_ s: CGSize) {
        let maxHeight = (primaryH - visibleFrame.minY) - frame.minY   // down to the bottom edge
        frame.size = CGSize(width: max(s.width, minSize.width),
                            height: max(min(s.height, maxHeight), minSize.height))
    }
}

@main
struct SnapTests {
    /// Mirrors snapWindow's geometry without touching Accessibility.
    static func snap(_ w: CGRect, to snap: WindowSnap, visibleFrame v: CGRect, primaryH: CGFloat) -> CGRect {
        let size = snapEndSize(snap: snap, currentSize: w.size, visibleFrame: v)
        return CGRect(origin: axOrigin(snap: snap, size: size, visibleFrame: v, primaryH: primaryH), size: size)
    }

    /// Mirrors snapWindow + animateSnap against a FakeWindow: each frame applies size and
    /// position in setFrame's order, and the final frame (t == 1) runs settleSnapFrame.
    /// `frames` are animation progress values; [1] is the instant (no animation) path.
    static func snap(_ w: inout FakeWindow, to snap: WindowSnap, frames: [Double] = [1]) {
        let v = w.visibleFrame, ph = w.primaryH
        let start = w.frame
        let endSize = snapEndSize(snap: snap, currentSize: start.size, visibleFrame: v)
        let target = axOrigin(snap: snap, size: endSize, visibleFrame: v, primaryH: ph)
        let repositionFirst = shouldRepositionBeforeResizing(from: start, to: CGRect(origin: target, size: endSize))
        for t in frames {
            let size = CGSize(width:  start.width  + (endSize.width  - start.width)  * t,
                              height: start.height + (endSize.height - start.height) * t)
            let pos = CGPoint(x: start.minX + (target.x - start.minX) * t,
                              y: start.minY + (target.y - start.minY) * t)
            if repositionFirst { w.setPosition(pos); w.setSize(size) }
            else               { w.setSize(size);    w.setPosition(pos) }
            if t == 1 {
                settleSnapFrame(snap: snap, endSize: endSize, visibleFrame: v, primaryH: ph,
                                readSize: { w.frame.size },
                                setSize: { w.setSize($0) },
                                setPosition: { w.setPosition($0) })
            }
        }
    }

    static func easeInOut(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t }

    static func main() {
        let primaryH: CGFloat = 900
        let v = CGRect(x: 0, y: 0, width: 1440, height: 875)   // visible frame, menu bar excluded
        var window = CGRect(x: 100, y: 120, width: 500, height: 400)

        window = snap(window, to: .center, visibleFrame: v, primaryH: primaryH)
        window = snap(window, to: .maximize, visibleFrame: v, primaryH: primaryH)
        let afterFirst = window
        precondition(afterFirst.size == v.size, "Maximize should fill the visible frame")

        window = snap(window, to: .maximize, visibleFrame: v, primaryH: primaryH)
        precondition(window.size == afterFirst.size,
                     "Second Maximize changed size: \(afterFirst.size) -> \(window.size)")
        precondition(window.origin == afterFirst.origin,
                     "Second Maximize moved window: \(afterFirst.origin) -> \(window.origin)")

        // Center, then Left Half. Going from Center to Left Half resizes before it
        // moves the window (the right edge moves the most). The taller size doesn't fit
        // below the centred window, so the window clamps it, and it used to stay short
        // after moving to the top.
        var fake = FakeWindow(frame: CGRect(x: 100, y: 120, width: 500, height: 400),
                              visibleFrame: v, primaryH: primaryH)
        snap(&fake, to: .center)
        snap(&fake, to: .left)
        let leftHalf = CGRect(x: 0, y: primaryH - v.maxY, width: v.width / 2, height: v.height)
        precondition(fake.frame == leftHalf,
                     "Center → Left Half should fill the left half: expected \(leftHalf), got \(fake.frame)")

        // Center, then Right Half.
        fake = FakeWindow(frame: CGRect(x: 100, y: 120, width: 500, height: 400),
                          visibleFrame: v, primaryH: primaryH)
        snap(&fake, to: .center)
        snap(&fake, to: .right)
        let rightHalf = CGRect(x: v.width / 2, y: primaryH - v.maxY, width: v.width / 2, height: v.height)
        precondition(fake.frame == rightHalf,
                     "Center → Right Half should fill the right half: expected \(rightHalf), got \(fake.frame)")

        // Bottom-Left Quarter, then Center 50%.
        fake = FakeWindow(frame: CGRect(x: 100, y: 120, width: 500, height: 400),
                          visibleFrame: v, primaryH: primaryH)
        snap(&fake, to: .bottomLeft)
        snap(&fake, to: .center50)
        let center50 = CGRect(x: v.width / 4, y: primaryH - v.midY - v.height / 4,
                              width: v.width / 2, height: v.height / 2)
        precondition(fake.frame == center50,
                     "Bottom-Left Quarter → Center 50% should be centred at half size: expected \(center50), got \(fake.frame)")

        // Bottom-Left Quarter, then Maximize. Growing from the bottom edge resizes before
        // it moves the window up, so the taller height used to be clamped at the bottom.
        for frames in [[1], (1...12).map { easeInOut(Double($0) / 12) }] {
            fake = FakeWindow(frame: CGRect(x: 100, y: 120, width: 500, height: 400),
                              visibleFrame: v, primaryH: primaryH)
            snap(&fake, to: .bottomLeft, frames: frames)
            snap(&fake, to: .maximize, frames: frames)
            let maximized = CGRect(x: v.minX, y: primaryH - v.maxY, width: v.width, height: v.height)
            precondition(fake.frame == maximized,
                         "Bottom-Left Quarter → Maximize should fill the visible frame: expected \(maximized), got \(fake.frame)")
        }

        // Every snap followed by every other snap, from several starting frames, with no
        // animation, a full 12-frame animation, and a lagging animation that jumps to the
        // end after frame two. Whether the window can take its new height depends on where
        // it is when the resize lands, so every path must still end at the exact frame.
        let allSnaps: [WindowSnap] = [.left, .right, .top, .bottom, .topLeft, .topRight,
                                      .bottomLeft, .bottomRight, .maximize, .center, .center50]
        let starts = [CGRect(x: 100, y: 120, width: 500, height: 400),     // small, near the top
                      CGRect(x: 900, y: 600, width: 400, height: 250),     // small, near the bottom
                      CGRect(x: 0, y: 25, width: 1440, height: 875)]       // full screen
        let animated = (1...12).map { easeInOut(Double($0) / 12) }
        let modes: [(name: String, frames: [Double])] = [
            ("instant", [1]), ("animated", animated), ("lagging", [animated[0], animated[1], 1])]
        for mode in modes {
            for start in starts {
                for first in allSnaps {
                    for second in allSnaps {
                        var w = FakeWindow(frame: start, visibleFrame: v, primaryH: primaryH)
                        snap(&w, to: first, frames: mode.frames)
                        snap(&w, to: second, frames: mode.frames)
                        let size = desiredSize(for: second, visibleFrame: v)
                        let expected = CGRect(origin: axOrigin(snap: second, size: size, visibleFrame: v,
                                                               primaryH: primaryH), size: size)
                        precondition(w.frame == expected,
                                     "\(mode.name) from \(start): \(first) → \(second) should be \(expected), got \(w.frame)")
                    }
                }
            }
        }

        // A window with a minimum width larger than half the screen keeps its left edge flush.
        var wide = FakeWindow(frame: CGRect(x: 100, y: 120, width: 500, height: 400),
                              minSize: CGSize(width: 900, height: 0),
                              visibleFrame: v, primaryH: primaryH)
        snap(&wide, to: .center)
        snap(&wide, to: .right)
        precondition(wide.frame == CGRect(x: v.maxX - 900, y: primaryH - v.maxY, width: 900, height: v.height),
                     "Min-size clamped Right Half should stay flush right, got \(wide.frame)")

        print("✓ Snap tests passed")
    }
}
