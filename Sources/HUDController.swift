import Cocoa

/// Virsū peldošs kapsulas logs, kas rāda stāvokli un mikrofona līmeni.
final class HUDController {
    private let panel: NSPanel
    private let hudView = HUDView()

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 56),
                       styleMask: [.borderless, .nonactivatingPanel],
                       backing: .buffered,
                       defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.contentView = hudView
    }

    func show(text: String, showLevel: Bool) {
        hudView.text = text
        hudView.showLevel = showLevel
        hudView.level = 0
        positionOnScreen()
        panel.appearance = NSApp.appearance
        panel.orderFrontRegardless()
    }

    func updateLevel(_ level: Float) {
        hudView.level = CGFloat(level)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func positionOnScreen() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = hudView.intrinsicContentSize
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 40
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

final class HUDView: NSView {
    var text: String = "" {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    var showLevel: Bool = false {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    var level: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let width = max(180, textWidth + 56)
        let height: CGFloat = showLevel ? 64 : 48
        return NSSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds

        // Nosakām, vai šobrīd jāattēlo tumšajā vai gaišajā režīmā
        let isDark: Bool = {
            let app = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            return app == .darkAqua || app == nil
        }()

        // Fons — noapaļota kapsula ar pielāgotu krāsu un maigu apmali
        let bgRect = bounds.insetBy(dx: 6, dy: 6)
        let path = NSBezierPath(roundedRect: bgRect, xRadius: bgRect.height / 2, yRadius: bgRect.height / 2)

        if isDark {
            NSColor(calibratedWhite: 0.12, alpha: 0.92).setFill()
            path.fill()
            NSColor(calibratedWhite: 0.35, alpha: 0.35).setStroke()
            path.lineWidth = 1
            path.stroke()
        } else {
            NSColor(calibratedWhite: 0.98, alpha: 0.95).setFill()
            path.fill()
            NSColor(calibratedWhite: 0.70, alpha: 0.50).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        // Teksts
        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        let textColor = isDark ? NSColor.white : NSColor(calibratedWhite: 0.10, alpha: 1.0)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let textRect: NSRect
        if showLevel {
            textRect = NSRect(x: bounds.midX - textSize.width / 2,
                              y: bounds.midY - textSize.height / 2 + 9,
                              width: textSize.width,
                              height: textSize.height)
        } else {
            textRect = NSRect(x: bounds.midX - textSize.width / 2,
                              y: bounds.midY - textSize.height / 2,
                              width: textSize.width,
                              height: textSize.height)
        }
        (text as NSString).draw(in: textRect, withAttributes: attrs)

        // Līmeņa josla
        if showLevel {
            let barWidth: CGFloat = 120
            let barHeight: CGFloat = 5
            let barRect = NSRect(x: bounds.midX - barWidth / 2,
                                 y: 12,
                                 width: barWidth,
                                 height: barHeight)

            let trackColor = isDark
                ? NSColor(calibratedWhite: 1.0, alpha: 0.22)
                : NSColor(calibratedWhite: 0.0, alpha: 0.12)
            trackColor.setFill()
            NSBezierPath(roundedRect: barRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

            let fillWidth = barWidth * min(max(level, 0), 1)
            if fillWidth > 0 {
                let fillRect = NSRect(x: barRect.minX, y: barRect.minY, width: fillWidth, height: barHeight)
                let activeColor = isDark
                    ? NSColor(calibratedRed: 0.2, green: 0.85, blue: 0.42, alpha: 1.0)
                    : NSColor(calibratedRed: 0.12, green: 0.70, blue: 0.32, alpha: 1.0)
                activeColor.setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
            }
        }
    }
}
