// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct SaveStateMutation: GraphQLMutation {
    static let operationName: String = "SaveState"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation SaveState($sessionId: ID!, $slot: Int!) { saveState(sessionId: $sessionId, slot: $slot) }"#
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
        .field("saveState", Bool.self, arguments: [
          "sessionId": .variable("sessionId"),
          "slot": .variable("slot")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SaveStateMutation.Data.self
      ] }

      /// Saves the session's game to a slot (1–9), with a screenshot.
      var saveState: Bool { __data["saveState"] }
    }
  }

}