import GameController
import SovEmuKit

/// What the controllers and the remote did, on the console of a debug build (`devicectl device
/// process launch --console`): for finding which input did what on a device. Nothing in release.
func inputTrace(_ line: @autoclosure () -> String) {
    #if DEBUG
    print(String(format: "[input %.3f] ", ProcessInfo.processInfo.systemUptime) + line())
    #endif
}

/// Every player's RetroPad state from game controllers, a hardware keyboard and the touch
/// controller, as `docs/CONTROLLERS.md` (in SovEmu) describes.
///
/// Each controller (Bluetooth or USB/Lightning, all through GameController) is recognised by
/// model (`ControllerIdentity`) and drives its own player, in the order controllers connect:
/// the lowest free port, freed again when it disconnects. The keyboard and the touch controls
/// are player 1. Inputs go through the user's mapping for the model (saved on the server and
/// shared with the other clients), else the defaults. Hotkeys are read after mapping: SELECT+R
/// fast-forwards, SELECT+L rewinds and SELECT+START opens the menu; on a keyboard, Tab
/// fast-forwards, Backspace rewinds and Escape opens the menu (unless the mapping binds it).
/// Home opens the menu too.
final class Controller {
    /// A connected device: this connection, not its model.
    enum DeviceKey: Hashable {
        case keyboard
        case pad(ObjectIdentifier)
    }

    struct Device: Identifiable {
        let key: DeviceKey
        let identity: ControllerIdentity
        /// 0-3 (player 1-4).
        let port: Int
        var id: DeviceKey { key }
    }

    struct Reading {
        /// Per port, from port 0 to the highest in use.
        var ports: [UInt16]
        /// As long as `ports`.
        var analog: [WireProtocol.Analog]
        var fastForward: Bool
        var rewind: Bool
        var menu: Bool
    }

    /// The game reads analog sticks (a 3D system): the left stick moves the stick, not the
    /// D-pad. Otherwise it doubles as a D-pad, as in 2D frontends. Set on the main thread, read
    /// by `read()` on the input queue: under `lock`.
    var analogSticks: Bool {
        get { lock.withLock { sticksAreAnalog } }
        set { lock.withLock { sticksAreAnalog = newValue } }
    }

    private let lock = NSLock()
    private var sticksAreAnalog = false
    private var touch: UInt16 = 0
    private var players = Players<ObjectIdentifier>()
    private var keyboardPort = 0
    private var store = Mappings(system: "")
    private var identities: [ObjectIdentifier: ControllerIdentity] = [:]
    private var observers: [NSObjectProtocol] = []
    /// When a controller last had anything held (system uptime, seconds), under `lock`: `read()`
    /// sets it every few milliseconds while one plays.
    private var padHeldAt: TimeInterval = -.infinity
    /// Whether `read()` last saw the menu asked for (on the input queue only): for the trace.
    private var menuWasAsked = false
    /// Called on `wakeQueue` whenever an input changes, with the event's time on the 32-bit
    /// `client_time_ms` clock when GameController gives one (`observe`). Under `lock`.
    private var wake: (@Sendable (Int64?) -> Void)?
    private var wakeQueue: DispatchQueue?

    /// Every controller tvOS reports, with its profiles: for the trace.
    static func describeControllers() -> String {
        GCController.controllers().map { c in
            "\(c.vendorName ?? "?") [\(c.productCategory)] ext=\(c.extendedGamepad != nil) micro=\(c.microGamepad != nil)"
        }.joined(separator: "; ")
    }

