import Foundation

// The touch controller's geometry: where each control sits on the screen and which RetroPad
// buttons a touch holds. One multi-touch view (the app's `TouchControls`) hit-tests every touch
// against it, so a thumb on the D-pad slides from one direction to the next, and to diagonals,
// and one on the face buttons slides between them, as on a real pad.

/// A point on the screen, in points, y down.
public struct TouchPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        (self.x, self.y) = (x, y)
    }
}

/// A rectangle on the screen, in points, y down.
public struct TouchRect: Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        (self.x, self.y, self.width, self.height) = (x, y, width, height)
    }

    public var centre: TouchPoint { TouchPoint(x: x + width / 2, y: y + height / 2) }

    func contains(_ p: TouchPoint, slop: Double = 0) -> Bool {
        p.x >= x - slop && p.x <= x + width + slop && p.y >= y - slop && p.y <= y + height + slop
    }
}

public struct TouchPad: Equatable, Sendable {
    /// One drawn control: its button, its label, where it is, and whether it is round.
    public struct Key: Equatable, Sendable {
        public let button: RetroButton
        public let label: String
        public let frame: TouchRect
        public let round: Bool
    }

    /// Which control a touch began on, and so how it is read as it moves.
    public enum Zone: Equatable, Sendable {
        /// The D-pad: the touch's direction from its centre.
        case dpad
        /// The face buttons: the one under the touch, or nearest it.
        case face
        /// One of the others (L, R, Select, Start): held while the touch stays near it.
        case key(RetroButton)
    }

    /// The D-pad's centre and reach.
    public let dpadCentre: TouchPoint
    public let dpadRadius: Double
    public let keys: [Key]

    /// The face buttons' diamond: its centre and reach.
    private let faceCentre: TouchPoint
    private let faceRadius: Double

    /// Within this share of the D-pad's radius a touch presses no direction.
    public static let deadZone = 0.2
    /// How far beyond a key's edge a touch still holds it: thumbs are wide.
    public static let slop = 12.0

    /// The layout for a screen area of `width` by `height` points (the safe area): the D-pad
    /// bottom left, the face buttons bottom right, Select and Start between them, L and R at
    /// the top corners, `margin` in from the edges.
    public init(width: Double, height: Double, margin: Double = 24) {
        let size = 56.0, gap = 56.0
        let cluster = size * 2 + gap // three rows of buttons, the middle one with a gap
        dpadRadius = cluster / 2
        dpadCentre = TouchPoint(x: margin + dpadRadius, y: height - margin - dpadRadius)
        faceRadius = cluster / 2
        faceCentre = TouchPoint(x: width - margin - faceRadius, y: height - margin - faceRadius)
        func around(_ c: TouchPoint, dx: Double, dy: Double) -> TouchRect {
            TouchRect(x: c.x + dx * (size + gap) / 2 - size / 2, y: c.y + dy * (size + gap) / 2 - size / 2, width: size,
                      height: size)
        }
        let (shoulderWidth, shoulderHeight) = (88.0, 40.0)
        let (smallWidth, smallHeight) = (72.0, 32.0)
        let middle = width / 2
        keys = [
            Key(button: .up, label: "▲", frame: around(dpadCentre, dx: 0, dy: -1), round: false),
            Key(button: .down, label: "▼", frame: around(dpadCentre, dx: 0, dy: 1), round: false),
            Key(button: .left, label: "◀", frame: around(dpadCentre, dx: -1, dy: 0), round: false),
            Key(button: .right, label: "▶", frame: around(dpadCentre, dx: 1, dy: 0), round: false),
            Key(button: .x, label: "X", frame: around(faceCentre, dx: 0, dy: -1), round: true),
            Key(button: .b, label: "B", frame: around(faceCentre, dx: 0, dy: 1), round: true),
            Key(button: .y, label: "Y", frame: around(faceCentre, dx: -1, dy: 0), round: true),
            Key(button: .a, label: "A", frame: around(faceCentre, dx: 1, dy: 0), round: true),
            Key(button: .l, label: "L", frame: TouchRect(x: margin, y: margin, width: shoulderWidth, height: shoulderHeight),
                round: false),
            Key(button: .r, label: "R",
                frame: TouchRect(x: width - margin - shoulderWidth, y: margin, width: shoulderWidth, height: shoulderHeight),
                round: false),
            Key(button: .select, label: "Select",
                frame: TouchRect(x: middle - 8 - smallWidth, y: height - margin - smallHeight, width: smallWidth,
                                 height: smallHeight), round: false),
            Key(button: .start, label: "Start",
                frame: TouchRect(x: middle + 8, y: height - margin - smallHeight, width: smallWidth, height: smallHeight),
                round: false),
        ]
    }

    private static let face: Set<RetroButton> = [.a, .b, .x, .y]

    /// The control a touch beginning at `p` is on; nil for none (the touch is the game's
    /// screen, or a button above the controls).
    public func zone(at p: TouchPoint) -> Zone? {
        if distance(p, dpadCentre) <= dpadRadius + Self.slop { return .dpad }
        if distance(p, faceCentre) <= faceRadius + Self.slop { return .face }
        return keys.first { !Self.face.contains($0.button) && $0.frame.contains(p, slop: Self.slop) }.map { .key($0.button) }
    }

    /// What a touch in `zone` holds at `p`, as RetroPad bits.
    public func buttons(_ zone: Zone, at p: TouchPoint) -> UInt16 {
        switch zone {
        case .dpad:
            return Self.directions(dx: p.x - dpadCentre.x, dy: p.y - dpadCentre.y, radius: dpadRadius)
        case .face:
            // The nearest face button while the thumb stays on the diamond (it may slide off
            // a little); none once it has left it.
            guard distance(p, faceCentre) <= faceRadius + 2 * Self.slop else { return 0 }
            let nearest = keys.filter { Self.face.contains($0.button) }.min { distance(p, $0.frame.centre) < distance(p, $1.frame.centre) }
            return nearest?.button.bit ?? 0
        case .key(let button):
            guard let key = keys.first(where: { $0.button == button }) else { return 0 }
            return key.frame.contains(p, slop: Self.slop) ? button.bit : 0
        }
    }

    /// The D-pad's directions for a touch `dx`, `dy` points from its centre (y down): none in
    /// the dead zone, else one of eight, each 45° wide, so a diagonal holds both its directions.
    /// Beyond the pad's edge the direction still counts: a sliding thumb does not let go.
    public static func directions(dx: Double, dy: Double, radius: Double) -> UInt16 {
        guard (dx * dx + dy * dy).squareRoot() > radius * deadZone else { return 0 }
        // 0 is right, counting clockwise (y down) in eighths.
        let angle = atan2(dy, dx)
        let sector = Int(((angle / (.pi / 4)).rounded() + 8).truncatingRemainder(dividingBy: 8))
        let ways: [[RetroButton]] = [[.right], [.right, .down], [.down], [.down, .left], [.left], [.left, .up], [.up],
                                     [.up, .right]]
        return ways[sector].reduce(0) { $0 | $1.bit }
    }

    private func distance(_ a: TouchPoint, _ b: TouchPoint) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
}
