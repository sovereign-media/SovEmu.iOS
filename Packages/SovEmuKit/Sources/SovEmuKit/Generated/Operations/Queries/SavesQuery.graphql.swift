// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct SavesQuery: GraphQLQuery {
    static let operationName: String = "Saves"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query Saves($id: Int!) { game(id: $id) { __typename saves { __typename ...SaveFields } } }"#,
        fragments: [SaveFields.self]
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
        SavesQuery.Data.self
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
          .field("saves", [Safe].self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          SavesQuery.Data.Game.self
        ] }

        /// This user's save states (slot 0 is the auto save, written when a session ends).
        var saves: [Safe] { __data["saves"] }

        /// Game.Safe
        ///
        /// Parent Type: `SaveSlot`
        nonisolated struct Safe: SovEmuGraphQL.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.SaveSlot }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .fragment(SaveFields.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            SavesQuery.Data.Game.Safe.self,
            SaveFields.self
          ] }

          /// 0 is the auto save; 1–9 are the player's.
          var slot: Int { __data["slot"] }
          /// Unix seconds.
          var savedAt: Double { __data["savedAt"] }
          /// The screen when it was saved, if there is one: a URL signed for this user that changes
          /// with each save.
          var screenshotUrl: String? { __data["screenshotUrl"] }

          struct Fragments: FragmentContainer {
            let __data: DataDict
            init(_dataDict: DataDict) { __data = _dataDict }

            var saveFields: SaveFields { _toFragment() }
          }
        }
      }
    }
  }

}