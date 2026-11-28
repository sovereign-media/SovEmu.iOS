// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  /// How a client decodes one codec: the decoder it would use for a game's stream.
  nonisolated struct VideoDecoderInput: InputObject {
    private(set) var __data: InputDict

    init(_ data: InputDict) {
      __data = data
    }

    init(
      codec: GraphQLEnum<VideoCodec>,
      hardware: Bool,
      lowLatency: Bool,
      name: GraphQLNullable<String> = nil
    ) {
      __data = InputDict([
        "codec": codec,
        "hardware": hardware,
        "lowLatency": lowLatency,
        "name": name
      ])
    }

    var codec: GraphQLEnum<VideoCodec> {
      get { __data["codec"] }
      set { __data["codec"] = newValue }
    }

    /// The device's hardware decodes it; false for a decoder that runs on the CPU.
    var hardware: Bool {
      get { __data["hardware"] }
      set { __data["hardware"] = newValue }
    }

    /// The decoder hands over each frame as soon as it is decoded, holding none back.
    var lowLatency: Bool {
      get { __data["lowLatency"] }
      set { __data["lowLatency"] = newValue }
    }

    /// The decoder's own name (`c2.amlogic.avc.decoder`, `libvpx`), for logs and the admin's
    /// view: nothing is decided from it. Kept to 80 characters.
    var name: GraphQLNullable<String> {
      get { __data["name"] }
      set { __data["name"] = newValue }
    }
  }

}