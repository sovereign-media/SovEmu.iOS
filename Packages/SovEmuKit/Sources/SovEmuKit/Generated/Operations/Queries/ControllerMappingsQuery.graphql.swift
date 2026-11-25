// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct ControllerMappingsQuery: GraphQLQuery {
    static let operationName: String = "ControllerMappings"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query ControllerMappings($system: ID) { controllerMappings(system: $system) { __typename ...MappingFields } }"#,
        fragments: [MappingFields.self]
      ))

    public var system: GraphQLNullable<ID>

    public init(system: GraphQLNullable<ID>) {
      self.system = system
    }

    @_spi(Unsafe) public var __variables: Variables? { ["system": system] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("controllerMappings", [ControllerMapping].self, arguments: ["system": .variable("system")]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        ControllerMappingsQuery.Data.self
      ] }

      /// The controller mappings in force for this user on a system (or, with none, on every
      /// system), one per controller model (docs/CONTROLLERS.md): their own for the system, their
      /// own for every system, the default for the system, the default for every system. A model
      /// missing here uses the clients' built-in defaults.
      var controllerMappings: [ControllerMapping] { __data["controllerMappings"] }

      /// ControllerMapping
      ///
      /// Parent Type: `ControllerMapping`
      nonisolated struct ControllerMapping: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.ControllerMapping }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(MappingFields.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ControllerMappingsQuery.Data.ControllerMapping.self,
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