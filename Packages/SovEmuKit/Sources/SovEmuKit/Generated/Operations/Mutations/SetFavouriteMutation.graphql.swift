// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct SetFavouriteMutation: GraphQLMutation {
    static let operationName: String = "SetFavourite"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation SetFavourite($gameId: Int!, $favourite: Boolean!) { setFavourite(gameId: $gameId, favourite: $favourite) }"#
      ))

    public var gameId: Int32
    public var favourite: Bool

    public init(
      gameId: Int32,
      favourite: Bool
    ) {
      self.gameId = gameId
      self.favourite = favourite
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "gameId": gameId,
      "favourite": favourite
    ] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("setFavourite", Bool.self, arguments: [
          "gameId": .variable("gameId"),
          "favourite": .variable("favourite")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SetFavouriteMutation.Data.self
      ] }

      /// Adds a game to this user's favourites, or takes it out.
      var setFavourite: Bool { __data["setFavourite"] }
    }
  }

}