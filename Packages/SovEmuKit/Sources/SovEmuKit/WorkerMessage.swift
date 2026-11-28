import Foundation
import Synchronization

// What the worker sends on the input channel, read by its first byte as SovEmu.Android's
// `Stream.received` and SovEmu.Web's session do: acks (`0x81`, with every frame that took
// input), the pipeline (`0x82`) and the check of the connection (`0x83`). A type or version this
// app does not know (a newer worker's) is counted and ignored, never mistaken for another.

extension WireProtocol {
    /// One message from the worker.
    public enum WorkerMessage: Equatable, Sendable {
        case ack(Ack)
        case pipeline(Pipeline)
        case link(Link)
        /// A type, or a version of one, this app does not know: ignored.
        case unknown(type: UInt8, version: UInt8)
        /// A type this app knows that does not decode (cut short, too long, a body of the wrong
        /// shape): ignored.
        case malformed(type: UInt8)
    }

    /// Reads a message by its type byte, then its version; only the one decoder it names runs.
    /// An ack, the common case, is read in place.
    public static func decodeWorkerMessage(_ data: Data) -> WorkerMessage {
        guard data.count >= 2 else { return .malformed(type: data.first ?? 0) }
        let type = data[data.startIndex]
        let version = data[data.startIndex + 1]
        guard version == inputVersion else { return .unknown(type: type, version: version) }
        switch type {
        case typeAck:
            guard data.count >= 14 else { return .malformed(type: type) }
            func u32(_ at: Int) -> UInt32 {
                let i = data.startIndex + at
                return UInt32(data[i]) | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2]) << 16 | UInt32(data[i + 3]) << 24
            }
            return .ack(Ack(seq: u32(2), clientTimeMs: u32(6), frame: u32(10)))
        case typePipeline:
            return decodePipeline(data).map(WorkerMessage.pipeline) ?? .malformed(type: type)
        case typeLink:
            return decodeLink(data).map(WorkerMessage.link) ?? .malformed(type: type)
        default:
            return .unknown(type: type, version: version)
        }
    }
}

/// How many messages of each kind this app did not know (type and version), for a newer
/// worker's sake: ignored, and each kind said once. Counted on WebRTC's data channel thread,
/// read on any, so behind a Mutex.
public final class UnknownMessages: Sendable {
    /// One kind: its type and version, and how many came.
    public struct Kind: Equatable, Sendable {
        public let type: UInt8
        public let version: UInt8
        public let count: Int
    }

    private let seen = Mutex<[UInt16: Int]>([:])

    public init() {}

    /// Counts one; true for the first of its kind, which is the one to log.
    @discardableResult
    public func add(type: UInt8, version: UInt8) -> Bool {
        let key = UInt16(type) << 8 | UInt16(version)
        return seen.withLock { counts in
            counts[key, default: 0] += 1
            return counts[key] == 1
        }
    }

    /// Every kind seen, by type then version.
    public func kinds() -> [Kind] {
        seen.withLock { counts in
            counts.keys.sorted().map { Kind(type: UInt8($0 >> 8), version: UInt8($0 & 0xff), count: counts[$0] ?? 0) }
        }
    }

    /// All the unknown messages so far.
    public var total: Int { seen.withLock { $0.values.reduce(0, +) } }
}
