// *Who's watching?* and *Choose a server*, as SovEmu.Android's `core/Launch.kt` (after
// Sovereign.Android's): the words, when the picker comes back, its D-pad moves, and moving
// between servers. `ServerChooser` takes what it needs from the app's session as
// `AccountSession`, which the app's multi-account session supplies (Android passes its `Session`).
import Foundation

/// The words *Who's watching?* and its neighbours use, as Sovereign.Android's.
public enum LaunchText {
    public static let whoIsWatching = "Who's watching?"
    public static let addUser = "Add user"

    /// The account menu's way into the picker: it stands for switching user and server.
    public static let changeUserOrServer = "Change user or server"

    /// Under the current account's tile on the picker opened from the account menu.
    public static let signedInNow = "Signed in now"

    /// The title of the sign-in form `Add user` opens.
    public static let addAUser = "Add a user"
    public static let changeServer = "Change server"

    /// What the sign-in form says when an account's sign-in ended on the server.
    public static let expired = "Your sign-in has ended. Sign in again."

    /// Three across: five accounts and `Add user` fill two rows.
    public static let pickerColumns = 3
}

/// Whether the app shows *Who's watching?* as it comes back to the foreground, as Sovereign's: an
/// app left in the background keeps running for hours, so a picker shown only at launch would
/// almost never show, and whoever picks up the remote next would carry on as whoever used it
/// last. `backgroundedAt` and `now` are a monotonic clock (ms, counting deep sleep); fewer than
/// two accounts, a threshold of 0, or a game playing never show it.
public enum IdlePicker {
    /// Sovereign's default for its server's `userPickerAfterMinutes`; SovEmu's server has no such
    /// setting yet, so the app uses this.
    public static let thresholdMinutes = 60

    public static func shouldShow(
        backgroundedAt: Int64?, now: Int64, accounts: Int, playing: Bool, thresholdMinutes: Int = thresholdMinutes
    ) -> Bool {
        guard let backgroundedAt, accounts >= 2, thresholdMinutes > 0, !playing else { return false }
        return now - backgroundedAt >= Int64(thresholdMinutes) * 60_000
    }
}

/// Where each D-pad direction goes from one tile of the picker. Nil: nowhere.
public struct PickerMove: Sendable, Equatable {
    public let left: Int?
    public let right: Int?
    public let up: Int?
    public let down: Int?

    public init(left: Int?, right: Int?, up: Int?, down: Int?) {
        (self.left, self.right, self.up, self.down) = (left, right, up, down)
    }
}

/// Every tile's four moves, for `count` tiles wrapped `columns` to a row with each row centred: Up
/// and Down go to the nearest tile in the next row, which on a centred short row is not the same
/// index (the focus engine's geometric search answers by distance, and can land on the wrong
/// row). A tie goes left.
public func pickerFocusMoves(count: Int, columns: Int) -> [PickerMove] {
    guard count > 0, columns > 0 else { return [] }
    let rows = (count + columns - 1) / columns
    func size(_ row: Int) -> Int { row < rows - 1 ? columns : count - columns * (rows - 1) }
    func centre(_ row: Int, _ column: Int) -> Double { Double(column) - Double(size(row) - 1) / 2 }
    func nearest(_ row: Int, _ from: Double) -> Int {
        var best = 0
        var distance = Double.greatestFiniteMagnitude
        for column in 0..<size(row) {
            let d = abs(centre(row, column) - from)
            if d < distance - 1e-9 {
                best = column
                distance = d
            }
        }
        return row * columns + best
    }
    return (0..<count).map { index in
        let row = index / columns
        let column = index % columns
        let x = centre(row, column)
        return PickerMove(
            left: column > 0 ? index - 1 : nil,
            right: column < size(row) - 1 ? index + 1 : nil,
            up: row > 0 ? nearest(row - 1, x) : nil,
            down: row < rows - 1 ? nearest(row + 1, x) : nil)
    }
}

// MARK: - Choose a server

/// The server the app talks to, as *Choose a server* (and `ServerAddress.check`) moves it.
/// Requirements are `async` so the app's `@MainActor` model can conform.
public protocol ServerService: Sendable {
    /// The address the app talks to now.
    func server() async -> String

    /// Makes `address` the server without asking it anything (putting one back).
    func setServer(_ address: String) async

    /// Asks `address` how to sign in (`bootstrapConfig`), and keeps it as the server.
    func bootstrap(at address: String) async throws -> BootstrapConfig
}

/// What *Choose a server* needs from the app's session (Android's `Session`): where a launch lands
/// on the current server, and taking a server's accounts off the device.
public protocol AccountSession: Sendable {
    /// Decides where the app opens for the current server, without a token request, and lands
    /// there (`AccountStore.launch(on:now:)` and the session's own state).
    func launch() async -> LaunchAccounts

    /// Signs out every account on `address` (each token revoked on its own server, without
    /// waiting); whether the active account was among them (`AccountStore.removeServer`).
    @discardableResult
    func removeServer(_ address: String) async -> Bool
}

/// Where choosing or removing a server leaves the app.
public enum ServerMove: Sendable, Equatable {
    /// Nothing changed: the server in use was chosen.
    case stayed
    /// The app now talks to another server, and has landed there by the launch rule.
    case moved(LaunchAccounts)
    /// No server is left: the sign-in screen, with an empty address.
    case noServer
    /// The chosen server did not answer: the app is still on the one it was, and why.
    case failed(String)
}

/// *Choose a server*'s choices, as Sovereign's: switching server is a choice rather than retyping
/// an address, and removing one signs out everyone on it. A live sign-in is set aside on a switch,
/// never signed out: its accounts stay, and come back with their server.
public struct ServerChooser: Sendable {
    private let service: any ServerService
    private let session: any AccountSession

    public init(service: any ServerService, session: any AccountSession) {
        (self.service, self.session) = (service, session)
    }

    /// Moves to `server`: it answers its `bootstrapConfig` (no token request), then the launch
    /// rule lands there (its one account's Home, or its picker). A server that does not answer
    /// leaves the app where it was.
    public func choose(_ server: KnownServer) async throws -> ServerMove {
        if server.inUse { return .stayed }
        let previous = await service.server()
        do {
            _ = try await service.bootstrap(at: server.address)
        } catch is CancellationError {
            await service.setServer(previous)
            throw CancellationError()
        } catch {
            await service.setServer(previous)
            return .failed(ServerAddress.reachFailure(error, address: server.address))
        }
        return .moved(await session.launch())
    }

    /// Removes `server` from `servers` (the list as shown) and everyone on it. When it was the one
    /// in use, the app moves to the server that took its place in the list (even if that one does
    /// not answer: its picker makes no request), or to no server at all.
    public func remove(_ server: KnownServer, from servers: [KnownServer]) async throws -> ServerMove {
        let current = await service.server()
        let inUse = server.inUse || StoredAccount.sameServer(server.address, current)
        let next = KnownServers.successor(servers, removed: server)
        await session.removeServer(server.address)
        if !inUse { return .stayed }
        guard let next else {
            await service.setServer("")
            _ = await session.launch()
            return .noServer
        }
        do {
            _ = try await service.bootstrap(at: next.address)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await service.setServer(next.address)
        }
        return .moved(await session.launch())
    }
}
