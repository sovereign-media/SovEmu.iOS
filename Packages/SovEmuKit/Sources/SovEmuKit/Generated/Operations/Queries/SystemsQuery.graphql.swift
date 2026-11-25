// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct SystemsQuery: GraphQLQuery {
    static let operationName: String = "Systems"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query Systems { systems { __typename ...SystemFields } }"#,
        fragments: [SystemFields.self]
      ))

    public init() {}

    nonisolated struct Data: SovEmuGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("systems", [System].self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SystemsQuery.Data.self
      ] }

      /// The systems with games (hidden ones and those with none left out), in SovEmu's order.
      var systems: [System] { __data["systems"] }

      /// System
      ///
      /// Parent Type: `System`
      nonisolated struct System: SovEmuGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.System }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(SystemFields.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          SystemsQuery.Data.System.self,
          SystemFields.self
        ] }

        var id: SovEmuGraphQL.ID { __data["id"] }
        var name: String { __data["name"] }
        /// A short label for tight spaces ("SNES").
        var short: String { __data["short"] }
        var manufacturer: String { __data["manufacturer"] }
        var year: Int { __data["year"] }
        /// The UI accent colour (CSS).
        var color: String { __data["color"] }
        var gameCount: Int { __data["gameCount"] }
        /// A core that plays it is installed (and, for a 3D system, there is a renderer).
        var playable: Bool { __data["playable"] }
        var needsGpu: Bool { __data["needsGpu"] }
        /// For a 3D system, where it renders here.
        var rendering: GraphQLEnum<SovEmuGraphQL.Rendering>? { __data["rendering"] }
        /// A BIOS file it cannot start games without is missing. Cheap: no checksums (see `bios`).
        var biosMissing: Bool { __data["biosMissing"] }
        /// A 3D system: its cores render with OpenGL and read analog sticks.
        /// The shape of its games' boxes, width over height (US and European releases): game cards
        /// take it so box art fills them.
        var boxAspect: Double { __data["boxAspect"] }

        struct Fragments: FragmentContainer {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          var systemFields: SystemFields { _toFragment() }
        }
      }
    }
  }

}