// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct SessionOfferMutation: GraphQLMutation {
    static let operationName: String = "SessionOffer"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation SessionOffer($id: ID!, $sdp: String!, $client: String, $capabilities: ClientCapabilitiesInput) { sessionOffer(id: $id, sdp: $sdp, client: $client, capabilities: $capabilities) }"#
      ))

    public var id: ID
    public var sdp: String
    public var client: GraphQLNullable<String>
    public var capabilities: GraphQLNullable<ClientCapabilitiesInput>

    public init(
      id: ID,
      sdp: String,
      client: GraphQLNullable<String>,
      capabilities: GraphQLNullable<ClientCapabilitiesInput>
    ) {
      self.id = id
      self.sdp = sdp
      self.client = client
      self.capabilities = capabilities
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "id": id,
      "sdp": sdp,
      "client": client,
      "capabilities": capabilities
    ] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("sessionOffer", String.self, arguments: [
          "id": .variable("id"),
          "sdp": .variable("sdp"),
          "client": .variable("client"),
          "capabilities": .variable("capabilities")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SessionOfferMutation.Data.self
      ] }

      /// Answers a client's WebRTC offer (SDP) for a session with the worker's answer (SDP).
      /// `client` names the app and device (`web`, `android 1.4.0 (Mi TV)`), as its stats do,
      /// for the admin's sessions page. `capabilities` is what the client can decode and show:
      /// the whole document, every time. It is kept against the sign-in's device; `BAD_REQUEST`
      /// for one of another version (the message asks the player to update the app) or one that
      /// does not hold together.
      var sessionOffer: String { __data["sessionOffer"] }
    }
  }

}