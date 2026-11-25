// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct UserFields: SovEmuGraphQL.SelectionSet, Fragment {
    static var fragmentDefinition: StaticString {
      #"fragment UserFields on User { __typename id username isAdmin role }"#
    }

    let __data: DataDict
    init(_dataDict: DataDict) { __data = _dataDict }

    static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.User }
    static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("id", Int.self),
      .field("username", String.self),
      .field("isAdmin", Bool.self),
      .field("role", GraphQLEnum<SovEmuGraphQL.Role>.self),
    ] }
    static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      UserFields.self
    ] }

    var id: Int { __data["id"] }
    var username: String { __data["username"] }
    /// Whether the role is `ADMIN`.
    var isAdmin: Bool { __data["isAdmin"] }
    var role: GraphQLEnum<SovEmuGraphQL.Role> { __data["role"] }
  }

}