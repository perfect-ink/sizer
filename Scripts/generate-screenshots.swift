// Renders the Mac App Store screenshots into docs/app-store/screenshots/en-US (or the directory
// given as the first argument) at 2880×1800, one of the sizes App Store Connect
// accepts for macOS. Run it with `make screenshots`.
//
// The Settings window is the app's real one: this file is compiled together with
// SettingsWindowController.swift, BindingStore.swift and SnapGeometry.swift (with
// -D APPSTORE, so it shows what the App Store build shows) and drawn off screen.
// Everything else (desktop, windows, menu, key caps) is drawn here.

import Cocoa
import Carbon.HIToolbox

// MARK: - Stubs for the bits of main.swift the Settings window talks to

/// Shadows the ApplicationServices call so the window renders in its "granted" state.
func AXIsProcessTrusted() -> Bool { true }

final class AppDelegate: NSObject {
    static var shared: AppDelegate? = AppDelegate()
    var isEnabled = true
    func syncLaunchAtLoginState() {}
    func setLaunchAtLogin(_ enabled: Bool) { BindingStore.shared.launchAtLogin = enabled }
    @objc func toggleEnabled(_ sender: Any?) { isEnabled.toggle() }
    func resetAndOpenAccessibilitySettings() {}
}

/// Same drawing as main.swift's menu bar icon.
func makeSizerIcon(dim: CGFloat = 18) -> NSImage {
    let img = NSImage(size: NSSize(width: dim, height: dim), flipped: false) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        let s = dim / 18
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 10 * s),
                                                    .foregroundColor: NSColor.black]
        let str = "S" as NSString
        let sz  = str.size(withAttributes: attrs)
        str.draw(at: CGPoint(x: (dim - sz.width) / 2, y: (dim - sz.height) / 2), withAttributes: attrs)
        func arrow(tip: CGPoint, l: CGPoint, r: CGPoint) {
            ctx.beginPath(); ctx.move(to: tip); ctx.addLine(to: l); ctx.addLine(to: r)
            ctx.closePath(); ctx.fillPath()
        }
        ctx.setFillColor(NSColor.black.cgColor)
        let m = dim / 2
        arrow(tip: CGPoint(x: m, y: dim - 1*s), l: CGPoint(x: m - 2.5*s, y: dim - 4.5*s), r: CGPoint(x: m + 2.5*s, y: dim - 4.5*s))
        arrow(tip: CGPoint(x: m, y: 1*s),       l: CGPoint(x: m - 2.5*s, y: 4.5*s),       r: CGPoint(x: m + 2.5*s, y: 4.5*s))
        arrow(tip: CGPoint(x: 1*s, y: m),       l: CGPoint(x: 4.5*s, y: m - 2.5*s),       r: CGPoint(x: 4.5*s, y: m + 2.5*s))
        arrow(tip: CGPoint(x: dim - 1*s, y: m), l: CGPoint(x: dim - 4.5*s, y: m - 2.5*s), r: CGPoint(x: dim - 4.5*s, y: m + 2.5*s))
        return true
    }
    img.isTemplate = true
    return img
}

// MARK: - Canvas (points; rendered at 2×)

let canvasSize = CGSize(width: 1440, height: 900)   // → 2880×1800 px

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let ink        = rgb(17, 20, 32)
let inkSoft    = rgb(17, 20, 32, 0.62)
let accent     = rgb(42, 100, 246)
let keyFace    = rgb(255, 255, 255)
let windowBody = rgb(246, 246, 248)
let windowBar  = rgb(232, 232, 236)
let lineColor  = rgb(206, 208, 216)

struct Canvas {
    let rep: NSBitmapImageRep

    init() {
        rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(canvasSize.width * 2), pixelsHigh: Int(canvasSize.height * 2),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = canvasSize
    }

    func draw(_ body: (CGContext) -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let gc = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = gc
        gc.cgContext.setAllowsAntialiasing(true)
        gc.cgContext.setShouldSmoothFonts(true)
        body(gc.cgContext)
        NSGraphicsContext.restoreGraphicsState()
    }

