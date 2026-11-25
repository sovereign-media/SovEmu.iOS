// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct LayoutFields: SovEmuGraphQL.SelectionSet, Fragment {
    static var fragmentDefinition: StaticString {
      #"fragment LayoutFields on PadLayout { __typename id name width height body { __typename x y w h r tone } keys { __typename key label x y w h r } }"#
    }

    let __data: DataDict
    init(_dataDict: DataDict) { __data = _dataDict }

    static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.PadLayout }
    static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("id", String.self),
      .field("name", String.self),
      .field("width", Double.self),
      .field("height", Double.self),
      .field("body", [Body].self),
      .field("keys", [Key].self),
    ] }
    static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      LayoutFields.self
    ] }

    /// A system id, or a controller family (`xbox`, `playstation`, `nintendo`, `generic`).
    var id: String { __data["id"] }
    var name: String { __data["name"] }
    var width: Double { __data["width"] }
    var height: Double { __data["height"] }
    var body: [Body] { __data["body"] }
    var keys: [Key] { __data["keys"] }

    /// Body
    ///
    /// Parent Type: `Shape`
    nonisolated struct Body: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Shape }
      static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("x", Double.self),
        .field("y", Double.self),
        .field("w", Double.self),
        .field("h", Double.self),
        .field("r", Double.self),
        .field("tone", Int.self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        LayoutFields.Body.self
      ] }

      var x: Double { __data["x"] }
      var y: Double { __data["y"] }
      var w: Double { __data["w"] }
      var h: Double { __data["h"] }
      var r: Double { __data["r"] }
      /// 0 the body, 1 a recess drawn darker (a screen, a stick's well).
      var tone: Int { __data["tone"] }
    }

    /// Key
    ///
    /// Parent Type: `PadKey`
    nonisolated struct Key: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.PadKey }
      static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("key", String.self),
        .field("label", String.self),
        .field("x", Double.self),
        .field("y", Double.self),
        .field("w", Double.self),
        .field("h", Double.self),
        .field("r", Double.self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        LayoutFields.Key.self
      ] }

      /// A RetroPad button on a system's pad, an input name (`south` …) on a controller's.
      var key: String { __data["key"] }
      /// What the pad prints on it.
      var label: String { __data["label"] }
      var x: Double { __data["x"] }
      var y: Double { __data["y"] }
      var w: Double { __data["w"] }
      var h: Double { __data["h"] }
      var r: Double { __data["r"] }
    }
  }

}