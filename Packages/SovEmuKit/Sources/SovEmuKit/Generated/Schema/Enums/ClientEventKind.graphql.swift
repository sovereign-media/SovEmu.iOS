// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) import ApolloAPI

extension SovEmuGraphQL {
  /// What went wrong on a client.
  nonisolated enum ClientEventKind: String, EnumType {
    /// WebRTC could not connect.
    case connectionFailed = "CONNECTION_FAILED"
    /// A connected stream dropped.
    case connectionLost = "CONNECTION_LOST"
    /// No new picture for a while during play.
    case streamStalled = "STREAM_STALLED"
    /// A controller the client has no layout for.
    case controllerUnknown = "CONTROLLER_UNKNOWN"
    /// A screen or the app failed.
    case screenError = "SCREEN_ERROR"
    case other = "OTHER"
  }

}