    func write(to url: URL) throws {
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}

// MARK: - Drawing helpers

func fill(_ rect: CGRect, radius: CGFloat, color: NSColor, shadow: Bool = false) {
    NSGraphicsContext.saveGraphicsState()
    if shadow {
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.28)
        sh.shadowBlurRadius = 28
        sh.shadowOffset = NSSize(width: 0, height: -12)
        sh.set()
    }
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()
}

func stroke(_ rect: CGRect, radius: CGFloat, color: NSColor, width: CGFloat = 1) {
    color.setStroke()
    let p = NSBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2), xRadius: radius, yRadius: radius)
    p.lineWidth = width
    p.stroke()
}

func text(_ s: String, at origin: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = ink, width: CGFloat? = nil, align: NSTextAlignment = .left, tracking: CGFloat = 0) {
    let para = NSMutableParagraphStyle()
    para.alignment = align
    para.lineBreakMode = .byWordWrapping
    para.lineHeightMultiple = 1.06
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .paragraphStyle: para, .kern: tracking,
    ]
    let str = NSAttributedString(string: s, attributes: attrs)
    if let width {
        let h = str.boundingRect(with: CGSize(width: width, height: 10_000),
                                 options: [.usesLineFragmentOrigin]).height
        str.draw(with: CGRect(x: origin.x, y: origin.y - h, width: width, height: h),
                 options: [.usesLineFragmentOrigin])
    } else {
        str.draw(at: origin)
    }
}

func textWidth(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
    (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width
}

/// Page background: warm paper with a soft blue bloom, so the light windows read against it.
func drawBackground(_ ctx: CGContext) {
    let g = NSGradient(colors: [rgb(238, 241, 252), rgb(222, 229, 250), rgb(236, 230, 247)])!
    g.draw(in: CGRect(origin: .zero, size: canvasSize), angle: -70)
    ctx.saveGState()
    let bloom = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [rgb(255, 255, 255, 0.9).cgColor, rgb(255, 255, 255, 0).cgColor] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: 1100, y: 820), startRadius: 0,
                           endCenter: CGPoint(x: 1100, y: 820), endRadius: 700, options: [])
    ctx.restoreGState()
}

func drawHeadline(_ title: String, _ subtitle: String, x: CGFloat = 96, y: CGFloat = 836,
                  width: CGFloat = 1250, titleSize: CGFloat = 52, align: NSTextAlignment = .left) {
    text(title, at: CGPoint(x: x, y: y), size: titleSize, weight: .bold, color: ink, width: width, align: align, tracking: -0.8)
    let titleH = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: titleSize, weight: .bold)])
        .boundingRect(with: CGSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin]).height
    text(subtitle, at: CGPoint(x: x, y: y - titleH - 10), size: 23, weight: .regular, color: inkSoft, width: width, align: align)
}

/// A keyboard shortcut as a row of key caps, e.g. ["⌃","⌥","⌘","←"].
func drawKeys(_ keys: [String], at origin: CGPoint, cap: CGFloat = 40, dark: Bool = false) {
    var x = origin.x
    for k in keys {
        let r = CGRect(x: x, y: origin.y, width: cap, height: cap)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.22)
        sh.shadowBlurRadius = 3
        sh.shadowOffset = NSSize(width: 0, height: -2)
        sh.set()
        (dark ? ink : keyFace).setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        NSGraphicsContext.restoreGraphicsState()
        stroke(r, radius: 8, color: dark ? rgb(0, 0, 0, 0.4) : rgb(0, 0, 0, 0.12))
        let fs = cap * 0.5
        let w = textWidth(k, size: fs, weight: .medium)
        let font = NSFont.systemFont(ofSize: fs, weight: .medium)
        let h = font.ascender - font.descender
        text(k, at: CGPoint(x: r.midX - w / 2, y: r.midY - h / 2), size: fs, weight: .medium, color: dark ? .white : ink)
        x += cap + 8
    }
}

