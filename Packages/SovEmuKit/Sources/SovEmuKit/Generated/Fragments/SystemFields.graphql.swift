// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

extension SovEmuGraphQL {
  nonisolated struct SystemFields: SovEmuGraphQL.SelectionSet, Fragment {
    static var fragmentDefinition: StaticString {
      #"fragment SystemFields on System { __typename id name short manufacturer year color gameCount playable needsGpu rendering biosMissing boxAspect photoUrl }"#
    }

    let __data: DataDict
    init(_dataDict: DataDict) { __data = _dataDict }

    static var __parentType: any ApolloAPI.ParentType { SovEmuGraphQL.Objects.System }
    static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("id", SovEmuGraphQL.ID.self),
      .field("name", String.self),
      .field("short", String.self),
      .field("manufacturer", String.self),
      .field("year", Int.self),
      .field("color", String.self),
      .field("gameCount", Int.self),
      .field("playable", Bool.self),
      .field("needsGpu", Bool.self),
      .field("rendering", GraphQLEnum<SovEmuGraphQL.Rendering>?.self),
      .field("biosMissing", Bool.self),
      .field("boxAspect", Double.self),
      .field("photoUrl", String?.self),
    ] }
    static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
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
    /// A photo of its hardware for its card (a transparent cut-out): SovEmu's, or the admin's own
    /// from `<data>/systems/<id>.webp`. A URL signed for this user; null when it has none.
    var photoUrl: String? { __data["photoUrl"] }
  }

}