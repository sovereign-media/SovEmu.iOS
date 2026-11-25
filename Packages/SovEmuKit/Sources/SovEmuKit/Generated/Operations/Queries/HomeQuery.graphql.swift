// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct HomeQuery: GraphQLQuery {
    static let operationName: String = "Home"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query Home { home { __typename featured { __typename ...GameFields } recent { __typename ...GameFields } added { __typename ...GameFields } topRated { __typename ...GameFields } favourites { __typename ...GameFields } } collections { __typename id name games { __typename ...GameFields } } }"#,
        fragments: [GameFields.self, SaveFields.self]
      ))

    public init() {}

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("home", Home.self),
        .field("collections", [Collection].self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        HomeQuery.Data.self
      ] }

      /// The home screen's feed.
      var home: Home { __data["home"] }
      /// This user's collections, by name.
      var collections: [Collection] { __data["collections"] }

      /// Home
      ///
      /// Parent Type: `Home`
      nonisolated struct Home: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Home }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("featured", [Featured].self),
          .field("recent", [Recent].self),
          .field("added", [Added].self),
          .field("topRated", [TopRated].self),
          .field("favourites", [Favourite].self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          HomeQuery.Data.Home.self
        ] }

        /// The hero: games with artwork and a description first, a new pick each day.
        var featured: [Featured] { __data["featured"] }
        /// This user's games, most recently played first.
        var recent: [Recent] { __data["recent"] }
        /// The library's newest games.
        var added: [Added] { __data["added"] }
        /// The library's best rated games (`Game.rating`), best first.
        var topRated: [TopRated] { __data["topRated"] }
        /// This user's favourites, by title.
        var favourites: [Favourite] { __data["favourites"] }

        /// Home.Featured
        ///
        /// Parent Type: `Game`
        nonisolated struct Featured: SovEmuGraphQL.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Game }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .fragment(GameFields.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            HomeQuery.Data.Home.Featured.self,
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

        /// Home.Recent
        ///
        /// Parent Type: `Game`
        nonisolated struct Recent: SovEmuGraphQL.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Game }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .fragment(GameFields.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            HomeQuery.Data.Home.Recent.self,
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

        /// Home.Added
        ///
        /// Parent Type: `Game`
        nonisolated struct Added: SovEmuGraphQL.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Game }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .fragment(GameFields.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            HomeQuery.Data.Home.Added.self,
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

        /// Home.TopRated
        ///
        /// Parent Type: `Game`
        nonisolated struct TopRated: SovEmuGraphQL.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Game }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .fragment(GameFields.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            HomeQuery.Data.Home.TopRated.self,
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

        /// Home.Favourite
        ///
        /// Parent Type: `Game`
        nonisolated struct Favourite: SovEmuGraphQL.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Game }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .fragment(GameFields.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            HomeQuery.Data.Home.Favourite.self,
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
          .field("games", [Game].self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          HomeQuery.Data.Collection.self
        ] }

        var id: Int { __data["id"] }
        var name: String { __data["name"] }
        /// Its games, most recently added first.
        var games: [Game] { __data["games"] }

        /// Collection.Game
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
            HomeQuery.Data.Collection.Game.self,
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