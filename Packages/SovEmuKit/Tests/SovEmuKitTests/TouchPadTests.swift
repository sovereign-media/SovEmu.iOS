import Testing
@testable import SovEmuKit

/// The touch controller's geometry: a thumb slides across the D-pad and the face buttons as on a
/// real pad, rather than each button needing a touch of its own.
struct TouchPadTests {
    private let pad = TouchPad(width: 844, height: 390)

    private func bits(_ buttons: RetroButton...) -> UInt16 { buttons.reduce(0) { $0 | $1.bit } }

    @Test func theDPadHasEightWaysAndADeadZone() {
        let r = 84.0
        #expect(TouchPad.directions(dx: 40, dy: 0, radius: r) == bits(.right))
        #expect(TouchPad.directions(dx: 0, dy: -40, radius: r) == bits(.up))
        // A diagonal holds both its directions: four buttons could not.
        #expect(TouchPad.directions(dx: 30, dy: 30, radius: r) == bits(.right, .down))
        #expect(TouchPad.directions(dx: -30, dy: -30, radius: r) == bits(.left, .up))
        #expect(TouchPad.directions(dx: -40, dy: 1, radius: r) == bits(.left))
        // At the centre nothing is pressed, so resting a thumb there is safe.
        #expect(TouchPad.directions(dx: 5, dy: 5, radius: r) == 0)
        // Past the pad's edge the direction still holds: a sliding thumb does not let go.
        #expect(TouchPad.directions(dx: 300, dy: 0, radius: r) == bits(.right))
    }

    @Test func aThumbSlidesAcrossTheDPadWithoutLiftingIt() {
        let c = pad.dpadCentre
        let start = TouchPoint(x: c.x, y: c.y - 50)
        #expect(pad.zone(at: start) == .dpad)
        #expect(pad.buttons(.dpad, at: start) == bits(.up))
        #expect(pad.buttons(.dpad, at: TouchPoint(x: c.x + 40, y: c.y - 40)) == bits(.up, .right))
        #expect(pad.buttons(.dpad, at: TouchPoint(x: c.x + 50, y: c.y)) == bits(.right))
    }

    @Test func aThumbOnTheFaceButtonsPressesTheNearestAndLetsGoOffThem() throws {
        let a = try #require(pad.keys.first { $0.button == .a }).frame.centre
        let b = try #require(pad.keys.first { $0.button == .b }).frame.centre
        #expect(pad.zone(at: a) == .face)
        #expect(pad.buttons(.face, at: a) == bits(.a))
        #expect(pad.buttons(.face, at: b) == bits(.b))
        // Slid far off the diamond, towards the screen's middle: nothing held.
        #expect(pad.buttons(.face, at: TouchPoint(x: 422, y: 100)) == 0)
    }

    @Test func theOtherKeysHoldWhileTheTouchStaysNearThem() throws {
        let start = try #require(pad.keys.first { $0.button == .start }).frame
        #expect(pad.zone(at: start.centre) == .key(.start))
        #expect(pad.buttons(.key(.start), at: TouchPoint(x: start.x - 5, y: start.centre.y)) == bits(.start))
        #expect(pad.buttons(.key(.start), at: TouchPoint(x: start.x - 100, y: start.centre.y)) == 0)
        #expect(pad.zone(at: TouchPoint(x: 30, y: 30)) == .key(.l))
    }

    @Test func theGamesScreenIsNoControl() {
        // A touch in the middle reaches neither the controls nor the game: the view lets it by.
        #expect(pad.zone(at: TouchPoint(x: 422, y: 150)) == nil)
    }
}
