// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct SetInCollectionMutation: GraphQLMutation {
    static let operationName: String = "SetInCollection"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation SetInCollection($collectionId: Int!, $gameId: Int!, $member: Boolean!) { setInCollection(collectionId: $collectionId, gameId: $gameId, member: $member) }"#
      ))

    public var collectionId: Int32
    public var gameId: Int32
    public var member: Bool

    public init(
      collectionId: Int32,
      gameId: Int32,
      member: Bool
    ) {
      self.collectionId = collectionId
      self.gameId = gameId
      self.member = member
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "collectionId": collectionId,
      "gameId": gameId,
      "member": member
    ] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("setInCollection", Bool.self, arguments: [
          "collectionId": .variable("collectionId"),
          "gameId": .variable("gameId"),
          "member": .variable("member")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SetInCollectionMutation.Data.self
      ] }

      /// Puts a game in one of this user's collections, or takes it out.
      var setInCollection: Bool { __data["setInCollection"] }
    }
  }

}