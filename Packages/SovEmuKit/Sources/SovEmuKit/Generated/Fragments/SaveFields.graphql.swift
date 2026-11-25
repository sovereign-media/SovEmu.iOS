// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct SaveFields: SovEmuGraphQL.SelectionSet, Fragment {
    static var fragmentDefinition: StaticString {
      #"fragment SaveFields on SaveSlot { __typename slot savedAt screenshotUrl }"#
    }

    let __data: DataDict
    init(_dataDict: DataDict) { __data = _dataDict }

    static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.SaveSlot }
    static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("slot", Int.self),
      .field("savedAt", Double.self),
      .field("screenshotUrl", String?.self),
    ] }
    static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      SaveFields.self
    ] }

    /// 0 is the auto save; 1–9 are the player's.
    var slot: Int { __data["slot"] }
    /// Unix seconds.
    var savedAt: Double { __data["savedAt"] }
    /// The screen when it was saved, if there is one: a URL signed for this user that changes
    /// with each save.
    var screenshotUrl: String? { __data["screenshotUrl"] }
  }

}