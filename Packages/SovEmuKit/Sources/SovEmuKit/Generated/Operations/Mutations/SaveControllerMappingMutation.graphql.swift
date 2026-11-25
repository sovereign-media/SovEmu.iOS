// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct SaveControllerMappingMutation: GraphQLMutation {
    static let operationName: String = "SaveControllerMapping"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"mutation SaveControllerMapping($controller: String!, $system: ID, $name: String!, $bindings: [BindingInput!]!) { saveControllerMapping( controller: $controller system: $system name: $name bindings: $bindings ) { __typename ...MappingFields } }"#,
        fragments: [MappingFields.self]
      ))

    public var controller: String
    public var system: GraphQLNullable<ID>
    public var name: String
    public var bindings: [BindingInput]

    public init(
      controller: String,
      system: GraphQLNullable<ID>,
      name: String,
      bindings: [BindingInput]
    ) {
      self.controller = controller
      self.system = system
      self.name = name
      self.bindings = bindings
    }

    @_spi(Unsafe) public var __variables: Variables? { [
      "controller": controller,
      "system": system,
      "name": name,
      "bindings": bindings
    ] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Mutation }
      static var __selections: [ApolloAPI.Selection] { [
        .field("saveControllerMapping", SaveControllerMapping.self, arguments: [
          "controller": .variable("controller"),
          "system": .variable("system"),
          "name": .variable("name"),
          "bindings": .variable("bindings")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SaveControllerMappingMutation.Data.self
      ] }

      /// Saves this user's mapping for a controller model on a system, or on every system without
      /// one, replacing its defaults wherever they play.
      var saveControllerMapping: SaveControllerMapping { __data["saveControllerMapping"] }

      /// SaveControllerMapping
      ///
      /// Parent Type: `ControllerMapping`
      nonisolated struct SaveControllerMapping: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.ControllerMapping }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(MappingFields.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          SaveControllerMappingMutation.Data.SaveControllerMapping.self,
          MappingFields.self
        ] }

        /// `keyboard`, a known model (`xbox`, `dualsense` …) or `pad:<vendor>:<product>`.
        var controller: String { __data["controller"] }
        /// The system it is for, or null for every system.
        var system: String? { __data["system"] }
        /// What the controller called itself when the mapping was saved, for lists.
        var name: String { __data["name"] }
        var bindings: [Binding] { __data["bindings"] }
        var source: GraphQLEnum<SovEmuGraphQL.MappingSource> { __data["source"] }

        struct Fragments: FragmentContainer {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          var mappingFields: MappingFields { _toFragment() }
        }

        typealias Binding = MappingFields.Binding
      }
    }
  }

}