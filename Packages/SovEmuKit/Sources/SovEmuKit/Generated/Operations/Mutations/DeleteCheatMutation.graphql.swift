// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct DeleteCheatMutation: GraphQLMutation {
    static let operationName: String = "DeleteCheat"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation DeleteCheat($gameId: Int!, $cheatId: Int!) { deleteCheat(gameId: $gameId, cheatId: $cheatId) }"#
      ))

    public var gameId: Int32
    public var cheatId: Int32

    public init(
      gameId: Int32,
      cheatId: Int32
    ) {
      self.gameId = gameId
      self.cheatId = cheatId
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "gameId": gameId,
      "cheatId": cheatId
    ] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("deleteCheat", Bool.self, arguments: [
          "gameId": .variable("gameId"),
          "cheatId": .variable("cheatId")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        DeleteCheatMutation.Data.self
      ] }

      var deleteCheat: Bool { __data["deleteCheat"] }
    }
  }

}