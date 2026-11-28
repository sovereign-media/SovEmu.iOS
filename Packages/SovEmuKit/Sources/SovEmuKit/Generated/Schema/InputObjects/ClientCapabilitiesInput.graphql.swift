// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  /// Everything a client declares about what it can play: one complete document, sent whole with
  /// every `sessionOffer`. The server never reads a missing fact as permission.
  nonisolated struct ClientCapabilitiesInput: InputObject {
    private(set) var __data: InputDict

    init(_ data: InputDict) {
      __data = data
    }

    init(
      version: Int32,
      videoDecoders: [VideoDecoderInput],
      display: DisplayInput
    ) {
      __data = InputDict([
        "version": version,
        "videoDecoders": videoDecoders,
        "display": display
      ])
    }

    /// The document's shape: 1. A document of any other version is refused (`BAD_REQUEST`,
    /// with a message asking the player to update the app).
    var version: Int32 {
      get { __data["version"] }
      set { __data["version"] = newValue }
    }

    /// Every video codec the client can decode, one row each: the decoder it would use.
    var videoDecoders: [VideoDecoderInput] {
      get { __data["videoDecoders"] }
      set { __data["videoDecoders"] = newValue }
    }

    var display: DisplayInput {
      get { __data["display"] }
      set { __data["display"] = newValue }
    }
  }

}