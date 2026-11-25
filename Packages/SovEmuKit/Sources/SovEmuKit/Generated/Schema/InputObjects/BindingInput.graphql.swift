// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  /// One input driving one button.
  nonisolated struct BindingInput: InputObject {
    private(set) var __data: InputDict

    init(_ data: InputDict) {
      __data = data
    }

    init(
      input: String,
      button: GraphQLEnum<PadButton>
    ) {
      __data = InputDict([
        "input": input,
        "button": button
      ])
    }

    /// A controller input (`south`, `l1`, `up` …) or a keyboard's `KeyboardEvent.code`.
    var input: String {
      get { __data["input"] }
      set { __data["input"] = newValue }
    }

    var button: GraphQLEnum<PadButton> {
      get { __data["button"] }
      set { __data["button"] = newValue }
    }
  }

}