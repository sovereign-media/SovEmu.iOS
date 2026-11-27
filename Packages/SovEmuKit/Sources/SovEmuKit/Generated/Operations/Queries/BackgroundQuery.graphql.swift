// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct BackgroundQuery: GraphQLQuery {
    static let operationName: String = "Background"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query Background { background { __typename id url } }"#
      ))

    public init() {}

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("background", Background?.self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        BackgroundQuery.Data.self
      ] }

      /// The background to draw behind every screen now: the one chosen, or one at random each
      /// time it is asked (`random`); null for none.
      var background: Background? { __data["background"] }

      /// Background
      ///
      /// Parent Type: `Background`
      nonisolated struct Background: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Background }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", String.self),
          .field("url", String.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          BackgroundQuery.Data.Background.self
        ] }

        /// Its name in settings (`SovEmu__Appearance__Background`): `lattice`, or a file's name in the folders.
        var id: String { __data["id"] }
        /// The image (WebP, PNG or JPEG): a URL signed for this user.
        var url: String { __data["url"] }
      }
    }
  }

}