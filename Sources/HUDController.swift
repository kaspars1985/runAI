import Cocoa
import QuartzCore

/// Virsū peldošs tumša stikla HUD logs ar neona viļņu animāciju.
/// Rāda ierakstīšanas, atšifrēšanas un pabeigšanas stāvokļus.
final class HUDController {
    var blurBackdropEnabled: Bool = true
    var positionPreference: HUDPosition = .center

    private let panel: NSPanel
    private let hudView = HUDView()
    private var backdropPanels: [NSPanel] = []

    // 60 FPS animācijas taimeris — darbojas tikai kamēr HUD ir redzams.
    private var animationTimer: Timer?
    private var phase: CGFloat = 0
    private var pulse: CGFloat = 0
    private var startTime: CFTimeInterval = 0

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: HUDView.containerWidth, height: HUDView.containerHeight),
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

    // MARK: - Publiskā saskarne

    /// Sāk ierakstīšanas stāvokli ar norādīto karsto taustiņu.
    func showRecording(hotkeyText: String) {
        hudView.mode = .recording
        hudView.statusText = "\(hotkeyText) turēts · Klausās balsi..."
        hudView.level = 0
        startTime = CACurrentMediaTime()
        present()
    }

    /// Pārslēdz uz atšifrēšanas stāvokli.
    func showTranscribing() {
        hudView.mode = .transcribing
        hudView.statusText = "⚡ Atlaid taustiņu · Atšifrē..."
        present()
    }

    /// Rāda veiksmes stāvokli (teksts ievietots vai nokopēts).
    func showSuccess(message: String) {
        hudView.mode = .success
        hudView.statusText = "✓ \(message)"
        present()
    }

    /// Rāda kļūdas stāvokli.
    func showError(_ error: String) {
        hudView.mode = .error
        hudView.statusText = error
        present()
    }

    /// Atjaunina mikrofona līmeni (0...1).
    func updateLevel(_ level: Float) {
        hudView.level = CGFloat(min(max(level, 0), 1))
    }

    /// Paslēpj HUD un aptur animāciju (0% CPU idle).
    func hide() {
        stopAnimation()
        hideBackdrop()
        panel.orderOut(nil)
    }

    // MARK: - Privātās metodes

    private func present() {
        showBackdrop()
        positionOnScreen()
        panel.appearance = NSApp.appearance
        panel.orderFrontRegardless()

        // Animējam tikai dinamiskiem stāvokļiem; statiskie (.success, .error)
        // netērē CPU uz 60 FPS taimeri.
        if hudView.mode == .recording || hudView.mode == .transcribing {
            startAnimation()
        } else {
            stopAnimation()
            hudView.needsDisplay = true
        }
    }

    private func showBackdrop() {
        guard blurBackdropEnabled else { return }
        guard backdropPanels.isEmpty else { return }

        for screen in NSScreen.screens {
            let bPanel = NSPanel(contentRect: screen.frame,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
            bPanel.isOpaque = false
            bPanel.backgroundColor = .clear
            bPanel.hasShadow = false
            bPanel.level = .statusBar - 1
            bPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            bPanel.ignoresMouseEvents = true
            bPanel.isMovable = false
            bPanel.hidesOnDeactivate = false

            let visualEffect = NSVisualEffectView(frame: bPanel.contentView!.bounds)
            visualEffect.autoresizingMask = [.width, .height]
            visualEffect.material = .fullScreenUI
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active

            let overlay = NSView(frame: visualEffect.bounds)
            overlay.autoresizingMask = [.width, .height]
            overlay.wantsLayer = true
            overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.20).cgColor
            visualEffect.addSubview(overlay)

            bPanel.contentView = visualEffect
            bPanel.alphaValue = 0.0
            bPanel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                bPanel.animator().alphaValue = 0.85
            }
            backdropPanels.append(bPanel)
        }
    }

    private func hideBackdrop() {
        let panels = backdropPanels
        backdropPanels = []
        guard !panels.isEmpty else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.20
            for p in panels {
                p.animator().alphaValue = 0.0
            }
        }, completionHandler: {
            for p in panels {
                p.orderOut(nil)
            }
        })
    }

    private func startAnimation() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func tick() {
        // Fāzes animācija viļņiem
        phase += 0.09
        if phase > .pi * 2 { phase -= .pi * 2 }

        // Pulsācija atšifrēšanas laikā
        pulse += 0.06
        if pulse > .pi * 2 { pulse -= .pi * 2 }

        // Ierakstīšanas hronometrs
        if hudView.mode == .recording {
            let elapsed = CACurrentMediaTime() - startTime
            hudView.elapsed = elapsed
        }

        hudView.phase = phase
        hudView.pulse = pulse
        hudView.needsDisplay = true
    }

    private func positionOnScreen() {
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) ?? NSScreen.main
        guard let s = screen else { return }
        let visible = s.visibleFrame
        let size = NSSize(width: HUDView.containerWidth, height: HUDView.containerHeight)
        let x = visible.midX - size.width / 2
        let y: CGFloat
        switch positionPreference {
        case .center:
            y = visible.midY - size.height / 2
        case .top:
            y = visible.maxY - size.height - 30
        }
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