func keysWidth(_ n: Int, cap: CGFloat = 40) -> CGFloat { CGFloat(n) * cap + CGFloat(n - 1) * 8 }

// MARK: - Desktop mock

struct Desktop {
    let frame: CGRect            // outer display, including menu bar
    var menuBarHeight: CGFloat { 28 * frame.width / 1140 }
    var area: CGRect { CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - menuBarHeight) }

    func draw(appName: String = "Finder") {
        // Wallpaper
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.30)
        sh.shadowBlurRadius = 40
        sh.shadowOffset = NSSize(width: 0, height: -16)
        sh.set()
        rgb(30, 42, 80).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 18, yRadius: 18).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: frame, xRadius: 18, yRadius: 18).addClip()
        NSGradient(colors: [rgb(52, 72, 140), rgb(120, 86, 170), rgb(232, 120, 110)])!
            .draw(in: frame, angle: -35)
        // Menu bar
        rgb(255, 255, 255, 0.72).setFill()
        CGRect(x: frame.minX, y: frame.maxY - menuBarHeight, width: frame.width, height: menuBarHeight).fill()
        let mbY = frame.maxY - menuBarHeight
        let s = menuBarHeight / 28
        text("", at: CGPoint(x: frame.minX + 18 * s, y: mbY + 5 * s), size: 15 * s, weight: .regular, color: ink)
        text(appName, at: CGPoint(x: frame.minX + 44 * s, y: mbY + 6 * s), size: 13 * s, weight: .bold, color: ink)
        var mx = frame.minX + 44 * s + textWidth(appName, size: 13 * s, weight: .bold) + 20 * s
        for item in ["File", "Edit", "View", "Go", "Window", "Help"] {
            text(item, at: CGPoint(x: mx, y: mbY + 6 * s), size: 13 * s, color: ink)
            mx += textWidth(item, size: 13 * s) + 18 * s
        }
        // Right side: Sizer icon, wifi-ish glyph, clock
        let clock = "Tue 18 Nov  9:41 AM"
        let cw = textWidth(clock, size: 13 * s, weight: .medium)
        text(clock, at: CGPoint(x: frame.maxX - 16 * s - cw, y: mbY + 6 * s), size: 13 * s, weight: .medium, color: ink)
        let icon = makeSizerIcon(dim: 18 * s)
        let tinted = NSImage(size: icon.size, flipped: false) { r in
            icon.draw(in: r); ink.set(); r.fill(using: .sourceAtop); return true
        }
        tinted.draw(in: CGRect(x: frame.maxX - 16 * s - cw - 36 * s, y: mbY + 5 * s, width: 18 * s, height: 18 * s))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The Sizer icon's x in the menu bar, for hanging a menu off it.
    var sizerIconMidX: CGFloat {
        let s = menuBarHeight / 28
        let cw = textWidth("Tue 18 Nov  9:41 AM", size: 13 * s, weight: .medium)
        return frame.maxX - 16 * s - cw - 36 * s + 9 * s
    }
}

