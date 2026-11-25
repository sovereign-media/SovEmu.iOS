// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  /// One thing that went wrong on a client.
  nonisolated struct ClientEventInput: InputObject {
    private(set) var __data: InputDict

    init(_ data: InputDict) {
      __data = data
    }

    init(
      kind: GraphQLEnum<ClientEventKind>,
      message: String,
      sessionId: GraphQLNullable<ID> = nil,
      at: GraphQLNullable<Double> = nil
    ) {
      __data = InputDict([
        "kind": kind,
        "message": message,
        "sessionId": sessionId,
        "at": at
      ])
    }

    var kind: GraphQLEnum<ClientEventKind> {
      get { __data["kind"] }
      set { __data["kind"] = newValue }
    }

    /// What happened, in a line (kept to 500 characters).
    var message: String {
      get { __data["message"] }
      set { __data["message"] = newValue }
    }

    /// The game session it happened in, if any.
    var sessionId: GraphQLNullable<ID> {
      get { __data["sessionId"] }
      set { __data["sessionId"] = newValue }
    }

    /// When, in seconds since the Unix epoch on the client's clock.
    var at: GraphQLNullable<Double> {
      get { __data["at"] }
      set { __data["at"] = newValue }
    }
  }

}