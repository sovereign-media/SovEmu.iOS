import GameController
import SovEmuKit

/// Port 0's RetroPad state from game controllers, a hardware keyboard and the touch controller.
///
/// Controller buttons map by position, as on the web and Android clients: the bottom face
/// (`buttonA` in GameController's Xbox-style naming) is RetroPad B, the right face is A.
/// Hold Select (Options) with R to fast-forward, with L to rewind; Select+Start, or the Home
/// button, opens the in-game menu.
final class Controller {
    private var touch: UInt16 = 0
    private let lock = NSLock()

    func setTouch(_ button: RetroButton, _ pressed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if pressed { touch |= button.bit } else { touch &= ~button.bit }
    }

    func clear() {
        lock.lock()
        touch = 0
        lock.unlock()
    }

    struct Reading {
        var buttons: UInt16
        var fastForward: Bool
        var rewind: Bool
        var menu: Bool
    }

    private func gamepadState() -> (UInt16, Bool) {
        var state: UInt16 = 0
        var home = false
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            let pairs: [(GCControllerButtonInput?, RetroButton)] = [
                (pad.buttonA, .b), (pad.buttonB, .a), (pad.buttonX, .y), (pad.buttonY, .x),
                (pad.leftShoulder, .l), (pad.rightShoulder, .r),
                (pad.leftTrigger, .l2), (pad.rightTrigger, .r2),
                (pad.leftThumbstickButton, .l3), (pad.rightThumbstickButton, .r3),
                (pad.buttonMenu, .start), (pad.buttonOptions, .select),
                (pad.dpad.up, .up), (pad.dpad.down, .down), (pad.dpad.left, .left), (pad.dpad.right, .right),
            ]
            for (input, button) in pairs where input?.isPressed == true {
                state |= button.bit
            }
            let x = pad.leftThumbstick.xAxis.value, y = pad.leftThumbstick.yAxis.value
            if x < -0.5 { state |= RetroButton.left.bit }
            if x > 0.5 { state |= RetroButton.right.bit }
            if y > 0.5 { state |= RetroButton.up.bit }
            if y < -0.5 { state |= RetroButton.down.bit }
            home = home || (pad.buttonHome?.isPressed ?? false)
        }
        if let keyboard = GCKeyboard.coalesced?.keyboardInput {
            let keys: [(GCKeyCode, RetroButton)] = [
                (.upArrow, .up), (.downArrow, .down), (.leftArrow, .left), (.rightArrow, .right),
                (.keyX, .a), (.keyZ, .b), (.keyA, .y), (.keyS, .x), (.keyQ, .l), (.keyW, .r),
                (.returnOrEnter, .start), (.leftShift, .select),
            ]
            for (code, button) in keys where keyboard.button(forKeyCode: code)?.isPressed == true {
                state |= button.bit
            }
            home = home || (keyboard.button(forKeyCode: .escape)?.isPressed ?? false)
        }
        return (state, home)
    }

    func read() -> Reading {
        let (pads, home) = gamepadState()
        lock.lock()
        let raw = pads | touch
        lock.unlock()
        let select = raw & RetroButton.select.bit != 0
        let ff = select && raw & RetroButton.r.bit != 0
        let rewind = select && raw & RetroButton.l.bit != 0
        let menu = home || (select && raw & RetroButton.start.bit != 0)
        var buttons = raw
        if ff || rewind { buttons &= ~(RetroButton.select.bit | RetroButton.l.bit | RetroButton.r.bit) }
        return Reading(buttons: buttons, fastForward: ff, rewind: rewind, menu: menu)
    }
}