/// A generic app window with traffic lights and placeholder content.
func drawWindow(_ r: CGRect, title: String, sidebar: Bool = false, tint: NSColor? = nil, highlight: Bool = false) {
    fill(r, radius: 10, color: windowBody, shadow: true)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).addClip()
    let barH: CGFloat = max(22, r.height * 0.075)
    windowBar.setFill()
    CGRect(x: r.minX, y: r.maxY - barH, width: r.width, height: barH).fill()
    for (i, c) in [rgb(255, 95, 87), rgb(255, 189, 46), rgb(40, 201, 64)].enumerated() {
        c.setFill()
        NSBezierPath(ovalIn: CGRect(x: r.minX + 10 + CGFloat(i) * 16, y: r.maxY - barH / 2 - 5, width: 10, height: 10)).fill()
    }
    let fs = min(13, barH * 0.5)
    let tw = textWidth(title, size: fs, weight: .semibold)
    text(title, at: CGPoint(x: r.midX - tw / 2, y: r.maxY - barH / 2 - fs * 0.62), size: fs, weight: .semibold, color: inkSoft)

    var contentX = r.minX
    if sidebar, r.width > 220 {
        let sw = min(150, r.width * 0.28)
        rgb(236, 236, 240).setFill()
        CGRect(x: r.minX, y: r.minY, width: sw, height: r.height - barH).fill()
        var y = r.maxY - barH - 24
        for i in 0..<7 where y > r.minY + 16 {
            (i == 1 ? accent.withAlphaComponent(0.18) : NSColor.clear).setFill()
            NSBezierPath(roundedRect: CGRect(x: r.minX + 10, y: y - 4, width: sw - 20, height: 18), xRadius: 5, yRadius: 5).fill()
            lineColor.setFill()
            NSBezierPath(roundedRect: CGRect(x: r.minX + 18, y: y + 1, width: sw * 0.55, height: 7), xRadius: 3, yRadius: 3).fill()
            y -= 26
        }
        contentX = r.minX + sw
    }
    // Content lines
    (tint ?? lineColor).setFill()
    var y = r.maxY - barH - 28
    var i = 0
    while y > r.minY + 18 {
        let w = (r.maxX - contentX - 40) * [0.82, 0.6, 0.72, 0.45][i % 4]
        NSBezierPath(roundedRect: CGRect(x: contentX + 20, y: y, width: w, height: 8), xRadius: 4, yRadius: 4).fill()
        y -= 24
        i += 1
    }
    NSGraphicsContext.restoreGraphicsState()
    if highlight { stroke(r, radius: 10, color: accent, width: 3) }
}

/// Window rect for a snap position inside a desktop area, with a small gutter so edges stay visible.
func snapRect(_ snap: WindowSnap, in a: CGRect, gutter g: CGFloat = 6) -> CGRect {
    let hw = a.width / 2, hh = a.height / 2
    switch snap {
    case .left:        return CGRect(x: a.minX, y: a.minY, width: hw, height: a.height).insetBy(dx: g, dy: g)
    case .right:       return CGRect(x: a.midX, y: a.minY, width: hw, height: a.height).insetBy(dx: g, dy: g)
    case .top:         return CGRect(x: a.minX, y: a.midY, width: a.width, height: hh).insetBy(dx: g, dy: g)
    case .bottom:      return CGRect(x: a.minX, y: a.minY, width: a.width, height: hh).insetBy(dx: g, dy: g)
    case .topLeft:     return CGRect(x: a.minX, y: a.midY, width: hw, height: hh).insetBy(dx: g, dy: g)
    case .topRight:    return CGRect(x: a.midX, y: a.midY, width: hw, height: hh).insetBy(dx: g, dy: g)
    case .bottomLeft:  return CGRect(x: a.minX, y: a.minY, width: hw, height: hh).insetBy(dx: g, dy: g)
    case .bottomRight: return CGRect(x: a.midX, y: a.minY, width: hw, height: hh).insetBy(dx: g, dy: g)
    case .maximize:    return a.insetBy(dx: g, dy: g)
    case .center:      return a.insetBy(dx: a.width * 0.125, dy: a.height * 0.125)
    case .center50:    return a.insetBy(dx: a.width * 0.25, dy: a.height * 0.25)
    }
}

// MARK: - Shortcut symbols

func keyName(_ keyCode: UInt32) -> String {
    switch Int(keyCode) {
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    case kVK_ANSI_Grave: return "`"
    case kVK_Space: return "Space"
    default:
        // Letters/digits via the current keyboard layout.
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var len = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            UCKeyTranslate(raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self), UInt16(keyCode),
                           UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           UInt32(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
        }
        return status == noErr ? String(utf16CodeUnits: chars, count: len).uppercased() : "?"
    }
}

