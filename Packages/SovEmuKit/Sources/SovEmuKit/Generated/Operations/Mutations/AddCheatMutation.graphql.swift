// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct AddCheatMutation: GraphQLMutation {
    static let operationName: String = "AddCheat"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation AddCheat($gameId: Int!, $code: String!, $description: String!) { addCheat(gameId: $gameId, code: $code, description: $description) { __typename ...CheatFields } }"#,
        fragments: [CheatFields.self]
      ))

    public var gameId: Int32
    public var code: String
    public var description: String

    public init(
      gameId: Int32,
      code: String,
      description: String
    ) {
      self.gameId = gameId
      self.code = code
      self.description = description
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "gameId": gameId,
      "code": code,
      "description": description
    ] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("addCheat", [AddCheat].self, arguments: [
          "gameId": .variable("gameId"),
          "code": .variable("code"),
          "description": .variable("description")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        AddCheatMutation.Data.self
      ] }

      /// Adds a cheat (on) for a game; returns the game's cheats. A running session gets it.
      var addCheat: [AddCheat] { __data["addCheat"] }

      /// AddCheat
      ///
      /// Parent Type: `Cheat`
      nonisolated struct AddCheat: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Cheat }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(CheatFields.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          AddCheatMutation.Data.AddCheat.self,
          CheatFields.self
        ] }

        var id: Int { __data["id"] }
        var description: String { __data["description"] }
        var code: String { __data["code"] }
        var enabled: Bool { __data["enabled"] }

        struct Fragments: FragmentContainer {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          var cheatFields: CheatFields { _toFragment() }
        }
      }
    }
  }

}