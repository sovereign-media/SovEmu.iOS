// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct BootstrapQuery: GraphQLQuery {
    static let operationName: String = "Bootstrap"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query Bootstrap { bootstrapConfig { __typename signInAvailable address issuer webClientId deviceClientId authorizationEndpoint tokenEndpoint revocationEndpoint deviceAuthorizationEndpoint verificationUri passwordEndpoint } }"#
      ))

    public init() {}

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("bootstrapConfig", BootstrapConfig.self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        BootstrapQuery.Data.self
      ] }

      /// Where and how to sign in here. Works signed out: an app's first question, which also tells
      /// it a SovEmu server is at the address it was given.
      var bootstrapConfig: BootstrapConfig { __data["bootstrapConfig"] }

      /// BootstrapConfig
      ///
      /// Parent Type: `BootstrapConfig`
      nonisolated struct BootstrapConfig: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.BootstrapConfig }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("signInAvailable", Bool.self),
          .field("address", String.self),
          .field("issuer", String?.self),
          .field("webClientId", String?.self),
          .field("deviceClientId", String?.self),
          .field("authorizationEndpoint", String?.self),
          .field("tokenEndpoint", String?.self),
          .field("revocationEndpoint", String?.self),
          .field("deviceAuthorizationEndpoint", String?.self),
          .field("verificationUri", String?.self),
          .field("passwordEndpoint", String?.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          BootstrapQuery.Data.BootstrapConfig.self
        ] }

        /// Whether anything can sign in at this address. False when it is not one of
        /// `SovEmu__Http__PublicUrl`'s; then the rest is null, and `address` says what to add.
        var signInAvailable: Bool { __data["signInAvailable"] }
        /// The address the request reached, as `Host` named it.
        var address: String { __data["address"] }
        /// The OpenID Connect issuer for this address (discovery at
        /// `<issuer>/.well-known/openid-configuration`).
        var issuer: String? { __data["issuer"] }
        /// The web client's id: the authorization code flow with PKCE.
        var webClientId: String? { __data["webClientId"] }
        /// The devices' id: the device grant (a code shown on the screen and approved at
        /// `verificationUri`), and the password fallback. A TV signs in as it, and so does an app
        /// signing in with a code or a password.
        var deviceClientId: String? { __data["deviceClientId"] }
        var authorizationEndpoint: String? { __data["authorizationEndpoint"] }
        var tokenEndpoint: String? { __data["tokenEndpoint"] }
        var revocationEndpoint: String? { __data["revocationEndpoint"] }
        /// Where an app asks for a code to show (RFC 8628 device authorization).
        var deviceAuthorizationEndpoint: String? { __data["deviceAuthorizationEndpoint"] }
        /// Where a person approves that code, in a signed-in browser.
        var verificationUri: String? { __data["verificationUri"] }
        /// The apps' password fallback: a form post of `client_id`, `username`, `password` and
        /// `scope`, answered like the token endpoint. Null when `SovEmu__Authentication__PasswordSignIn` is off.
        var passwordEndpoint: String? { __data["passwordEndpoint"] }
      }
    }
  }

}