func modifierSymbols(_ mods: UInt32) -> [String] {
    var out: [String] = []
    if mods & UInt32(controlKey) != 0 { out.append("⌃") }
    if mods & UInt32(optionKey)  != 0 { out.append("⌥") }
    if mods & UInt32(shiftKey)   != 0 { out.append("⇧") }
    if mods & UInt32(cmdKey)     != 0 { out.append("⌘") }
    return out
}

func keys(for id: UInt32) -> [String] {
    let store = BindingStore.shared
    return modifierSymbols(store.modifiers(for: id)) + [keyName(store.keyCode(for: id))]
}

// MARK: - The real Settings window, rendered off screen

func renderSettingsWindow(tab: String) -> NSImage {
    let ctrl = SettingsWindowController()
    let win = ctrl.window!
    win.appearance = NSAppearance(named: .aqua)
    if let tabs = win.contentView?.subviews.compactMap({ $0 as? NSTabView }).first {
        tabs.selectTabViewItem(withIdentifier: tab)
    }
    // The script has no bundle, so fill the version label from Info.plist.
    if let plist = NSDictionary(contentsOfFile: "Info.plist"),
       let version = plist["CFBundleShortVersionString"] as? String {
        func visit(_ v: NSView) {
            if let f = v as? NSTextField, f.stringValue == "v" { f.stringValue = "v\(version)" }
            v.subviews.forEach(visit)
        }
        visit(win.contentView!)
    }
    // Shown on screen but fully transparent: layer-backed controls (the tab bar) only
    // draw once the window is really on a display, and a key window gets coloured
    // traffic lights. Nothing is visible to the user at alpha 0.
    win.alphaValue = 0
    win.center()
    win.makeKeyAndOrderFront(nil)
    win.layoutIfNeeded()
    win.contentView?.layoutSubtreeIfNeeded()
    win.displayIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

    let frameView = win.contentView!.superview!      // theme frame: title bar + traffic lights included
    let b = frameView.bounds
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(b.width * 2), pixelsHigh: Int(b.height * 2),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = b.size
    frameView.cacheDisplay(in: b, to: rep)

    // Two things don't survive an off-screen capture of a non-key window: the
    // selected tab's label and the traffic-light colours. Paint both in place.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    for (button, color) in [(NSWindow.ButtonType.closeButton, rgb(255, 95, 87)),
                            (.miniaturizeButton, rgb(254, 188, 46)),
                            (.zoomButton, rgb(40, 200, 64))] {
        guard let btn = win.standardWindowButton(button) else { continue }
        let r = btn.convert(btn.bounds, to: frameView).insetBy(dx: 0.5, dy: 0.5)
        color.setFill()
        NSBezierPath(ovalIn: r).fill()
        stroke(r, radius: r.width / 2, color: rgb(0, 0, 0, 0.15))
    }
    func findSegmented(_ v: NSView) -> NSSegmentedControl? {
        if let s = v as? NSSegmentedControl, v.superview is NSTabView { return s }
        for sub in v.subviews { if let s = findSegmented(sub) { return s } }
        return nil
    }
    if let seg = findSegmented(win.contentView!), seg.segmentCount > 0, seg.selectedSegment >= 0,
       let label = seg.label(forSegment: seg.selectedSegment) {
        let r = seg.convert(seg.bounds, to: frameView)
        let segW = r.width / CGFloat(seg.segmentCount)
        let sr = CGRect(x: r.minX + segW * CGFloat(seg.selectedSegment), y: r.minY, width: segW, height: r.height)
        let font = seg.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let w = (label as NSString).size(withAttributes: [.font: font]).width
        let h = font.ascender - font.descender
        text(label, at: CGPoint(x: sr.midX - w / 2, y: sr.midY - h / 2 - 0.5), size: font.pointSize,
             weight: .regular, color: .labelColor)
    }
    NSGraphicsContext.restoreGraphicsState()
    win.orderOut(nil)
    let img = NSImage(size: b.size)
    img.addRepresentation(rep)
    return img
}

