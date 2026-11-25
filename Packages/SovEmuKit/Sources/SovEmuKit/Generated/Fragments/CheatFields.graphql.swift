// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct CheatFields: SovEmuGraphQL.SelectionSet, Fragment {
    static var fragmentDefinition: StaticString {
      #"fragment CheatFields on Cheat { __typename id description code enabled }"#
    }

    let __data: DataDict
    init(_dataDict: DataDict) { __data = _dataDict }

    static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Cheat }
    static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("id", Int.self),
      .field("description", String.self),
      .field("code", String.self),
      .field("enabled", Bool.self),
    ] }
    static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      CheatFields.self
    ] }

    var id: Int { __data["id"] }
    var description: String { __data["description"] }
    var code: String { __data["code"] }
    var enabled: Bool { __data["enabled"] }
  }

}