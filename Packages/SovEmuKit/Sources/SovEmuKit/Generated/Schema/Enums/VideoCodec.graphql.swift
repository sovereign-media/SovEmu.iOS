// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) import ApolloAPI

extension SovEmuGraphQL {
  /// A video codec a client may decode. The worker encodes VP8 and H.264 today; the rest are
  /// named so a client's document need not change when their encoders arrive.
  nonisolated enum VideoCodec: String, EnumType {
    case vp8 = "VP8"
    case h264 = "H264"
    case vp9 = "VP9"
    case av1 = "AV1"
    case h265 = "H265"
  }

}