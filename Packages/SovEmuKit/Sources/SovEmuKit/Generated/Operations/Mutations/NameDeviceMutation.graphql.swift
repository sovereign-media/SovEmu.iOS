// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct NameDeviceMutation: GraphQLMutation {
    static let operationName: String = "NameDevice"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation NameDevice($name: String!) { nameDevice(name: $name) }"#
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
        .field("nameDevice", Bool.self, arguments: ["name": .variable("name")]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        NameDeviceMutation.Data.self
      ] }

      /// Names this sign-in's device, as the app describes itself ("SovEmu for Android 1.4.0 ·
      /// Mi TV Stick"), for the admin's lists of sign-ins. An app calls it once signed in, and
      /// again when its version changes. `BAD_REQUEST` for an empty name or one over 80
      /// characters.
      var nameDevice: Bool { __data["nameDevice"] }
    }
  }

}