import Foundation

// Where this client's link goes and how it was measured (#243), as SovEmu.Web's link.ts and
// SovEmu.Android's: the path it reports to the worker (`Stats.path`), the stats overlay's Network
// rows, and the loading screen's "Home network" / "Remote". The three clients word these the same.

/// One end of the selected ICE candidate pair, as WebRTC's statistics report it: its
/// `candidateType` (`host`, `srflx`, `prflx`, `relay`), `protocol` (`udp`, `tcp`) and, for a
/// relay candidate, `relayProtocol` (how this client reaches the relay: `udp`, `tcp`, `tls`).
public struct IceCandidateStats: Equatable, Sendable {
    public var candidateType: String
    public var `protocol`: String?
    public var relayProtocol: String?

    public init(candidateType: String, protocol: String? = nil, relayProtocol: String? = nil) {
        (self.candidateType, self.protocol, self.relayProtocol) = (candidateType, `protocol`, relayProtocol)
    }

    var isRelay: Bool { candidateType == "relay" }
}

public enum LinkLabels {
    /// The path this client reports in its stats (`ClientStats.path`): through the relay over
    /// `relay-udp`, `relay-tcp` or `relay-tls` when its own end of the pair is a relay
    /// candidate, else `direct`. Only the client can tell the relay's transports apart: the relay
    /// forwards UDP to the worker whichever it used.
    public static func clientPath(_ local: IceCandidateStats?) -> String? {
        guard let local else { return nil }
        guard local.isRelay else { return "direct" }
        let p = (local.relayProtocol ?? "udp").lowercased()
        return "relay-\(p == "tcp" || p == "tls" ? p : "udp")"
    }

    private static let candidates = ["host": "host", "srflx": "STUN", "prflx": "STUN", "relay": "relay"]

    /// `host → host`, `STUN → host`, `relay → host`: the selected pair's candidate types.
    public static func pairLabel(_ local: IceCandidateStats?, _ remote: IceCandidateStats?) -> String? {
        guard let l = local.flatMap({ candidates[$0.candidateType] }), let r = remote.flatMap({ candidates[$0.candidateType] })
        else { return nil }
        return "\(l) → \(r)"
    }

    /// `UDP`, or `TCP to the relay` / `TLS to the relay` when relayed.
    public static func transportLabel(_ local: IceCandidateStats?) -> String? {
        guard let local else { return nil }
        if local.isRelay { return "\((local.relayProtocol ?? "udp").uppercased()) to the relay" }
        return (local.protocol ?? "udp").uppercased()
    }

    /// The loading screen's word for where the player is: `Home network` on `lan`, else
    /// `Remote`; nil while the path is not known.
    public static func networkLabel(_ path: String) -> String? {
        guard !path.isEmpty else { return nil }
        return path == "lan" ? "Home network" : "Remote"
    }

    /// Whether a check report should replace the one shown. The input channel is unordered, so a
    /// "probing" report can arrive after "done" (or after a later "probing"): it is stale, and
    /// would send the loading bar's label and the Network rows back. A client checks its link
    /// once.
    public static func supersedes(_ current: WireProtocol.Link?, _ next: WireProtocol.Link) -> Bool {
        guard let current else { return true }
        if current.state == WireProtocol.Link.done { return next.state == WireProtocol.Link.done }
        return next.state == WireProtocol.Link.done || next.elapsedMs >= current.elapsedMs
    }

    /// `18.2 Mbit/s`, or `850 kbit/s` under a megabit.
    public static func rateLabel(_ kbps: Int) -> String {
        kbps >= 1000 ? String(format: "%.1f Mbit/s", locale: posix, Double(kbps) / 1000) : "\(kbps) kbit/s"
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    private static let stopped = [
        "ceiling": "reached the ceiling",
        "steady": "settled",
        "trouble": "the link filled",
        "budget": "out of time",
        "unavailable": "could not measure",
        "off": "turned off",
    ]

    /// `18.2 Mbit/s in 0.6 s (reached the ceiling)`, `not measured`.
    public static func measuredLabel(_ link: WireProtocol.Link?) -> String {
        guard let link, link.state == WireProtocol.Link.done, link.stoppedBy != "off", link.stoppedBy != "unavailable",
              link.estimateKbps != 0
        else { return link?.stoppedBy == "off" ? "not measured (turned off)" : "not measured" }
        let why = stopped[link.stoppedBy] ?? link.stoppedBy
        let seconds = String(format: "%.1f", locale: posix, Double(link.elapsedMs) / 1000)
        return "\(rateLabel(link.estimateKbps)) in \(seconds) s (\(why))"
    }
}

extension WireProtocol {
    /// The stats overlay's Network rows: where the link goes and through what (this app's own
    /// view of the selected pair, shown with any worker), then what the worker measured before
    /// the stream started (`link`) and estimates now (`estimateKbps`; both blank with an older
    /// worker).
    public static func networkRows(local: IceCandidateStats?, remote: IceCandidateStats?, link: Link?,
                                   estimateKbps: Int) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let network = LinkLabels.networkLabel(link?.path ?? "") { rows.append(("Network", network)) }
        if let local { rows.append(("TURN server", local.isRelay ? "Yes" : "No")) }
        if let transport = LinkLabels.transportLabel(local) { rows.append(("Transport", transport)) }
        if let pair = LinkLabels.pairLabel(local, remote) { rows.append(("Path", pair)) }
        rows.append(("Measured at start", LinkLabels.measuredLabel(link)))
        if let link, link.state == Link.done, link.startKbps != 0 {
            rows.append(("Started at", LinkLabels.rateLabel(link.startKbps)))
        }
        if estimateKbps != 0 { rows.append(("Estimate now", LinkLabels.rateLabel(estimateKbps))) }
        return rows
    }
}
