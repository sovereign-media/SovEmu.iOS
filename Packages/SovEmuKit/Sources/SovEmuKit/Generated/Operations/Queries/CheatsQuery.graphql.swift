// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct CheatsQuery: GraphQLQuery {
    static let operationName: String = "Cheats"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query Cheats($id: Int!) { game(id: $id) { __typename cheats { __typename ...CheatFields } } }"#,
        fragments: [CheatFields.self]
      ))

    public var id: Int32

    public init(id: Int32) {
      self.id = id
    }

    @_spi(Unsafe) public var __variables: Variables? { ["id": id] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("game", Game.self, arguments: ["id": .variable("id")]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        CheatsQuery.Data.self
      ] }

      var game: Game { __data["game"] }

      /// Game
      ///
      /// Parent Type: `Game`
      nonisolated struct Game: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Game }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("cheats", [Cheat].self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          CheatsQuery.Data.Game.self
        ] }

        /// This user's cheats for it.
        var cheats: [Cheat] { __data["cheats"] }

        /// Game.Cheat
        ///
        /// Parent Type: `Cheat`
        nonisolated struct Cheat: SovEmuGraphQL.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Cheat }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .fragment(CheatFields.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            CheatsQuery.Data.Game.Cheat.self,
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

}