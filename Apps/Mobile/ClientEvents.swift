import Foundation
import SovEmuKit
import UIKit

/// What goes wrong on this device, sent to the server's log (`client event`), so a fault can be
/// read with `kubectl logs`: a connection that failed or dropped, a controller with no known
/// layout. Events gather for two seconds and go in one call; a report that fails is dropped.
enum ClientEvents {
    private static let queue = ClientEventQueue()
    /// The signed-in client, set by `AppModel` whenever it makes one.
    static var api: SovEmuAPI?
    private static var gathering = false

    /// Reports something that went wrong. Safe from any thread.
    static func report(_ kind: ClientEventKind, _ message: String, sessionId: String? = nil) {
        guard queue.add(kind, message, sessionId: sessionId) else { return }
        DispatchQueue.main.async {
            guard !gathering else { return }
            gathering = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                gathering = false
                let batches = queue.take()
                guard let api else { return }
                let client = clientName
                Task {
                    for batch in batches { _ = try? await api.reportClientEvents(client: client, events: batch) }
                }
            }
        }
    }

    /// `ios 0.1.0 (iPad, iPadOS 18.1)`.
    static var clientName: String {
        let device = UIDevice.current
        return "ios \(version) (\(device.model), \(device.systemName) \(device.systemVersion))"
    }

    /// `SovEmu for iOS 0.1.0 · iPad`: this sign-in, on the admin's Devices page.
    static var deviceName: String { "SovEmu for iOS \(version) · \(UIDevice.current.model)" }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
