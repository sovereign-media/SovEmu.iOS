// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct GameDecorationQuery: GraphQLQuery {
    static let operationName: String = "GameDecoration"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query GameDecoration($id: Int!) { game(id: $id) { __typename decoration { __typename url width height top left bottom right } } }"#
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
        GameDecorationQuery.Data.self
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
          .field("decoration", Decoration?.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          GameDecorationQuery.Data.Game.self
        ] }

        /// The decoration (bezel) to draw around its picture: the set chosen for its system
        /// (`SovEmu__Decorations__Set`, `SovEmu__Systems__<id>__Decoration`), its own image there, else its
        /// system's, else the set's default. Null when the set is `none` or has nothing for it.
        var decoration: Decoration? { __data["decoration"] }

        /// Game.Decoration
        ///
        /// Parent Type: `Decoration`
        nonisolated struct Decoration: SovEmuGraphQL.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Decoration }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("url", String.self),
            .field("width", Int.self),
            .field("height", Int.self),
            .field("top", Int.self),
            .field("left", Int.self),
            .field("bottom", Int.self),
            .field("right", Int.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            GameDecorationQuery.Data.Game.Decoration.self
          ] }

          /// The image (PNG), under `/media/decorations/`: a URL signed for this user.
          var url: String { __data["url"] }
          /// Its size in pixels.
          var width: Int { __data["width"] }
          var height: Int { __data["height"] }
          /// The window's margins from the image's edges, in the image's pixels.
          var top: Int { __data["top"] }
          var left: Int { __data["left"] }
          var bottom: Int { __data["bottom"] }
          var right: Int { __data["right"] }
        }
      }
    }
  }

}