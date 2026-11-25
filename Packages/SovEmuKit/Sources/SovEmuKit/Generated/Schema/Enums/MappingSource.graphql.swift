// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) import ApolloAPI

extension SovEmuGraphQL {
  /// Where a mapping comes from.
  nonisolated enum MappingSource: String, EnumType {
    /// The user's own.
    case user = "USER"
    /// An admin's default, from the admin page.
    case admin = "ADMIN"
    /// A default from `SovEmu__Controllers__<n>__…`, which an admin cannot change (locked).
    case environment = "ENVIRONMENT"
  }

}