func drawImage(_ img: NSImage, centeredAt c: CGPoint, height: CGFloat, shadow: Bool = true) -> CGRect {
    let scale = height / img.size.height
    let r = CGRect(x: c.x - img.size.width * scale / 2, y: c.y - height / 2, width: img.size.width * scale, height: height)
    NSGraphicsContext.saveGraphicsState()
    if shadow {
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.30)
        sh.shadowBlurRadius = 44
        sh.shadowOffset = NSSize(width: 0, height: -18)
        sh.set()
        // Shadow follows the window's rounded shape rather than the transparent bitmap bounds.
        rgb(240, 240, 240).setFill()
        NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 11 * scale, yRadius: 11 * scale).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    return r
}

// MARK: - A caption pill next to a window

func drawLabelledKeys(_ label: String, _ keys: [String], centeredAt c: CGPoint) {
    let cap: CGFloat = 36
    let kw = keysWidth(keys.count, cap: cap)
    let lw = textWidth(label, size: 15, weight: .semibold)
    let pad: CGFloat = 14
    let w = pad + lw + 14 + kw + pad
    let h: CGFloat = 56
    let r = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    fill(r, radius: 14, color: rgb(255, 255, 255, 0.94), shadow: true)
    text(label, at: CGPoint(x: r.minX + pad, y: r.midY - 9), size: 15, weight: .semibold, color: ink)
    drawKeys(keys, at: CGPoint(x: r.minX + pad + lw + 14, y: r.midY - cap / 2), cap: cap)
}

// MARK: - Screens

typealias Screen = (file: String, draw: (CGContext) -> Void)

func screen1(_ ctx: CGContext) {
    drawBackground(ctx)
    drawHeadline("Snap any window into place with a keystroke.",
                 "Sizer lives in your menu bar and moves the front window the instant you press a shortcut. No dragging, no mouse.")
    let d = Desktop(frame: CGRect(x: 150, y: 48, width: 1140, height: 640))
    d.draw(appName: "Safari")
    let a = d.area
    drawWindow(snapRect(.left, in: a), title: "Research", sidebar: true)
    drawWindow(snapRect(.right, in: a), title: "Notes", highlight: true)
    drawLabelledKeys("Left Half", keys(for: 1), centeredAt: CGPoint(x: a.minX + a.width * 0.25, y: a.minY + 70))
    drawLabelledKeys("Right Half", keys(for: 2), centeredAt: CGPoint(x: a.minX + a.width * 0.75, y: a.minY + 70))
}

func screen2(_ ctx: CGContext) {
    drawBackground(ctx)
    drawHeadline("Halves, quarters, center, maximize.",
                 "Fifteen positions, each with its own shortcut. Windows land on the display they are already on, with the Dock and menu bar respected.")
    let d = Desktop(frame: CGRect(x: 150, y: 48, width: 1140, height: 640))
    d.draw(appName: "Mail")
    let a = d.area
    let quads: [(WindowSnap, String, UInt32)] = [(.topLeft, "Inbox", 5), (.topRight, "Calendar", 6),
                                                 (.bottomLeft, "Terminal", 8), (.bottomRight, "Messages", 7)]
    for (snap, title, id) in quads {
        let r = snapRect(snap, in: a)
        drawWindow(r, title: title, sidebar: snap == .topLeft, tint: snap == .bottomLeft ? rgb(60, 60, 70) : nil)
        drawLabelledKeys(BindingStore.shared.definitions.first { $0.id == id }!.label, keys(for: id),
                         centeredAt: CGPoint(x: r.midX, y: r.minY + 52))
    }
}

