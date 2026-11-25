// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct StartProgressQuery: GraphQLQuery {
    static let operationName: String = "StartProgress"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query StartProgress($startId: String!) { startProgress(startId: $startId) { __typename phase read total elapsedMs phaseMs error } }"#
      ))

    public var startId: String

    public init(startId: String) {
      self.startId = startId
    }

    @_spi(Unsafe) public var __variables: Variables? { ["startId": startId] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("startProgress", StartProgress.self, arguments: ["startId": .variable("startId")]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        StartProgressQuery.Data.self
      ] }

      /// How far the start `startId` (given to `startSession`) has got. Poll it while
      /// `startSession` waits.
      var startProgress: StartProgress { __data["startProgress"] }

      /// StartProgress
      ///
      /// Parent Type: `StartStatus`
      nonisolated struct StartProgress: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.StartStatus }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("phase", GraphQLEnum<SovEmuGraphQL.StartPhase>.self),
          .field("read", Double?.self),
          .field("total", Double?.self),
          .field("elapsedMs", Double.self),
          .field("phaseMs", Double.self),
          .field("error", String?.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          StartProgressQuery.Data.StartProgress.self
        ] }

        var phase: GraphQLEnum<SovEmuGraphQL.StartPhase> { __data["phase"] }
        /// Bytes read so far in this phase, where known.
        var read: Double? { __data["read"] }
        /// Bytes this phase will read, when known.
        var total: Double? { __data["total"] }
        /// Since the start began.
        var elapsedMs: Double { __data["elapsedMs"] }
        /// Since this phase began.
        var phaseMs: Double { __data["phaseMs"] }
        var error: String? { __data["error"] }
      }
    }
  }

}