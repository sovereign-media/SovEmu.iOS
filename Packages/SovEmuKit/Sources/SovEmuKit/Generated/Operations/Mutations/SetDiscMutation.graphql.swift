// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct SetDiscMutation: GraphQLMutation {
    static let operationName: String = "SetDisc"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation SetDisc($sessionId: ID!, $disc: Int!) { setDisc(sessionId: $sessionId, disc: $disc) }"#
      ))

    public var sessionId: ID
    public var disc: Int32

    public init(
      sessionId: ID,
      disc: Int32
    ) {
      self.sessionId = sessionId
      self.disc = disc
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "sessionId": sessionId,
      "disc": disc
    ] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("setDisc", Bool.self, arguments: [
          "sessionId": .variable("sessionId"),
          "disc": .variable("disc")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SetDiscMutation.Data.self
      ] }

      /// Changes a multi-disc game's disc (from 1), as when the game asks for the next one.
      var setDisc: Bool { __data["setDisc"] }
    }
  }

}