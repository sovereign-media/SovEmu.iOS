// WebRTC's own names for the LiveKit build's `LK`-prefixed types. Only what the apps use: a type
// they start to use gets its line here.
@_exported import LiveKitWebRTC

public typealias RTCAudioDeviceModuleType = LKRTCAudioDeviceModuleType
public typealias RTCCVPixelBuffer = LKRTCCVPixelBuffer
public typealias RTCConfiguration = LKRTCConfiguration
public typealias RTCDataBuffer = LKRTCDataBuffer
public typealias RTCDataChannel = LKRTCDataChannel
public typealias RTCDataChannelConfiguration = LKRTCDataChannelConfiguration
public typealias RTCDataChannelDelegate = LKRTCDataChannelDelegate
public typealias RTCDefaultVideoDecoderFactory = LKRTCDefaultVideoDecoderFactory
public typealias RTCDefaultVideoEncoderFactory = LKRTCDefaultVideoEncoderFactory
public typealias RTCIceCandidate = LKRTCIceCandidate
public typealias RTCIceConnectionState = LKRTCIceConnectionState
public typealias RTCIceGatheringState = LKRTCIceGatheringState
public typealias RTCI420Buffer = LKRTCI420Buffer
public typealias RTCIceServer = LKRTCIceServer
public typealias RTCMTLVideoView = LKRTCMTLVideoView
public typealias RTCMediaConstraints = LKRTCMediaConstraints
public typealias RTCMediaStream = LKRTCMediaStream
public typealias RTCPeerConnection = LKRTCPeerConnection
public typealias RTCPeerConnectionDelegate = LKRTCPeerConnectionDelegate
public typealias RTCPeerConnectionFactory = LKRTCPeerConnectionFactory
public typealias RTCPeerConnectionState = LKRTCPeerConnectionState
public typealias RTCRtpTransceiver = LKRTCRtpTransceiver
public typealias RTCRtpTransceiverInit = LKRTCRtpTransceiverInit
public typealias RTCSessionDescription = LKRTCSessionDescription
public typealias RTCSignalingState = LKRTCSignalingState
public typealias RTCStatisticsReport = LKRTCStatisticsReport
public typealias RTCVideoFrame = LKRTCVideoFrame
public typealias RTCVideoFrameBuffer = LKRTCVideoFrameBuffer
public typealias RTCVideoRenderer = LKRTCVideoRenderer
public typealias RTCVideoTrack = LKRTCVideoTrack

@discardableResult
public func RTCInitializeSSL() -> Bool { LKRTCInitializeSSL() }
