// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

nonisolated protocol SovEmuGraphQL_SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
where Schema == SovEmuGraphQL.SchemaMetadata {}

nonisolated protocol SovEmuGraphQL_InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
where Schema == SovEmuGraphQL.SchemaMetadata {}

nonisolated protocol SovEmuGraphQL_MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
where Schema == SovEmuGraphQL.SchemaMetadata {}

nonisolated protocol SovEmuGraphQL_MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
where Schema == SovEmuGraphQL.SchemaMetadata {}

extension SovEmuGraphQL {
  typealias SelectionSet = SovEmuGraphQL_SelectionSet

  typealias InlineFragment = SovEmuGraphQL_InlineFragment

  typealias MutableSelectionSet = SovEmuGraphQL_MutableSelectionSet

  typealias MutableInlineFragment = SovEmuGraphQL_MutableInlineFragment

  nonisolated enum SchemaMetadata: ApolloAPI.SchemaMetadata {
    static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

    private static let objectTypeMap: [String: ApolloAPI.Object] = [
      "Binding": SovEmuGraphQL.Objects.Binding,
      "BootstrapConfig": SovEmuGraphQL.Objects.BootstrapConfig,
      "Cheat": SovEmuGraphQL.Objects.Cheat,
      "ClientConfig": SovEmuGraphQL.Objects.ClientConfig,
      "Collection": SovEmuGraphQL.Objects.Collection,
      "ControllerMapping": SovEmuGraphQL.Objects.ControllerMapping,
      "Decoration": SovEmuGraphQL.Objects.Decoration,
      "Game": SovEmuGraphQL.Objects.Game,
      "GameSession": SovEmuGraphQL.Objects.GameSession,
      "Home": SovEmuGraphQL.Objects.Home,
      "Mutation": SovEmuGraphQL.Objects.Mutation,
      "PadKey": SovEmuGraphQL.Objects.PadKey,
      "PadLayout": SovEmuGraphQL.Objects.PadLayout,
      "Patch": SovEmuGraphQL.Objects.Patch,
      "Query": SovEmuGraphQL.Objects.Query,
      "SaveSlot": SovEmuGraphQL.Objects.SaveSlot,
      "Shape": SovEmuGraphQL.Objects.Shape,
      "StartStatus": SovEmuGraphQL.Objects.StartStatus,
      "System": SovEmuGraphQL.Objects.System,
      "SystemButton": SovEmuGraphQL.Objects.SystemButton,
      "SystemControls": SovEmuGraphQL.Objects.SystemControls,
      "SystemStick": SovEmuGraphQL.Objects.SystemStick,
      "User": SovEmuGraphQL.Objects.User,
      "Viewer": SovEmuGraphQL.Objects.Viewer
    ]

    static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
      objectTypeMap[typename]
    }
  }

  nonisolated enum Objects {}
  nonisolated enum Interfaces {}
  nonisolated enum Unions {}

}