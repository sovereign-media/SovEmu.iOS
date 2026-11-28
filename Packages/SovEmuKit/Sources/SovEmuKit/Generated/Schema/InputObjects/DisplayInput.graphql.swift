// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  /// The screen a client shows games on.
  nonisolated struct DisplayInput: InputObject {
    private(set) var __data: InputDict

    init(_ data: InputDict) {
      __data = data
    }

    init(
      width: Int32,
      height: Int32,
      refreshHz: Double
    ) {
      __data = InputDict([
        "width": width,
        "height": height,
        "refreshHz": refreshHz
      ])
    }

    /// In physical pixels.
    var width: Int32 {
      get { __data["width"] }
      set { __data["width"] = newValue }
    }

    var height: Int32 {
      get { __data["height"] }
      set { __data["height"] = newValue }
    }

    /// Pictures a second.
    var refreshHz: Double {
      get { __data["refreshHz"] }
      set { __data["refreshHz"] = newValue }
    }
  }

}