func screen3(_ ctx: CGContext) {
    drawBackground(ctx)
    drawHeadline("Tidy every window of an app at once.",
                 "Auto Arrange lays the front app's windows out in columns or two rows. Maximize All fills the screen with each of them.")
    let d = Desktop(frame: CGRect(x: 150, y: 48, width: 1140, height: 640))
    d.draw(appName: "Finder")
    let a = d.area
    let n = 3
    let cw = a.width / CGFloat(n)
    for i in 0..<n {
        let r = CGRect(x: a.minX + CGFloat(i) * cw, y: a.minY, width: cw, height: a.height).insetBy(dx: 6, dy: 6)
        drawWindow(r, title: ["Documents", "Downloads", "Projects"][i], sidebar: true)
    }
    drawLabelledKeys("Auto Arrange Columns", keys(for: 12), centeredAt: CGPoint(x: a.midX - 200, y: a.minY + 64))
    drawLabelledKeys("Auto Arrange 2 Rows", keys(for: 13), centeredAt: CGPoint(x: a.midX + 200, y: a.minY + 64))
}

func screen4(_ ctx: CGContext, settings: NSImage) {
    drawBackground(ctx)
    drawHeadline("Every shortcut is yours to change.",
                 "Click a shortcut, press the keys you want, done. Reset any of them to the defaults at any time.",
                 x: 96, y: 640, width: 560, titleSize: 54)
    let wr = drawImage(settings, centeredAt: CGPoint(x: 1010, y: 450), height: 720)
    // A few floating key caps to echo the recording state.
    drawKeys(["⌃", "⌥", "⌘", "M"], at: CGPoint(x: wr.minX - 250, y: 300), cap: 46)
    text("Maximize", at: CGPoint(x: wr.minX - 250, y: 262), size: 17, weight: .semibold, color: inkSoft)
    drawKeys(["⌃", "⌥", "⇧", "↑"], at: CGPoint(x: wr.minX - 250, y: 200), cap: 46)
    text("Top-Right Quarter", at: CGPoint(x: wr.minX - 250, y: 162), size: 17, weight: .semibold, color: inkSoft)
}

func screen5(_ ctx: CGContext, general: NSImage) {
    drawBackground(ctx)
    drawHeadline("Lives in your menu bar. Out of your Dock.",
                 "Every action is one click away from the menu bar icon, and Sizer can start with your Mac.")
    // Menu bar strip with the dropdown
    let d = Desktop(frame: CGRect(x: 96, y: -600, width: 760, height: 1310))
    d.draw(appName: "Finder")
    let menuW: CGFloat = 300
    let rowH: CGFloat = 26
    let groups: [[UInt32]] = [[1, 2, 3, 4], [5, 6, 7, 8], [9, 16, 10, 11], [12, 13], [14, 15]]
    let rows = 1 + 1 + groups.reduce(0) { $0 + $1.count } + 2   // title, Enabled, items, Settings…, Quit
    let seps = 1 + groups.count + 1
    let menuH = CGFloat(rows) * rowH + CGFloat(seps) * 11 + 12
    let menuX = min(d.sizerIconMidX - 20, d.frame.maxX - menuW - 12)
    let menuR = CGRect(x: menuX, y: d.frame.maxY - d.menuBarHeight - 4 - menuH, width: menuW, height: menuH)
    fill(menuR, radius: 10, color: rgb(246, 246, 248, 0.97), shadow: true)
    stroke(menuR, radius: 10, color: rgb(0, 0, 0, 0.12))

    var y = menuR.maxY - 6
    func row(_ title: String, keys: [String]? = nil, check: Bool = false, disabled: Bool = false, hover: Bool = false) {
        y -= rowH
        if hover {
            accent.setFill()
            NSBezierPath(roundedRect: CGRect(x: menuR.minX + 6, y: y, width: menuW - 12, height: rowH), xRadius: 5, yRadius: 5).fill()
        }
        let c: NSColor = hover ? .white : (disabled ? rgb(0, 0, 0, 0.35) : ink)
        if check { text("✓", at: CGPoint(x: menuR.minX + 12, y: y + 5), size: 13, weight: .semibold, color: c) }
        text(title, at: CGPoint(x: menuR.minX + 30, y: y + 5), size: 13, weight: disabled ? .semibold : .regular, color: c)
        if let keys {
            let s = keys.joined()
            let w = textWidth(s, size: 13)
            text(s, at: CGPoint(x: menuR.maxX - 14 - w, y: y + 5), size: 13, color: hover ? .white : rgb(0, 0, 0, 0.45))
        }
    }
    func sep() {
        y -= 11
        rgb(0, 0, 0, 0.1).setFill()
        CGRect(x: menuR.minX + 12, y: y + 5, width: menuW - 24, height: 1).fill()
    }
    row("Sizer", disabled: true)
    sep()
    row("Enabled", check: true)
    for g in groups {
        sep()
        for id in g {
            let def = BindingStore.shared.definitions.first { $0.id == id }!
            row(def.label, keys: keys(for: id), hover: id == 9)
        }
    }
    sep()
    row("Settings…", keys: ["⌘", ","])
    row("Quit Sizer", keys: ["⌘", "Q"])

    _ = drawImage(general, centeredAt: CGPoint(x: 1130, y: 380), height: 600)
}

