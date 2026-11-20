import Foundation
import CoreGraphics

enum WindowSnap {
    case left, right, top, bottom                       // halves  (⌃⌥⌘+arrow)
    case topLeft, topRight, bottomLeft, bottomRight     // quarters (⌃⌥⇧+arrow)
    case maximize                                        // ⌃⌥⌘M
    case center                                          // ⌃⌥⌘C – 75% of visible frame
    case center50                                        // ⌃⌥X  – 50% of visible frame
}

/// AX origin (top-left corner, y downward) for a window of `size` placed at `snap`
/// inside `v` (NS visible frame, bottom-left origin).
///
/// Each snap position has a fixed anchor corner/edge that stays at the screen
/// boundary even when `size` is clamped by the window's minimum-size constraint.
func axOrigin(snap: WindowSnap, size s: CGSize, visibleFrame v: CGRect, primaryH: CGFloat) -> CGPoint {
    let topAX    = primaryH - v.maxY
    let bottomAX = primaryH - (v.minY + s.height)
    let rightX   = v.maxX - s.width

    switch snap {
    case .left:        return CGPoint(x: v.minX, y: topAX)
    case .right:       return CGPoint(x: rightX, y: topAX)
    case .top:         return CGPoint(x: v.minX, y: topAX)
    case .bottom:      return CGPoint(x: v.minX, y: bottomAX)
    case .topLeft:     return CGPoint(x: v.minX, y: topAX)
    case .topRight:    return CGPoint(x: rightX, y: topAX)
    case .bottomLeft:  return CGPoint(x: v.minX, y: bottomAX)
    case .bottomRight: return CGPoint(x: rightX, y: bottomAX)
    case .maximize:    return CGPoint(x: v.minX, y: topAX)
    case .center:
        return CGPoint(x: v.minX + (v.width - s.width) / 2,
                       y: primaryH - v.midY - s.height / 2)
    case .center50:
        return CGPoint(x: v.minX + (v.width - s.width) / 2,
                       y: primaryH - v.midY - s.height / 2)
    }
}

func desiredSize(for snap: WindowSnap, visibleFrame v: CGRect) -> CGSize {
    switch snap {
    case .left, .right:      return CGSize(width: v.width / 2, height: v.height)
    case .top, .bottom:      return CGSize(width: v.width,     height: v.height / 2)
    case .topLeft, .topRight,
         .bottomLeft, .bottomRight:
                              return CGSize(width: v.width / 2, height: v.height / 2)
    case .maximize:          return CGSize(width: v.width,     height: v.height)
    case .center:            return CGSize(width: v.width * 0.75, height: v.height * 0.75)
    case .center50:          return CGSize(width: v.width * 0.50, height: v.height * 0.50)
    }
}

/// The size a snap should end at: the current size if it already matches the
/// desired size (within 2pt), otherwise the desired size.
func snapEndSize(snap: WindowSnap, currentSize: CGSize, visibleFrame v: CGRect) -> CGSize {
    let desired = desiredSize(for: snap, visibleFrame: v)
    if abs(currentSize.width - desired.width) <= 2 && abs(currentSize.height - desired.height) <= 2 {
        return currentSize
    }
    return desired
}

/// AX resizes are anchored at the window's top-left corner. When the left or top
/// edge is doing most of the moving, reposition first and then resize toward the
/// stationary opposite edge. Right/bottom-edge resizes use the inverse order.
func shouldRepositionBeforeResizing(from start: CGRect, to end: CGRect) -> Bool {
    let edgeMovements = [
        (amount: abs(end.minX - start.minX), movesFromTopLeft: true),
        (amount: abs(end.maxX - start.maxX), movesFromTopLeft: false),
        (amount: abs(end.minY - start.minY), movesFromTopLeft: true),
        (amount: abs(end.maxY - start.maxY), movesFromTopLeft: false)
    ]

    return edgeMovements.max(by: { $0.amount < $1.amount })?.movesFromTopLeft ?? false
}

/// Finish a snap once the window has been sent to `endSize` at its target origin.
///
/// A resize applied before the window reaches its target origin can be clamped
/// because the window would run off the screen (e.g. Center → Left Half grows the
/// window downward while it is still centred). Now that the window sits at its
/// target origin, retry the size. If it still doesn't fit, the window has a minimum
/// (or maximum) size, so move it to keep the snap's anchor edge flush.
func settleSnapFrame(snap: WindowSnap, endSize: CGSize, visibleFrame v: CGRect, primaryH: CGFloat,
                     readSize: () -> CGSize,
                     setSize: (CGSize) -> Void,
                     setPosition: (CGPoint) -> Void) {
    var actual = readSize()
    guard actual != endSize else { return }
    setSize(endSize)
    actual = readSize()
    guard actual != endSize else { return }
    setPosition(axOrigin(snap: snap, size: actual, visibleFrame: v, primaryH: primaryH))
}
