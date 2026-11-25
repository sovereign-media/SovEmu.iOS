// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct ControlsQuery: GraphQLQuery {
    static let operationName: String = "Controls"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query Controls($id: ID!) { system(id: $id) { __typename controls { __typename buttons { __typename button label } sticks { __typename stick label key } layout { __typename ...LayoutFields } } } controllerLayouts { __typename ...LayoutFields } }"#,
        fragments: [LayoutFields.self]
      ))

    public var id: ID

    public init(id: ID) {
      self.id = id
    }

    @_spi(Unsafe) public var __variables: Variables? { ["id": id] }

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("system", System?.self, arguments: ["id": .variable("id")]),
        .field("controllerLayouts", [ControllerLayout].self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        ControlsQuery.Data.self
      ] }

      var system: System? { __data["system"] }
      /// Diagrams of the player's controllers, by family (`xbox`, `playstation`, `nintendo`,
      /// `generic`), keyed by input (`south`, `l1` …).
      var controllerLayouts: [ControllerLayout] { __data["controllerLayouts"] }

      /// System
      ///
      /// Parent Type: `System`
      nonisolated struct System: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.System }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("controls", Controls.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ControlsQuery.Data.System.self
        ] }

        /// What the system calls its buttons, and a diagram of its pad (docs/CONTROLLERS.md).
        var controls: Controls { __data["controls"] }

        /// System.Controls
        ///
        /// Parent Type: `SystemControls`
        nonisolated struct Controls: SovEmuGraphQL.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.SystemControls }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("buttons", [Button].self),
            .field("sticks", [Stick].self),
            .field("layout", Layout.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            ControlsQuery.Data.System.Controls.self
          ] }

          /// The buttons the system's pad has, in the order to list them.
          var buttons: [Button] { __data["buttons"] }
          /// The analog controls the system's core reads from the player's sticks, in the order to
          /// list them after the buttons; empty for a system without them.
          var sticks: [Stick] { __data["sticks"] }
          var layout: Layout { __data["layout"] }

          /// System.Controls.Button
          ///
          /// Parent Type: `SystemButton`
          nonisolated struct Button: SovEmuGraphQL.SelectionSet {
            let __data: DataDict
            init(_dataDict: DataDict) { __data = _dataDict }

            static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.SystemButton }
            static var __selections: [ApolloAPI.Selection] { [
              .field("__typename", String.self),
              .field("button", GraphQLEnum<SovEmuGraphQL.PadButton>.self),
              .field("label", String.self),
            ] }
            static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
              ControlsQuery.Data.System.Controls.Button.self
            ] }

            var button: GraphQLEnum<SovEmuGraphQL.PadButton> { __data["button"] }
            var label: String { __data["label"] }
          }

          /// System.Controls.Stick
          ///
          /// Parent Type: `SystemStick`
          nonisolated struct Stick: SovEmuGraphQL.SelectionSet {
            let __data: DataDict
            init(_dataDict: DataDict) { __data = _dataDict }

            static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.SystemStick }
            static var __selections: [ApolloAPI.Selection] { [
              .field("__typename", String.self),
              .field("stick", GraphQLEnum<SovEmuGraphQL.Stick>.self),
              .field("label", String.self),
              .field("key", String.self),
            ] }
            static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
              ControlsQuery.Data.System.Controls.Stick.self
            ] }

            var stick: GraphQLEnum<SovEmuGraphQL.Stick> { __data["stick"] }
            var label: String { __data["label"] }
            var key: String { __data["key"] }
          }

          /// System.Controls.Layout
          ///
          /// Parent Type: `PadLayout`
          nonisolated struct Layout: SovEmuGraphQL.SelectionSet {
            let __data: DataDict
            init(_dataDict: DataDict) { __data = _dataDict }

            static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.PadLayout }
            static var __selections: [ApolloAPI.Selection] { [
              .field("__typename", String.self),
              .fragment(LayoutFields.self),
            ] }
            static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
              ControlsQuery.Data.System.Controls.Layout.self,
              LayoutFields.self
            ] }

            /// A system id, or a controller family (`xbox`, `playstation`, `nintendo`, `generic`).
            var id: String { __data["id"] }
            var name: String { __data["name"] }
            var width: Double { __data["width"] }
            var height: Double { __data["height"] }
            var body: [Body] { __data["body"] }
            var keys: [Key] { __data["keys"] }

            struct Fragments: FragmentContainer {
              let __data: DataDict
              init(_dataDict: DataDict) { __data = _dataDict }

              var layoutFields: LayoutFields { _toFragment() }
            }

            typealias Body = LayoutFields.Body

            typealias Key = LayoutFields.Key
          }
        }
      }

      /// ControllerLayout
      ///
      /// Parent Type: `PadLayout`
      nonisolated struct ControllerLayout: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.PadLayout }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(LayoutFields.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ControlsQuery.Data.ControllerLayout.self,
          LayoutFields.self
        ] }

        /// A system id, or a controller family (`xbox`, `playstation`, `nintendo`, `generic`).
        var id: String { __data["id"] }
        var name: String { __data["name"] }
        var width: Double { __data["width"] }
        var height: Double { __data["height"] }
        var body: [Body] { __data["body"] }
        var keys: [Key] { __data["keys"] }

        struct Fragments: FragmentContainer {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          var layoutFields: LayoutFields { _toFragment() }
        }

        typealias Body = LayoutFields.Body

        typealias Key = LayoutFields.Key
      }
    }
  }

}