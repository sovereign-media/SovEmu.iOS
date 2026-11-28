// The touch controller, as one multi-touch view: every touch is hit-tested against SovEmuKit's
// `TouchPad`, so a thumb slides across the D-pad (diagonals included) and the face buttons as
// on a real pad. Shown when no controller or keyboard is connected. SovEmu.Android's
// `TouchControls`; the web has none.

import SovEmuKit
import UIKit

final class TouchControlsView: UIView {
    private let controller: Controller
    private var pad = TouchPad(width: 0, height: 0)
    /// Each touch on a control, and the control it began on. Main thread only, as UIKit is.
    private var touches: [ObjectIdentifier: (touch: UITouch, zone: TouchPad.Zone)] = [:]
    /// What the touches hold now: drawn lit, and the controller's touch input.
    private var held: UInt16 = 0

    init(controller: Controller) {
        self.controller = controller
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { nil }

    /// Lets go of everything: the view is going away.
    func releaseAll() {
        touches.removeAll()
        update()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let area = bounds.inset(by: safeAreaInsets)
        pad = TouchPad(width: Double(area.width), height: Double(area.height))
        setNeedsDisplay()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    /// Touches off the controls go by, to the game's screen and the ☰ button.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        pad.zone(at: padPoint(point)) != nil
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let zone = pad.zone(at: padPoint(touch.location(in: self))) {
                self.touches[ObjectIdentifier(touch)] = (touch, zone)
            }
        }
        update()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update() }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }

    private func end(_ touches: Set<UITouch>) {
        for touch in touches { self.touches[ObjectIdentifier(touch)] = nil }
        update()
    }

    /// What every touch holds, where it is now; told to the controller and drawn when it changes.
    private func update() {
        let now = touches.values.reduce(UInt16(0)) { $0 | pad.buttons($1.zone, at: padPoint($1.touch.location(in: self))) }
        guard now != held else { return }
        held = now
        controller.setTouch(now)
        setNeedsDisplay()
    }

    /// A point in the view, in the pad's safe-area space.
    private func padPoint(_ p: CGPoint) -> TouchPoint {
        TouchPoint(x: Double(p.x - safeAreaInsets.left), y: Double(p.y - safeAreaInsets.top))
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        let origin = CGPoint(x: safeAreaInsets.left, y: safeAreaInsets.top)
        let font = UIFont.systemFont(ofSize: 14, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white.withAlphaComponent(0.9)]
        for key in pad.keys {
            let frame = CGRect(x: origin.x + key.frame.x, y: origin.y + key.frame.y, width: key.frame.width,
                               height: key.frame.height)
            let lit = held & key.button.bit != 0
            UIColor.white.withAlphaComponent(lit ? 0.45 : 0.18).setFill()
            UIBezierPath(roundedRect: frame, cornerRadius: key.round ? frame.height / 2 : 10).fill()
            let label = key.label as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2), withAttributes: attributes)
        }
    }
}
