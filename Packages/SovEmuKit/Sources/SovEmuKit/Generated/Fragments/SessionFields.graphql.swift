// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct SessionFields: SovEmuGraphQL.SelectionSet, Fragment {
    static var fragmentDefinition: StaticString {
      #"fragment SessionFields on GameSession { __typename id gameId system title core width height fps connected discs disc }"#
    }

    let __data: DataDict
    init(_dataDict: DataDict) { __data = _dataDict }

    static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.GameSession }
    static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("id", SovEmuGraphQL.ID.self),
      .field("gameId", Int.self),
      .field("system", String.self),
      .field("title", String.self),
      .field("core", String.self),
      .field("width", Int.self),
      .field("height", Int.self),
      .field("fps", Double.self),
      .field("connected", Bool.self),
      .field("discs", Int.self),
      .field("disc", Int.self),
    ] }
    static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      SessionFields.self
    ] }

    var id: SovEmuGraphQL.ID { __data["id"] }
    var gameId: Int { __data["gameId"] }
    var system: String { __data["system"] }
    var title: String { __data["title"] }
    /// The core's name.
    var core: String { __data["core"] }
    var width: Int { __data["width"] }
    var height: Int { __data["height"] }
    var fps: Double { __data["fps"] }
    /// A client is streaming it.
    var connected: Bool { __data["connected"] }
    /// How many discs the game has (1 for most games).
    var discs: Int { __data["discs"] }
    /// The disc in the tray, from 1.
    var disc: Int { __data["disc"] }
  }

}