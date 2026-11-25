// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct CollectionChoicesQuery: GraphQLQuery {
    static let operationName: String = "CollectionChoices"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query CollectionChoices($id: Int!) { collections { __typename id name } game(id: $id) { __typename collectionIds } }"#
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
        .field("collections", [Collection].self),
        .field("game", Game.self, arguments: ["id": .variable("id")]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        CollectionChoicesQuery.Data.self
      ] }

      /// This user's collections, by name.
      var collections: [Collection] { __data["collections"] }
      var game: Game { __data["game"] }

      /// Collection
      ///
      /// Parent Type: `Collection`
      nonisolated struct Collection: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Collection }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", Int.self),
          .field("name", String.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          CollectionChoicesQuery.Data.Collection.self
        ] }

        var id: Int { __data["id"] }
        var name: String { __data["name"] }
      }

      /// Game
      ///
      /// Parent Type: `Game`
      nonisolated struct Game: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Game }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("collectionIds", [Int].self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          CollectionChoicesQuery.Data.Game.self
        ] }

        /// The ids of this user's collections that hold it.
        var collectionIds: [Int] { __data["collectionIds"] }
      }
    }
  }

}