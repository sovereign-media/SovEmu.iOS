// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct SetCheatEnabledMutation: GraphQLMutation {
    static let operationName: String = "SetCheatEnabled"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation SetCheatEnabled($gameId: Int!, $cheatId: Int!, $enabled: Boolean!) { setCheatEnabled(gameId: $gameId, cheatId: $cheatId, enabled: $enabled) { __typename ...CheatFields } }"#,
        fragments: [CheatFields.self]
      ))

    public var gameId: Int32
    public var cheatId: Int32
    public var enabled: Bool

    public init(
      gameId: Int32,
      cheatId: Int32,
      enabled: Bool
    ) {
      self.gameId = gameId
      self.cheatId = cheatId
      self.enabled = enabled
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "gameId": gameId,
      "cheatId": cheatId,
      "enabled": enabled
    ] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("setCheatEnabled", [SetCheatEnabled].self, arguments: [
          "gameId": .variable("gameId"),
          "cheatId": .variable("cheatId"),
          "enabled": .variable("enabled")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SetCheatEnabledMutation.Data.self
      ] }

      /// Turns a cheat on or off; returns the game's cheats.
      var setCheatEnabled: [SetCheatEnabled] { __data["setCheatEnabled"] }

      /// SetCheatEnabled
      ///
      /// Parent Type: `Cheat`
      nonisolated struct SetCheatEnabled: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Cheat }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(CheatFields.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          SetCheatEnabledMutation.Data.SetCheatEnabled.self,
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