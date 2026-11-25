// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct PatchesQuery: GraphQLQuery {
    static let operationName: String = "Patches"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query Patches($id: Int!) { game(id: $id) { __typename patches { __typename id name isDefault } } }"#
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
        PatchesQuery.Data.self
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
          .field("patches", [Patch].self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          PatchesQuery.Data.Game.self
        ] }

        /// The soft patches found with it (IPS, UPS or BPS, beside it with its name or in a folder
        /// named as it), the default first. Choose one with `setPatch`.
        var patches: [Patch] { __data["patches"] }

        /// Game.Patch
        ///
        /// Parent Type: `Patch`
        nonisolated struct Patch: SovEmuGraphQL.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Patch }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("id", Int.self),
            .field("name", String.self),
            .field("isDefault", Bool.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            PatchesQuery.Data.Game.Patch.self
          ] }

          var id: Int { __data["id"] }
          /// From its file: "BPS patch" beside the game, else the file's name ("English v1.1").
          var name: String { __data["name"] }
          /// Applied unless the player chose otherwise (it is beside the game, with its name).
          var isDefault: Bool { __data["isDefault"] }
        }
      }
    }
  }

}