func screen6(_ ctx: CGContext) {
    drawBackground(ctx)
    drawHeadline("Made for more than one display.",
                 "Send the front window to the next or previous display and it keeps its size. Every snap uses the visible area of the screen it is on.")
    let left  = Desktop(frame: CGRect(x: 96,  y: 120, width: 600, height: 380))
    let right = Desktop(frame: CGRect(x: 744, y: 120, width: 600, height: 380))
    left.draw(appName: "Xcode")
    right.draw(appName: "Xcode")
    let ghost = snapRect(.center, in: left.area)
    rgb(255, 255, 255, 0.35).setFill()
    NSBezierPath(roundedRect: ghost, xRadius: 10, yRadius: 10).fill()
    stroke(ghost, radius: 10, color: rgb(255, 255, 255, 0.8), width: 2)
    drawWindow(snapRect(.center, in: right.area), title: "Sizer.xcodeproj", sidebar: true, highlight: true)
    // Arrow between displays
    accent.setStroke()
    let p = NSBezierPath()
    p.lineWidth = 6
    p.lineCapStyle = .round
    p.move(to: CGPoint(x: ghost.maxX + 20, y: ghost.midY))
    p.line(to: CGPoint(x: right.area.minX + right.area.width * 0.22, y: ghost.midY))
    p.stroke()
    let tip = CGPoint(x: right.area.minX + right.area.width * 0.22 + 8, y: ghost.midY)
    let arrow = NSBezierPath()
    arrow.move(to: tip); arrow.line(to: CGPoint(x: tip.x - 22, y: tip.y + 14)); arrow.line(to: CGPoint(x: tip.x - 22, y: tip.y - 14)); arrow.close()
    accent.setFill(); arrow.fill()
    drawLabelledKeys("Next Display", keys(for: 14), centeredAt: CGPoint(x: 720, y: 60))
    drawLabelledKeys("Previous Display", keys(for: 15), centeredAt: CGPoint(x: 720, y: 600))
}

// MARK: - Main

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .aqua)

        // Fresh, predictable preferences for the rendered Settings window.
        let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        UserDefaults.standard.removePersistentDomain(forName: domain)
        BindingStore.shared.launchAtLogin = true
        BindingStore.shared.animationSpeed = .fast

        let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/app-store/screenshots/en-US")
        try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let shortcuts = renderSettingsWindow(tab: "shortcuts")
        let general   = renderSettingsWindow(tab: "general")

        let screens: [Screen] = [
            ("01-snap-halves.png",        screen1),
            ("02-quarters.png",           screen2),
            ("03-auto-arrange.png",       screen3),
            ("04-shortcuts.png",          { screen4($0, settings: shortcuts) }),
            ("05-menu-bar.png",           { screen5($0, general: general) }),
            ("06-displays.png",           screen6),
        ]
        for (file, draw) in screens {
            let c = Canvas()
            c.draw(draw)
            let url = outDir.appendingPathComponent(file)
            try! c.write(to: url)
            print("✓ \(url.path) (\(c.rep.pixelsWide)×\(c.rep.pixelsHigh))")
        }
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }
}
