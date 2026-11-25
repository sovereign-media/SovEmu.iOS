// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) import ApolloAPI

extension SovEmuGraphQL {
  /// What an account may do.
  nonisolated enum Role: String, EnumType {
    /// Plays games: browse the library, play, keep saves and settings of their own.
    case viewer = "VIEWER"
    /// Also runs the server: users, the library, emulator settings.
    case admin = "ADMIN"
  }

}