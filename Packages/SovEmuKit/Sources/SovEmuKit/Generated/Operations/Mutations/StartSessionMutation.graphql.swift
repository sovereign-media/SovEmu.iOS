// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct StartSessionMutation: GraphQLMutation {
    static let operationName: String = "StartSession"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation StartSession($gameId: Int!, $startId: String, $slot: Int) { startSession(gameId: $gameId, startId: $startId, slot: $slot) { __typename ...SessionFields } }"#,
        fragments: [SessionFields.self]
      ))

    public var gameId: Int32
    public var startId: GraphQLNullable<String>
    public var slot: GraphQLNullable<Int32>

    public init(
      gameId: Int32,
      startId: GraphQLNullable<String>,
      slot: GraphQLNullable<Int32>
    ) {
      self.gameId = gameId
      self.startId = startId
      self.slot = slot
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "gameId": gameId,
      "startId": startId,
      "slot": slot
    ] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("startSession", StartSession.self, arguments: [
          "gameId": .variable("gameId"),
          "startId": .variable("startId"),
          "slot": .variable("slot")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        StartSessionMutation.Data.self
      ] }

      /// Starts a game (ending this user's running one first) and returns once it is ready to
      /// stream. Give a `startId` (8–64 letters, digits, `-` or `_`) to follow its progress with
      /// `startProgress` meanwhile. Give a `slot` to continue from that save state: it is loaded
      /// as the game starts, as `loadState` would, without a request of its own before the
      /// client connects. A state that cannot be loaded is logged and the game starts afresh.
      var startSession: StartSession { __data["startSession"] }

      /// StartSession
      ///
      /// Parent Type: `GameSession`
      nonisolated struct StartSession: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.GameSession }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(SessionFields.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          StartSessionMutation.Data.StartSession.self,
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

        struct Fragments: FragmentContainer {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          var sessionFields: SessionFields { _toFragment() }
        }
      }
    }
  }

}