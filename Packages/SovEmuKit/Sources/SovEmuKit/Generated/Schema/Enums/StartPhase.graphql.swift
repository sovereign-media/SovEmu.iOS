// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) import ApolloAPI

extension SovEmuGraphQL {
  /// What a game start is doing.
  nonisolated enum StartPhase: String, EnumType {
    /// Saving and stopping the player's previous session.
    case stopping = "STOPPING"
    /// Starting the emulator's process.
    case launching = "LAUNCHING"
    /// Opening the emulator.
    case core = "CORE"
    /// Reading the game.
    case content = "CONTENT"
    case ready = "READY"
    case failed = "FAILED"
  }

}