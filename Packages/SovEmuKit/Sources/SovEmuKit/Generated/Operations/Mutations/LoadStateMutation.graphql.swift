// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct LoadStateMutation: GraphQLMutation {
    static let operationName: String = "LoadState"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation LoadState($sessionId: ID!, $slot: Int!) { loadState(sessionId: $sessionId, slot: $slot) }"#
      ))

    public var sessionId: ID
    public var slot: Int32

    public init(
      sessionId: ID,
      slot: Int32
    ) {
      self.sessionId = sessionId
      self.slot = slot
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "sessionId": sessionId,
      "slot": slot
    ] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("loadState", Bool.self, arguments: [
          "sessionId": .variable("sessionId"),
          "slot": .variable("slot")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        LoadStateMutation.Data.self
      ] }

      /// Loads a slot (0 is the auto save) into the session's game.
      var loadState: Bool { __data["loadState"] }
    }
  }

}