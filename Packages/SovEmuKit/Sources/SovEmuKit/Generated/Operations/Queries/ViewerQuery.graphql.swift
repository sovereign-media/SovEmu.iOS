// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct ViewerQuery: GraphQLQuery {
    static let operationName: String = "Viewer"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query Viewer { viewer { __typename setupRequired user { __typename ...UserFields } } }"#,
        fragments: [UserFields.self]
      ))

    public init() {}

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("viewer", Viewer.self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        ViewerQuery.Data.self
      ] }

      /// Who is signed in, and whether first-run setup is needed. Works signed out.
      var viewer: Viewer { __data["viewer"] }

      /// Viewer
      ///
      /// Parent Type: `Viewer`
      nonisolated struct Viewer: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Viewer }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("setupRequired", Bool.self),
          .field("user", User?.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ViewerQuery.Data.Viewer.self
        ] }

        /// No account exists yet: the client should offer first-run setup.
        var setupRequired: Bool { __data["setupRequired"] }
        /// The signed-in user, if any.
        var user: User? { __data["user"] }

        /// Viewer.User
        ///
        /// Parent Type: `User`
        nonisolated struct User: SovEmuGraphQL.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.User }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .fragment(UserFields.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            ViewerQuery.Data.Viewer.User.self,
            UserFields.self
          ] }

          var id: Int { __data["id"] }
          var username: String { __data["username"] }
          /// Whether the role is `ADMIN`.
          var isAdmin: Bool { __data["isAdmin"] }
          var role: GraphQLEnum<SovEmuGraphQL.Role> { __data["role"] }

          struct Fragments: FragmentContainer {
            let __data: DataDict
            init(_dataDict: DataDict) { __data = _dataDict }

            var userFields: UserFields { _toFragment() }
          }
        }
      }
    }
  }

}