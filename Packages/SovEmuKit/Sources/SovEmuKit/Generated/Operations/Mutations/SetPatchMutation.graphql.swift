// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct SetPatchMutation: GraphQLMutation {
    static let operationName: String = "SetPatch"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation SetPatch($gameId: Int!, $patchId: Int) { setPatch(gameId: $gameId, patchId: $patchId) }"#
      ))

    public var gameId: Int32
    public var patchId: GraphQLNullable<Int32>

    public init(
      gameId: Int32,
      patchId: GraphQLNullable<Int32>
    ) {
      self.gameId = gameId
      self.patchId = patchId
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "gameId": gameId,
      "patchId": patchId
    ] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("setPatch", Bool.self, arguments: [
          "gameId": .variable("gameId"),
          "patchId": .variable("patchId")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SetPatchMutation.Data.self
      ] }

      var setPatch: Bool { __data["setPatch"] }
    }
  }

}