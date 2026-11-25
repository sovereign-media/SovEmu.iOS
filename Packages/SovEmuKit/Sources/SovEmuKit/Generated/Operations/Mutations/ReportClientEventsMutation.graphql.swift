// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct ReportClientEventsMutation: GraphQLMutation {
    static let operationName: String = "ReportClientEvents"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation ReportClientEvents($client: String!, $events: [ClientEventInput!]!) { reportClientEvents(client: $client, events: $events) }"#
      ))

    public var client: String
    public var events: [ClientEventInput]

    public init(
      client: String,
      events: [ClientEventInput]
    ) {
      self.client = client
      self.events = events
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "client": client,
      "events": events
    ] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("reportClientEvents", Int.self, arguments: [
          "client": .variable("client"),
          "events": .variable("events")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        ReportClientEventsMutation.Data.self
      ] }

      /// Signed-in users: what went wrong on this client (a connection that failed, a stalled
      /// picture, a screen that crashed), for the server's log beside the session's own lines and
      /// the admin's Client errors page. `client` names it and its version (`android 0.1.0
      /// (MiTV-AFMU1, Android 11)`). At most 20 events a call and 60 a minute per user; the rest
      /// are dropped. Returns how many were taken (0 when `SovEmu__ClientErrors__Enabled` is off).
      var reportClientEvents: Int { __data["reportClientEvents"] }
    }
  }

}