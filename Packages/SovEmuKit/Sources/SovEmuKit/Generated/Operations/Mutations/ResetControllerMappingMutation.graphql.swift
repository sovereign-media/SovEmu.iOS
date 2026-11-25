// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct ResetControllerMappingMutation: GraphQLMutation {
    static let operationName: String = "ResetControllerMapping"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation ResetControllerMapping($controller: String!, $system: ID) { resetControllerMapping(controller: $controller, system: $system) }"#
      ))

    public var controller: String
    public var system: GraphQLNullable<ID>

    public init(
      controller: String,
      system: GraphQLNullable<ID>
    ) {
      self.controller = controller
      self.system = system
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "controller": controller,
      "system": system
    ] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("resetControllerMapping", Bool.self, arguments: [
          "controller": .variable("controller"),
          "system": .variable("system")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        ResetControllerMappingMutation.Data.self
      ] }

      /// Puts a controller model back on the defaults (an admin's, else the built-in ones).
      /// Returns whether it had a mapping of the user's own.
      var resetControllerMapping: Bool { __data["resetControllerMapping"] }
    }
  }

}