// MARK: - HUDView

final class HUDView: NSView {

    enum Mode {
        case recording
        case transcribing
        case success
        case error
    }

    static let containerWidth: CGFloat = 360
    static let containerHeight: CGFloat = 88

    // Kešotās gradienta krāsas — izvairāmies no atkārtotas NSColor/CGGradient izveides katrā kadrā.
    private static let waveGradientColors: [CGColor] = [
        NSColor(red: 34/255, green: 211/255, blue: 238/255, alpha: 1.0).cgColor,
        NSColor(red: 168/255, green: 85/255, blue: 247/255, alpha: 1.0).cgColor,
        NSColor(red: 236/255, green: 72/255, blue: 153/255, alpha: 1.0).cgColor
    ]
    private static let waveCGGradient: CGGradient? = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: waveGradientColors as CFArray,
        locations: [0.0, 0.5, 1.0]
    )
    private static let waveNSGradient: NSGradient? = NSGradient(colors: [
        NSColor(red: 34/255, green: 211/255, blue: 238/255, alpha: 1.0),
        NSColor(red: 168/255, green: 85/255, blue: 247/255, alpha: 1.0),
        NSColor(red: 236/255, green: 72/255, blue: 153/255, alpha: 1.0)
    ])

    var mode: Mode = .recording {
        didSet { needsDisplay = true }
    }
    var statusText: String = "" {
        didSet { needsDisplay = true }
    }
    var level: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var phase: CGFloat = 0
    var pulse: CGFloat = 0
    var elapsed: CFTimeInterval = 0

    override var isFlipped: Bool { false }

    // MARK: - Zīmēšana

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds

        // Fons — tumšs luksusa stikls
        let bgRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 18, yRadius: 18)
        NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 0.94).setFill()
        bgPath.fill()

        // 1px apmale
        NSColor(white: 1.0, alpha: 0.12).setStroke()
        bgPath.lineWidth = 1
        bgPath.stroke()

        // Augšējā rinda (statuss + labā puse)
        drawHeaderRow(in: bounds)

        // Apakšējā rinda (vilnis)
        drawWaveform(in: bounds)
    }

    // MARK: - Augšējā rinda

    private func drawHeaderRow(in bounds: NSRect) {
        let rowHeight: CGFloat = 26
        let rowY = bounds.maxY - rowHeight - 10
        let rowRect = NSRect(x: 14, y: rowY, width: bounds.width - 28, height: rowHeight)

        // Kreisā puse — statusa pill
        let pillColor: NSColor
        let pillBorder: NSColor
        let dotColor: NSColor
        let textColor: NSColor

        switch mode {
        case .recording:
            pillColor = NSColor(red: 236/255, green: 72/255, blue: 153/255, alpha: 0.15)
            pillBorder = NSColor(red: 236/255, green: 72/255, blue: 153/255, alpha: 0.45)
            dotColor = NSColor(red: 236/255, green: 72/255, blue: 153/255, alpha: 1.0)
            textColor = NSColor(red: 255/255, green: 214/255, blue: 234/255, alpha: 1.0)
        case .transcribing:
            pillColor = NSColor(red: 34/255, green: 211/255, blue: 238/255, alpha: 0.15)
            pillBorder = NSColor(red: 34/255, green: 211/255, blue: 238/255, alpha: 0.45)
            dotColor = NSColor(red: 34/255, green: 211/255, blue: 238/255, alpha: 1.0)
            textColor = NSColor(red: 207/255, green: 250/255, blue: 254/255, alpha: 1.0)
        case .success:
            pillColor = NSColor(red: 16/255, green: 185/255, blue: 129/255, alpha: 0.15)
            pillBorder = NSColor(red: 16/255, green: 185/255, blue: 129/255, alpha: 0.45)
            dotColor = NSColor(red: 16/255, green: 185/255, blue: 129/255, alpha: 1.0)
            textColor = NSColor(red: 209/255, green: 250/255, blue: 229/255, alpha: 1.0)
        case .error:
            pillColor = NSColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 0.15)
            pillBorder = NSColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 0.45)
            dotColor = NSColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 1.0)
            textColor = NSColor(red: 254/255, green: 226/255, blue: 226/255, alpha: 1.0)
        }

        // Statusa teksts
        let statusFont = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        let statusAttrs: [NSAttributedString.Key: Any] = [
            .font: statusFont,
            .foregroundColor: textColor
        ]
        let statusSize = (statusText as NSString).size(withAttributes: statusAttrs)

        // Pills izmēri
        let dotSize: CGFloat = 7
        let dotPadding: CGFloat = 8
        let textPadding: CGFloat = 10
        let pillHeight: CGFloat = 22
        let pillWidth = dotPadding + dotSize + 6 + statusSize.width + textPadding
        let pillRect = NSRect(x: rowRect.minX,
                              y: rowRect.midY - pillHeight / 2,
                              width: min(pillWidth, rowRect.width - 90),
                              height: pillHeight)

        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillHeight / 2, yRadius: pillHeight / 2)
        pillColor.setFill()
        pillPath.fill()
        pillBorder.setStroke()
        pillPath.lineWidth = 1
        pillPath.stroke()

        // Glowjošs punkts
        let dotRect = NSRect(x: pillRect.minX + dotPadding,
                             y: pillRect.midY - dotSize / 2,
                             width: dotSize,
                             height: dotSize)
        let dotPath = NSBezierPath(ovalIn: dotRect)

        // Glow efekts
        let glowAlpha: CGFloat
        switch mode {
        case .recording:
            glowAlpha = 0.35 + 0.25 * (sin(pulse) * 0.5 + 0.5)
        case .transcribing:
            glowAlpha = 0.35 + 0.25 * (sin(pulse * 1.5) * 0.5 + 0.5)
        case .success, .error:
            glowAlpha = 0.5
        }
        let glowColor = dotColor.withAlphaComponent(glowAlpha)
        glowColor.setFill()
        let glowRect = dotRect.insetBy(dx: -3, dy: -3)
        NSBezierPath(ovalIn: glowRect).fill()

        dotColor.setFill()
        dotPath.fill()

        // Statusa teksts
        let textX = dotRect.maxX + 6
        let textRect = NSRect(x: textX,
                              y: pillRect.midY - statusSize.height / 2,
                              width: pillRect.maxX - textX - textPadding,
                              height: statusSize.height)
        (statusText as NSString).draw(in: textRect, withAttributes: statusAttrs)

        // Labā puse
        drawRightSide(in: rowRect)
    }

    private func drawRightSide(in rowRect: NSRect) {
        let rightFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let dimColor = NSColor(white: 1.0, alpha: 0.55)

        switch mode {
        case .recording:
            // Hronometrs
            let elapsedStr = formatElapsed(elapsed)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: rightFont,
                .foregroundColor: NSColor(white: 1.0, alpha: 0.85)
            ]
            let size = (elapsedStr as NSString).size(withAttributes: attrs)
            let rect = NSRect(x: rowRect.maxX - size.width,
                              y: rowRect.midY - size.height / 2,
                              width: size.width,
                              height: size.height)
            (elapsedStr as NSString).draw(in: rect, withAttributes: attrs)

        case .transcribing:
            // "Metal GPU" badge
            let badgeText = "Metal GPU"
            let badgeFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: NSColor(red: 34/255, green: 211/255, blue: 238/255, alpha: 1.0)
            ]
            let size = (badgeText as NSString).size(withAttributes: badgeAttrs)
            let padH: CGFloat = 8
            let padV: CGFloat = 3
            let badgeRect = NSRect(x: rowRect.maxX - size.width - padH * 2,
                                   y: rowRect.midY - (size.height + padV * 2) / 2,
                                   width: size.width + padH * 2,
                                   height: size.height + padV * 2)
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 6, yRadius: 6)
            NSColor(red: 34/255, green: 211/255, blue: 238/255, alpha: 0.12).setFill()
            badgePath.fill()
            NSColor(red: 34/255, green: 211/255, blue: 238/255, alpha: 0.35).setStroke()
            badgePath.lineWidth = 1
            badgePath.stroke()
            let textRect = NSRect(x: badgeRect.minX + padH,
                                  y: badgeRect.midY - size.height / 2,
                                  width: size.width,
                                  height: size.height)
            (badgeText as NSString).draw(in: textRect, withAttributes: badgeAttrs)

        case .success:
            // "100% lokāli" dim teksts
            let text = "100% lokāli"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: rightFont,
                .foregroundColor: dimColor
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let rect = NSRect(x: rowRect.maxX - size.width,
                              y: rowRect.midY - size.height / 2,
                              width: size.width,
                              height: size.height)
            (text as NSString).draw(in: rect, withAttributes: attrs)

        case .error:
            break
        }
    }

    private func formatElapsed(_ t: CFTimeInterval) -> String {
        let total = max(0, t)
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60
        let tenths = Int((total - floor(total)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    // MARK: - Viļņu zona

    private func drawWaveform(in bounds: NSRect) {
        let waveHeight: CGFloat = 48
        let waveRect = NSRect(x: 14, y: 8, width: bounds.width - 28, height: waveHeight)

        let gradient = Self.waveNSGradient
        let centerY = waveRect.midY

        switch mode {
        case .recording:
            drawRecordingWave(in: waveRect, centerY: centerY, gradient: gradient)
        case .transcribing:
            drawTranscribingWave(in: waveRect, centerY: centerY, gradient: gradient)
        case .success, .error:
            drawSettledBeam(in: waveRect, centerY: centerY, gradient: gradient)
        }
    }

    private func drawRecordingWave(in rect: NSRect, centerY: CGFloat, gradient: NSGradient?) {
        let amplitude = max(2, rect.height * 0.42 * (0.35 + level * 0.65))
        let steps = Int(rect.width)
        guard steps > 1 else { return }

        // Trīs harmonikas ar atšķirīgām fāzēm
        let path = NSBezierPath()
        path.lineWidth = 2.0
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        for i in 0...steps {
            let x = rect.minX + CGFloat(i)
            let t = CGFloat(i) / CGFloat(steps)
            let base = sin(t * .pi * 4 + phase) * 0.55
            let harmonic2 = sin(t * .pi * 7 + phase * 1.3) * 0.30
            let harmonic3 = sin(t * .pi * 11 + phase * 0.7) * 0.15
            let envelope = sin(t * .pi) // sašaurina galus
            let y = centerY + (base + harmonic2 + harmonic3) * amplitude * envelope
            if i == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }

        // Gradienta stroke — vienā piegājienā ar CoreGraphics
        drawGradientStroke(path: path, in: rect, lineWidth: 2.0)

        // Glow slānis
        let glowPath = path.copy() as! NSBezierPath
        glowPath.lineWidth = 5.0
        NSColor(red: 168/255, green: 85/255, blue: 247/255, alpha: 0.18).setStroke()
        glowPath.stroke()
    }

    private func drawTranscribingWave(in rect: NSRect, centerY: CGFloat, gradient: NSGradient?) {
        let steps = Int(rect.width)
        guard steps > 1 else { return }

        let pulseAmp = 0.5 + 0.5 * sin(pulse)
        let amplitude = rect.height * 0.18 * (0.6 + pulseAmp * 0.4)

        let path = NSBezierPath()
        path.lineWidth = 2.0
        path.lineCapStyle = .round

        for i in 0...steps {
            let x = rect.minX + CGFloat(i)
            let t = CGFloat(i) / CGFloat(steps)
            let envelope = sin(t * .pi)
            let y = centerY + sin(t * .pi * 3 + phase * 0.8) * amplitude * envelope
            if i == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }

        drawGradientStroke(path: path, in: rect, lineWidth: 2.0)

        // Pulsējošs glow
        let glowPath = path.copy() as! NSBezierPath
        glowPath.lineWidth = 6.0
        NSColor(red: 34/255, green: 211/255, blue: 238/255, alpha: 0.15 + pulseAmp * 0.15).setStroke()
        glowPath.stroke()
    }

    private func drawSettledBeam(in rect: NSRect, centerY: CGFloat, gradient: NSGradient?) {
        let beamHeight: CGFloat = 2.0
        let beamRect = NSRect(x: rect.minX, y: centerY - beamHeight / 2, width: rect.width, height: beamHeight)

        // Gradienta stars
        if let gradient = gradient {
            let path = NSBezierPath(roundedRect: beamRect, xRadius: beamHeight / 2, yRadius: beamHeight / 2)
            gradient.draw(in: path, angle: 0)
        }

        // Glow
        let glowRect = beamRect.insetBy(dx: 0, dy: -3)
        let glowPath = NSBezierPath(roundedRect: glowRect, xRadius: glowRect.height / 2, yRadius: glowRect.height / 2)
        NSColor(red: 168/255, green: 85/255, blue: 247/255, alpha: 0.20).setFill()
        glowPath.fill()
    }

    /// Zīmē gradienta līniju vienā piegājienā, izmantojot CoreGraphics stroked-path klipu.
    private func drawGradientStroke(path: NSBezierPath, in rect: NSRect, lineWidth: CGFloat) {
        if let ctx = NSGraphicsContext.current?.cgContext, let cgGrad = Self.waveCGGradient {
            ctx.saveGState()
            ctx.addPath(path.cgPath)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            ctx.drawLinearGradient(cgGrad,
                                   start: CGPoint(x: rect.minX, y: rect.midY),
                                   end: CGPoint(x: rect.maxX, y: rect.midY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        } else {
            NSColor.white.setStroke()
            path.lineWidth = lineWidth
            path.stroke()
        }
    }
}