    init() {
        // Controllers already connected join in GameController's order.
        for controller in GCController.controllers() { join(controller) }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            if let controller = note.object as? GCController { self?.join(controller) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            if let controller = note.object as? GCController { self?.leave(controller) }
        })
        observers.append(center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] note in
            if let keyboard = note.object as? GCKeyboard { self?.install(keyboard) }
        })
    }

    // MARK: Waking on input

    /// Calls `wake` on `queue` whenever a controller, the keyboard, the remote or the touch
    /// controls change, instead of being polled: GameController's handlers run on `queue`, so
    /// a press reaches the input pump without waiting for a timer. On the main thread.
    func observe(on queue: DispatchQueue, wake: @escaping @Sendable (Int64?) -> Void) {
        lock.withLock { (self.wake, wakeQueue) = (wake, queue) }
        GCController.controllers().forEach(install)
        if let keyboard = GCKeyboard.coalesced { install(keyboard) }
    }

    /// Stops `observe`'s handlers. On the main thread.
    func stopObserving() {
        lock.withLock { (wake, wakeQueue) = (nil, nil) }
        for controller in GCController.controllers() {
            controller.extendedGamepad?.valueChangedHandler = nil
            controller.microGamepad?.valueChangedHandler = nil
            controller.handlerQueue = .main
        }
        if let keyboard = GCKeyboard.coalesced {
            keyboard.keyboardInput?.keyChangedHandler = nil
            keyboard.handlerQueue = .main
        }
    }

    private func install(_ controller: GCController) {
        guard let queue = lock.withLock({ wakeQueue }) else { return }
        controller.handlerQueue = queue
        if let pad = controller.extendedGamepad {
            pad.valueChangedHandler = { [weak self] pad, _ in
                guard let self else { return }
                // A controller's press, for `padActive`: recorded here because the input loop
                // does not read the controllers while the menu is open.
                lock.withLock { self.padHeldAt = ProcessInfo.processInfo.systemUptime }
                changed(at: pad.lastEventTimestamp)
            }
        } else if let remote = controller.microGamepad {
            // A Siri Remote: only its menu presses matter here.
            remote.valueChangedHandler = { [weak self] remote, _ in self?.changed(at: remote.lastEventTimestamp) }
        }
    }

    private func install(_ keyboard: GCKeyboard) {
        guard let queue = lock.withLock({ wakeQueue }) else { return }
        keyboard.handlerQueue = queue
        keyboard.keyboardInput?.keyChangedHandler = { [weak self] input, _, _, _ in self?.changed(at: input.lastEventTimestamp) }
    }

    /// On `wakeQueue`: an event's time (seconds since boot, as `systemUptime`) on the 32-bit
    /// millisecond clock acks are measured on.
    private func changed(at timestamp: TimeInterval) {
        let ms = timestamp > 0 ? Int64(UInt32(truncatingIfNeeded: Int64(timestamp * 1000))) : nil
        lock.withLock { wake }?(ms)
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func join(_ controller: GCController) {
        install(controller)
        guard controller.extendedGamepad != nil else { return }
        let identity = ControllerIdentity.identify(productCategory: controller.productCategory, vendorName: controller.vendorName)
        lock.lock()
        defer { lock.unlock() }
        identities[ObjectIdentifier(controller)] = identity
        players.join(ObjectIdentifier(controller))
        // A model SovEmu's docs/CONTROLLERS.md does not know yet: worth adding.
        if identity.id.hasPrefix("pad:") {
            ClientEvents.report(.controllerUnknown, "\(controller.productCategory) / \(controller.vendorName ?? "?") → \(identity.id)")
        }
    }

    private func leave(_ controller: GCController) {
        lock.lock()
        defer { lock.unlock() }
        players.leave(ObjectIdentifier(controller))
        identities[ObjectIdentifier(controller)] = nil
    }

    // MARK: Mappings

    /// The user's mappings for the system being played (and for every system), as the
    /// server layers them; replaced after every save and reset.
    var mappings: Mappings {
        get {
            lock.lock()
            defer { lock.unlock() }
            return store
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            store = newValue
        }
    }

    /// The mapping in force in play for a controller model.
    func mapping(for controller: String) -> ControllerMap { mappings.mapping(for: controller) }

    // MARK: Devices and players

    /// The keyboard (if one is attached) and every connected controller, with their players.
    func devices() -> [Device] {
        var out: [Device] = []
        lock.lock()
        defer { lock.unlock() }
        if GCKeyboard.coalesced != nil {
            out.append(Device(key: .keyboard, identity: .keyboard, port: keyboardPort))
        }
        for controller in GCController.controllers() where controller.extendedGamepad != nil {
            let key = ObjectIdentifier(controller)
            let identity = identities[key]
                ?? ControllerIdentity.identify(productCategory: controller.productCategory, vendorName: controller.vendorName)
            identities[key] = identity
            out.append(Device(key: .pad(key), identity: identity, port: players.join(key)))
        }
        return out
    }

    /// Moves a device to another player for this session.
    func setPort(_ device: DeviceKey, _ port: Int) {
        lock.lock()
        defer { lock.unlock() }
        switch device {
        case .keyboard: keyboardPort = max(0, min(WireProtocol.maxPorts - 1, port))
        case .pad(let key): players.set(key, port: port)
        }
    }

    // MARK: Raw inputs

    private static func pressedInputs(_ pad: GCExtendedGamepad) -> Set<String> {
        let pairs: [(GCControllerButtonInput?, PadInput)] = [
            (pad.buttonA, .south), (pad.buttonB, .east), (pad.buttonX, .west), (pad.buttonY, .north),
            (pad.leftShoulder, .l1), (pad.rightShoulder, .r1), (pad.leftTrigger, .l2), (pad.rightTrigger, .r2),
            (pad.buttonOptions, .select), (pad.buttonMenu, .start),
            (pad.leftThumbstickButton, .l3), (pad.rightThumbstickButton, .r3),
            (pad.dpad.up, .up), (pad.dpad.down, .down), (pad.dpad.left, .left), (pad.dpad.right, .right),
        ]
        return Set(pairs.compactMap { $0.0?.isPressed == true ? $0.1.rawValue : nil })
    }

    private static func pressedKeys(_ keyboard: GCKeyboardInput) -> Set<String> {
        var keys = Set<String>()
        for usage in KeyNames.allUsages {
            if keyboard.button(forKeyCode: GCKeyCode(rawValue: usage))?.isPressed == true,
               let code = KeyNames.code(forUsage: usage) {
                keys.insert(code)
            }
        }
        return keys
    }

    /// Both sticks' directions past half-way (`ls_left` …), bindable inputs.
    private static func sticks(_ pad: GCExtendedGamepad) -> Set<String> {
        stickInputs(
            lx: pad.leftThumbstick.xAxis.value, ly: pad.leftThumbstick.yAxis.value,
            rx: pad.rightThumbstick.xAxis.value, ry: pad.rightThumbstick.yAxis.value
        )
    }

    /// The left stick pushed past halfway, as D-pad directions.
    private static func stickDirections(_ pad: GCExtendedGamepad) -> Set<String> {
        let x = pad.leftThumbstick.xAxis.value, y = pad.leftThumbstick.yAxis.value
        var out = Set<String>()
        if x < -0.5 { out.insert("left") }
        if x > 0.5 { out.insert("right") }
        if y > 0.5 { out.insert("up") }
        if y < -0.5 { out.insert("down") }
        return out
    }

    /// What is held on each device right now, by input name, for remapping and menus. A
    /// controller's Home button is `home` (never bound); with `stick`, its left stick counts
    /// as its D-pad.
    func held(stick: Bool = false) -> [DeviceKey: Set<String>] {
        var out: [DeviceKey: Set<String>] = [:]
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            var inputs = Self.pressedInputs(pad)
            if stick { inputs.formUnion(Self.stickDirections(pad)) }
            inputs.formUnion(Self.sticks(pad))
            if pad.buttonHome?.isPressed == true { inputs.insert("home") }
            out[.pad(ObjectIdentifier(controller))] = inputs
        }
        if let keyboard = GCKeyboard.coalesced?.keyboardInput {
            out[.keyboard] = Self.pressedKeys(keyboard)
        }
        for controller in GCController.controllers() where controller.extendedGamepad == nil {
            guard let remote = controller.microGamepad else { continue }
            out[.pad(ObjectIdentifier(controller))] = Self.remoteInputs(remote)
        }
        return out
    }

    /// While a game plays, a controller's Home button opens SovEmu's menu (as Select+Start does)
    /// instead of the system's: Apple TV's Control Center, or an iPad's Home Screen. The system
    /// keeps it everywhere else, and keeps a long press (Apple TV's own rule).
    static func claimHome(_ claim: Bool) {
        for controller in GCController.controllers() {
            controller.extendedGamepad?.buttonHome?.preferredSystemGestureState = claim ? .disabled : .enabled
        }
    }

    /// Whether a controller (not the remote) has had anything held in the last `within`
    /// seconds: a command tvOS raised then came from it (its B is Back, its X Play/Pause), and
    /// the game or the polled menu has it already. Asked a moment after the command, for tvOS
    /// can raise it before GameController reports the press, and a tap may be over by then.
    func padActive(within: TimeInterval = 0.3) -> Bool {
        let heldNow = GCController.controllers().contains { controller in
            guard let pad = controller.extendedGamepad else { return false }
            return !Self.pressedInputs(pad).isEmpty || !Self.stickDirections(pad).isEmpty
        }
        lock.lock()
        defer { lock.unlock() }
        let ago = ProcessInfo.processInfo.systemUptime - padHeldAt
        inputTrace("padActive: held now=\(heldNow), last held \(String(format: "%.3f", ago)) s ago")
        return heldNow || ago < within
    }

    // MARK: The Siri Remote

    /// A Siri Remote (an Apple TV's, a micro gamepad) never plays: it moves through the menus as
    /// a pad's D-pad and face buttons do. Its click pad's directions are the D-pad, a click
    /// confirms (`south`), and Back goes back (`east`).
    private static func remoteInputs(_ remote: GCMicroGamepad) -> Set<String> {
        remote.reportsAbsoluteDpadValues = false
        var out = Set<String>()
        let x = remote.dpad.xAxis.value, y = remote.dpad.yAxis.value
        if x < -0.5 { out.insert("left") }
        if x > 0.5 { out.insert("right") }
        if y > 0.5 { out.insert("up") }
        if y < -0.5 { out.insert("down") }
        if remote.buttonA.isPressed { out.insert("south") }
        if remote.buttonMenu.isPressed { out.insert("east") }
        return out
    }

    /// The remote's Back or Play/Pause pressed during play: the in-game menu, as a pad's Home.
    private static func remoteMenuPressed(_ controllers: [GCController]) -> Bool {
        controllers.contains { controller in
            guard controller.extendedGamepad == nil, let remote = controller.microGamepad else { return false }
            return remote.buttonMenu.isPressed || remote.buttonX.isPressed
        }
    }

    // MARK: Play

    func setTouch(_ button: RetroButton, _ pressed: Bool) {
        updateTouch { pressed ? $0 | button.bit : $0 & ~button.bit }
    }

    /// Every touch control held at once (`TouchControls`).
    func setTouch(_ state: UInt16) {
        updateTouch { _ in state }
    }

    /// Changes what the touch controls hold, and wakes the input pump at once.
    private func updateTouch(_ change: (UInt16) -> UInt16) {
        let (wake, queue) = lock.withLock {
            touch = change(touch)
            return (self.wake, wakeQueue)
        }
        let now = Int64(Stream.now32())
        queue?.async { wake?(now) }
    }

    func clear() {
        lock.lock()
        touch = 0
        lock.unlock()
    }

    func read() -> Reading {
        var ports = [UInt16](repeating: 0, count: WireProtocol.maxPorts)
        var analog = [WireProtocol.Analog](repeating: .centred, count: WireProtocol.maxPorts)
        var analogSet = Set<Int>()
        var used = 0
        var fastForward = false, rewind = false, menu = false

        let controllers = GCController.controllers()
        let keyboard = GCKeyboard.coalesced?.keyboardInput
        lock.lock()
        let touch = self.touch
        let keyboardPort = self.keyboardPort
        let store = self.store
        let analogSticks = sticksAreAnalog
        var pads: [(pad: GCExtendedGamepad, port: Int, mapping: ControllerMap)] = []
        for controller in controllers {
            guard let pad = controller.extendedGamepad else { continue }
            let key = ObjectIdentifier(controller)
            let identity = identities[key]
                ?? ControllerIdentity.identify(productCategory: controller.productCategory, vendorName: controller.vendorName)
            identities[key] = identity
            pads.append((pad, players.join(key), store.mapping(for: identity.id)))
        }
        lock.unlock()

        // Each pad's buttons and stick directions, read once.
        let held = pads.map { (pressed: Self.pressedInputs($0.pad), directions: Self.stickDirections($0.pad)) }
        if held.contains(where: { !$0.pressed.isEmpty || !$0.directions.isEmpty }) {
            lock.lock()
            padHeldAt = ProcessInfo.processInfo.systemUptime
            lock.unlock()
        }
        for ((pad, port, mapping), (pressed, directions)) in zip(pads, held) {
            let hotkeys = HotkeyReading.read(mapping.state(pressed))
            fastForward = fastForward || hotkeys.fastForward
            rewind = rewind || hotkeys.rewind
            menu = menu || hotkeys.menu || pad.buttonHome?.isPressed == true
            var state = hotkeys.state | mapping.state(Self.sticks(pad))
            // Unbound, the left stick doubles as the D-pad (not on a system that reads the sticks).
            if !analogSticks && !mapping.bindsLeftStick {
                for direction in directions {
                    state |= ControllerMap.pad.state([direction])
                }
            }
            if analogSet.insert(port).inserted {
                // GameController's y axes point up; libretro's point down.
                analog[port] = WireProtocol.Analog(
                    lx: WireProtocol.Analog.stick(pad.leftThumbstick.xAxis.value),
                    ly: WireProtocol.Analog.stick(-pad.leftThumbstick.yAxis.value),
                    rx: WireProtocol.Analog.stick(pad.rightThumbstick.xAxis.value),
                    ry: WireProtocol.Analog.stick(-pad.rightThumbstick.yAxis.value),
                    l2: WireProtocol.Analog.trigger(pad.leftTrigger.value),
                    r2: WireProtocol.Analog.trigger(pad.rightTrigger.value)
                )
            }
            ports[port] |= state
            used = max(used, port)
        }

        // The touch controls are player 1; the keyboard is player 1 unless moved.
        var touchHotkeys = HotkeyReading.read(touch)
        if let keyboard {
            let keys = Self.pressedKeys(keyboard)
            let mapping = store.mapping(for: ControllerIdentity.keyboardID)
            fastForward = fastForward || keys.contains(KeyNames.fastForward)
            rewind = rewind || keys.contains(KeyNames.rewind)
            menu = menu || (keys.contains(KeyNames.menu) && mapping.bindings[KeyNames.menu] == nil)
            let state = mapping.state(keys.filter(KeyNames.bindable))
            if keyboardPort == 0 {
                touchHotkeys = HotkeyReading.read(touch | state)
            } else {
                let hotkeys = HotkeyReading.read(state)
                fastForward = fastForward || hotkeys.fastForward
                rewind = rewind || hotkeys.rewind
                menu = menu || hotkeys.menu
                ports[keyboardPort] |= hotkeys.state
                used = max(used, keyboardPort)
            }
        }
        fastForward = fastForward || touchHotkeys.fastForward
        rewind = rewind || touchHotkeys.rewind
        let remoteMenu = Self.remoteMenuPressed(controllers)
        if (menu || touchHotkeys.menu || remoteMenu) && !menuWasAsked {
            let home = pads.contains { $0.pad.buttonHome?.isPressed == true }
            inputTrace("read: menu asked (home=\(home) remote=\(remoteMenu) touch/keys=\(touchHotkeys.menu)) pads=\(held.map { $0.pressed.sorted() })")
        }
        menu = menu || touchHotkeys.menu || remoteMenu
        menuWasAsked = menu
        ports[0] |= touchHotkeys.state

        return Reading(
            ports: Array(ports.prefix(used + 1)), analog: Array(analog.prefix(used + 1)),
            fastForward: fastForward, rewind: rewind, menu: menu)
    }
}
