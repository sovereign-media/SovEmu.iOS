// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct CreateCollectionMutation: GraphQLMutation {
    static let operationName: String = "CreateCollection"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation CreateCollection($name: String!) { createCollection(name: $name) { __typename id name } }"#
      ))

    public var name: String

    public init(name: String) {
      self.name = name
    }

    @_spi(Unsafe) public var __variables: Variables? { ["name": name] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("createCollection", CreateCollection.self, arguments: ["name": .variable("name")]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        CreateCollectionMutation.Data.self
      ] }

      /// Creates a collection (CONFLICT if this user already has one by that name).
      var createCollection: CreateCollection { __data["createCollection"] }

      /// CreateCollection
      ///
      /// Parent Type: `Collection`
      nonisolated struct CreateCollection: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Collection }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", Int.self),
          .field("name", String.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          CreateCollectionMutation.Data.CreateCollection.self
        ] }

        var id: Int { __data["id"] }
        var name: String { __data["name"] }
      }
    }
  }

}