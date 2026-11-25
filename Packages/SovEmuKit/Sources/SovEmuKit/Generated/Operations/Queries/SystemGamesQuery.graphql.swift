// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct SystemGamesQuery: GraphQLQuery {
    static let operationName: String = "SystemGames"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query SystemGames($id: ID!) { system(id: $id) { __typename games { __typename ...GameFields } } }"#,
        fragments: [GameFields.self, SaveFields.self]
      ))

    public var id: ID

    public init(id: ID) {
      self.id = id
    }

    @_spi(Unsafe) public var __variables: Variables? { ["id": id] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("system", System?.self, arguments: ["id": .variable("id")]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SystemGamesQuery.Data.self
      ] }

      var system: System? { __data["system"] }

      /// System
      ///
      /// Parent Type: `System`
      nonisolated struct System: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.System }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("games", [Game].self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          SystemGamesQuery.Data.System.self
        ] }

        /// Its games, by title.
        var games: [Game] { __data["games"] }

        /// System.Game
        ///
        /// Parent Type: `Game`
        nonisolated struct Game: SovEmuGraphQL.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Game }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .fragment(GameFields.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            SystemGamesQuery.Data.System.Game.self,
            GameFields.self
          ] }

          var id: Int { __data["id"] }
          /// The system's id.
          var system: String { __data["system"] }
          var title: String { __data["title"] }
          /// The title from the file name, when game information supplied a better `title`.
          var fileTitle: String? { __data["fileTitle"] }
          /// No-Intro tags from the file name: "USA", "Rev 1" …
          var tags: [String] { __data["tags"] }
          /// The file, relative to the library.
          var path: String { __data["path"] }
          /// Bytes.
          var size: Double { __data["size"] }
          /// When this user last played it (UTC, `YYYY-MM-DD HH:MM:SS`).
          var lastPlayedAt: String? { __data["lastPlayedAt"] }
          var playCount: Int { __data["playCount"] }
          /// Where to load a kind of artwork from, if the game has it: a URL signed for this user
          /// (valid `SovEmu__Assets__UrlHours`; ask again for a fresh one). With `width` (the box it is
          /// shown in, in device pixels), a lossy WebP copy at most that wide: the width is rounded up
          /// to the grid copies are made on (16 px steps, from 144), and a picture narrower than it is
          /// not enlarged. Without it, the original. Videos are always the original.
          var image: String? { __data["image"] }
          /// Where to load a kind of artwork from, if the game has it: a URL signed for this user
          /// (valid `SovEmu__Assets__UrlHours`; ask again for a fresh one). With `width` (the box it is
          /// shown in, in device pixels), a lossy WebP copy at most that wide: the width is rounded up
          /// to the grid copies are made on (16 px steps, from 144), and a picture narrower than it is
          /// not enlarged. Without it, the original. Videos are always the original.
          var imageSmall: String? { __data["imageSmall"] }
          /// Where to load a kind of artwork from, if the game has it: a URL signed for this user
          /// (valid `SovEmu__Assets__UrlHours`; ask again for a fresh one). With `width` (the box it is
          /// shown in, in device pixels), a lossy WebP copy at most that wide: the width is rounded up
          /// to the grid copies are made on (16 px steps, from 144), and a picture narrower than it is
          /// not enlarged. Without it, the original. Videos are always the original.
          var cover: String? { __data["cover"] }
          /// Where to load a kind of artwork from, if the game has it: a URL signed for this user
          /// (valid `SovEmu__Assets__UrlHours`; ask again for a fresh one). With `width` (the box it is
          /// shown in, in device pixels), a lossy WebP copy at most that wide: the width is rounded up
          /// to the grid copies are made on (16 px steps, from 144), and a picture narrower than it is
          /// not enlarged. Without it, the original. Videos are always the original.
          var thumb: String? { __data["thumb"] }
          /// Where to load a kind of artwork from, if the game has it: a URL signed for this user
          /// (valid `SovEmu__Assets__UrlHours`; ask again for a fresh one). With `width` (the box it is
          /// shown in, in device pixels), a lossy WebP copy at most that wide: the width is rounded up
          /// to the grid copies are made on (16 px steps, from 144), and a picture narrower than it is
          /// not enlarged. Without it, the original. Videos are always the original.
          var video: String? { __data["video"] }
          var description: String? { __data["description"] }
          /// `YYYY-MM-DD`, `YYYY-MM` or `YYYY`.
          var releaseDate: String? { __data["releaseDate"] }
          var developer: String? { __data["developer"] }
          var publisher: String? { __data["publisher"] }
          var genre: String? { __data["genre"] }
          /// Its genres, as `genre` lists them.
          var genres: [String] { __data["genres"] }
          /// As the game information says it: "1", "1-2", "1 to 4" …
          var players: String? { __data["players"] }
          /// 0 to 1.
          var rating: Double? { __data["rating"] }
          /// The ESRB's age rating, if the game information has one.
          var esrb: GraphQLEnum<SovEmuGraphQL.EsrbRating>? { __data["esrb"] }
          /// The ESRB rating's icon (PNG), if the game has a rating and there is an icon for it:
          /// `artwork/ratings/esrb/<rating>.png`, the admin's own in the data folder, else the
          /// built-in one. A URL signed for this user.
          var esrbBadgeUrl: String? { __data["esrbBadgeUrl"] }
          /// Ways to play: "Single player", "Multiplayer (simultaneous)" …
          var modes: [String] { __data["modes"] }
          /// The series and families it belongs to: "Castlevania" …
          var series: [String] { __data["series"] }
          /// Its themes: "Horror", "Fantasy" …
          var themes: [String] { __data["themes"] }
          /// How many discs (1 for most games): a multi-disc game is one entry, its discs changed in play.
          var discs: Int { __data["discs"] }
          /// What its several files are (discs, disks, tapes, sides or parts), shown with its count
          /// (`discs`). Null for a game in one file.
          var partKind: GraphQLEnum<SovEmuGraphQL.PartKind>? { __data["partKind"] }
          /// One of this user's favourites.
          var favourite: Bool { __data["favourite"] }
          /// What tells it apart from games of the same title on its system: the tags they do not
          /// share ("Translation", "Rev 1"), else its file's own title. Null when its title is its own.
          var release: String? { __data["release"] }
          /// The soft patch this user plays it with (a translation, a fix, a hack), by name: their
          /// choice, else the patch beside it with its name. Null: the original.
          var patch: String? { __data["patch"] }
          /// The auto save, if there is one: where this user left off.
          var autoSave: AutoSave? { __data["autoSave"] }

          struct Fragments: FragmentContainer {
            let __data: DataDict
            init(_dataDict: DataDict) { __data = _dataDict }

            var gameFields: GameFields { _toFragment() }
          }

          typealias AutoSave = GameFields.AutoSave
        }
      }
    }
  }

}