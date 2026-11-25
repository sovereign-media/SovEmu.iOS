// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct ClientConfigQuery: GraphQLQuery {
    static let operationName: String = "ClientConfig"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query ClientConfig { clientConfig { __typename iceServers } }"#
      ))

    public init() {}

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("clientConfig", ClientConfig.self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        ClientConfigQuery.Data.self
      ] }

      var clientConfig: ClientConfig { __data["clientConfig"] }

      /// ClientConfig
      ///
      /// Parent Type: `ClientConfig`
      nonisolated struct ClientConfig: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.ClientConfig }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("iceServers", SovEmuGraphQL.JSON.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ClientConfigQuery.Data.ClientConfig.self
        ] }

        /// `RTCIceServer` objects (STUN/TURN) for WebRTC, from `SovEmu__Streaming__IceServers`.
        var iceServers: SovEmuGraphQL.JSON { __data["iceServers"] }
      }
    }
  }

}