// @generated
// This file was automatically generated and can be edited to
// implement advanced custom scalar functionality.
//
// Any changes to this file will not be overwritten by future
// code generation execution.

import Foundation
@_spi(Internal) @_spi(Execution) import ApolloAPI

extension SovEmuGraphQL {
    /// The schema's `JSON` scalar: any JSON value, kept as its encoded bytes so it can be decoded
    /// into a `Decodable` type (`clientConfig.iceServers` holds `RTCIceServer` objects).
    struct JSON: CustomScalarType, Hashable {
        /// The value as Apollo read it.
        let _jsonValue: JSONValue
        /// The same value, encoded as JSON.
        let data: Data

        init(_jsonValue value: JSONValue) throws {
            // Apollo hands over what `JSONSerialization` read, so it writes back the same way.
            guard JSONSerialization.isValidJSONObject([value]) else {
                throw JSONDecodingError.couldNotConvert(value: value, to: JSON.self)
            }
            _jsonValue = value
            data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        }

        static func == (a: JSON, b: JSON) -> Bool { a.data == b.data }
        func hash(into hasher: inout Hasher) { hasher.combine(data) }

        /// The value decoded as `T`.
        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            try JSONDecoder().decode(T.self, from: data)
        }
    }
}
