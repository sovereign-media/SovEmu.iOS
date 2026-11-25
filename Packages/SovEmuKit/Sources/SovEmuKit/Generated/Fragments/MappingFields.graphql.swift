// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct MappingFields: SovEmuGraphQL.SelectionSet, Fragment {
    static var fragmentDefinition: StaticString {
      #"fragment MappingFields on ControllerMapping { __typename controller system name bindings { __typename input button } source }"#
    }

    let __data: DataDict
    init(_dataDict: DataDict) { __data = _dataDict }

    static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.ControllerMapping }
    static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("controller", String.self),
      .field("system", String?.self),
      .field("name", String.self),
      .field("bindings", [Binding].self),
      .field("source", GraphQLEnum<SovEmuGraphQL.MappingSource>.self),
    ] }
    static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
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

    /// Binding
    ///
    /// Parent Type: `Binding`
    nonisolated struct Binding: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Binding }
      static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("input", String.self),
        .field("button", GraphQLEnum<SovEmuGraphQL.PadButton>.self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        MappingFields.Binding.self
      ] }

      /// A controller input (`south`, `l1`, `up` …) or a keyboard's `KeyboardEvent.code`.
      var input: String { __data["input"] }
      var button: GraphQLEnum<SovEmuGraphQL.PadButton> { __data["button"] }
    }
  }

}