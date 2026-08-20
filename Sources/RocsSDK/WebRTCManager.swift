import AVFoundation
import Foundation
#if canImport(Mediasoup)
import Mediasoup
#endif
import WebRTC

// MARK: - WebRTCManager

final class WebRTCManager: NSObject {

    // MARK: - Callbacks

    var onRemoteAudioTrack: ((RTCMediaStreamTrack) -> Void)?
    var onRemoteVideoTrack: ((RTCMediaStreamTrack) -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: - Private state

    private var device: Device?
    private var sendTransport: SendTransport?
    private var _recvTransport: ReceiveTransport?

    /// Public read-only access to recv transport ID (needed for consume calls)
    var recvTransportId: String? { _recvTransport?.id }
    private var audioProducer: Producer?
    private var videoProducer: Producer?
    private var audioConsumer: Consumer?
    private var videoConsumer: Consumer?
    private var iceServersJson: String = "[]"

    // Camera state
    private(set) var cameraCapturer: RTCCameraVideoCapturer?
    private(set) var localVideoTrack: RTCVideoTrack?
    private var localVideoSource: RTCVideoSource?
    private(set) var cameraPosition: AVCaptureDevice.Position = .front

    // Signaling callbacks set by RocsClient
    var onSendTransportConnect: ((String) async throws -> Void)?
    var onRecvTransportConnect: ((String) async throws -> Void)?
    var onProduceCallback: ((String, String, String, @escaping (String?) -> Void) -> Void)?

    private let pcFactory: RTCPeerConnectionFactory = {
        // Configure WebRTC's audio session for loudspeaker BEFORE creating the factory.
        let config = RTCAudioSessionConfiguration.webRTC()
        config.category = AVAudioSession.Category.playAndRecord.rawValue
        config.categoryOptions = [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        config.mode = AVAudioSession.Mode.voiceChat.rawValue
        RTCAudioSessionConfiguration.setWebRTC(config)

        RTCInitializeSSL()
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()

    override init() { super.init() }
    deinit { cleanup() }

    // MARK: - Device

    func loadDevice(routerRtpCapabilities: String) async throws {
        print("[WebRTCManager] 🔵 loadDevice() called")
        let dev = Device(pcFactory: pcFactory)
        do {
            try await dev.load(with: routerRtpCapabilities)
            device = dev
            print("[WebRTCManager] ✅ Device loaded successfully")
        } catch {
            print("[WebRTCManager] ❌ Device load failed: \(error)")
            throw error
        }
    }

    func rtpCapabilities() throws -> String {
        guard let dev = device else { throw WErr("Device not loaded") }
        return try dev.rtpCapabilities()
    }

    // MARK: - ICE

    func setIceServers(_ servers: [[String: Any]]) {
        if let data = try? JSONSerialization.data(withJSONObject: servers),
           let str  = String(data: data, encoding: .utf8) { iceServersJson = str }
    }

    // MARK: - Transports

    func createSendTransport(params: [String: Any]) throws {
        print("[WebRTCManager] 🔵 createSendTransport() called")
        guard let dev = device else { 
            print("[WebRTCManager] ❌ Device not loaded")
            throw WErr("Device not loaded") 
        }
        do {
            let t = try dev.createSendTransport(
                id: params["id"] as? String ?? "",
                iceParameters:  try js(params["iceParameters"]),
                iceCandidates:  try js(params["iceCandidates"]),
                dtlsParameters: try js(params["dtlsParameters"]),
                sctpParameters: try? js(params["sctpParameters"]),
                iceServers: iceServersJson == "[]" ? nil : iceServersJson,
                iceTransportPolicy: ICETransportPolicy.relay,
                appData: nil)
            t.delegate = self
            sendTransport = t
            print("[WebRTCManager] ✅ Send transport created - id: \(t.id)")
        } catch {
            print("[WebRTCManager] ❌ createSendTransport failed: \(error)")
            throw error
        }
    }

    func createRecvTransport(params: [String: Any]) throws {
        guard let dev = device else { throw WErr("Device not loaded") }
        let t = try dev.createReceiveTransport(
            id: params["id"] as? String ?? "",
            iceParameters:  try js(params["iceParameters"]),
            iceCandidates:  try js(params["iceCandidates"]),
            dtlsParameters: try js(params["dtlsParameters"]),
            sctpParameters: try? js(params["sctpParameters"]),
            iceServers: iceServersJson == "[]" ? nil : iceServersJson,
            iceTransportPolicy: ICETransportPolicy.relay,
            appData: nil)
        t.delegate = self
        _recvTransport = t
    }

    // MARK: - Produce

    func produceAudio() async throws {
        print("[WebRTCManager] 🔵 produceAudio() called")
        guard let t = sendTransport else { 
            print("[WebRTCManager] ❌ Send transport not ready")
            throw WErr("Send transport not ready") 
        }
        do {
            let audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "echoCancellation":          kRTCMediaConstraintsValueTrue,
                "googEchoCancellation":      kRTCMediaConstraintsValueTrue,
                "googNoiseSuppression":      kRTCMediaConstraintsValueTrue,
                "googAutoGainControl":       kRTCMediaConstraintsValueTrue,
                "googHighpassFilter":        kRTCMediaConstraintsValueTrue,
                "googTypingNoiseDetection":  kRTCMediaConstraintsValueTrue
            ],
            optionalConstraints: nil
        )
        let src   = pcFactory.audioSource(with: audioConstraints)
            let track = pcFactory.audioTrack(with: src, trackId: "rocs-audio-0")
            track.isEnabled = true
            print("[WebRTCManager] 🔵 Calling createProducer for audio track...")
            let p = try await t.createProducer(for: track, encodings: nil, codecOptions: nil, codec: nil, appData: nil)
            p.delegate = self
            p.resume()
            audioProducer = p
            print("[WebRTCManager] ✅ Audio producer created successfully")

            // Force audio output to loudspeaker after WebRTC activates its audio session
            Self.forceCurrentAudioRoute(self.currentAudioRoute)

            // Start periodic stats logging to diagnose audio flow
            startStatsLogging()
        } catch {
            print("[WebRTCManager] ❌ produceAudio failed: \(error)")
            throw error
        }
    }

    private var statsTimer: Timer?

    private func startStatsLogging() {
        // Log stats at 2s, 5s, and 10s after produce
        let transport = sendTransport
        for delay in [2.0, 5.0, 10.0] {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                print("[WebRTCManager] 📊 === Stats check at \(delay)s ===")
                transport?.logSenderStats()
            }
        }
    }

    func produceVideoTrack(_ track: RTCVideoTrack) async throws {
        guard let t = sendTransport else { throw WErr("Send transport not ready") }
        let p = try await t.createProducer(for: track, encodings: nil, codecOptions: nil, codec: nil, appData: nil)
        p.delegate = self
        p.resume()
        videoProducer = p
    }

    // MARK: - Consume

    func consumeAudio(params: [String: Any]) async throws {
        print("[WebRTCManager] 🔵 consumeAudio - params keys: \(params.keys.sorted())")
        guard let t = _recvTransport else { throw WErr("Recv transport not ready") }
        
        // Activate RTCAudioSession BEFORE consuming to ensure audio unit is ready
        // This prevents first audio packets from being dropped
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.lockForConfiguration()
        do {
            try rtcSession.setActive(true)
            print("[WebRTCManager] ✅ RTCAudioSession activated before consume")
        } catch {
            print("[WebRTCManager] ⚠️ Failed to activate RTCAudioSession: \(error)")
        }
        rtcSession.unlockForConfiguration()
        
        let c = try await t.consume(
            consumerId: params["id"] as? String ?? "",
            producerId: params["producerId"] as? String ?? "",
            kind: MediaKind.audio,
            rtpParameters: try js(params["rtpParameters"]),
            appData: nil)
        c.delegate = self
        audioConsumer = c
        onRemoteAudioTrack?(c.track)
        c.resume()

        // Ensure audio stays on the selected output after consuming remote audio
        Self.forceCurrentAudioRoute(self.currentAudioRoute)
    }

    func consumeVideo(params: [String: Any]) async throws {
        guard let t = _recvTransport else { throw WErr("Recv transport not ready") }
        let c = try await t.consume(
            consumerId: params["id"] as? String ?? "",
            producerId: params["producerId"] as? String ?? "",
            kind: MediaKind.video,
            rtpParameters: try js(params["rtpParameters"]),
            appData: nil)
        c.delegate = self
        videoConsumer = c
        onRemoteVideoTrack?(c.track)
        c.resume()
    }

    // MARK: - Controls

    func setMuted(_ muted: Bool) {
        audioProducer?.track.isEnabled = !muted
    }

    func getStats() -> String {
        var out: [String: Any] = [:]
        if let r = sendTransport?.stats,
           let d = r.data(using: .utf8),
           let p = try? JSONSerialization.jsonObject(with: d) { out["send"] = p }
        if let r = _recvTransport?.stats,
           let d = r.data(using: .utf8),
           let p = try? JSONSerialization.jsonObject(with: d) { out["recv"] = p }
        return (try? String(data: JSONSerialization.data(withJSONObject: out), encoding: .utf8)) ?? "{}"
    }

    // MARK: - Camera

    func startCamera(position: AVCaptureDevice.Position = .front) async throws {
        let source = pcFactory.videoSource()
        let capturer = RTCCameraVideoCapturer(delegate: source)
        let track = pcFactory.videoTrack(with: source, trackId: "rocs-video-0")
        track.isEnabled = true

        guard let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == position }) else {
            throw WErr("No camera found for position \(position.rawValue)")
        }

        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        guard let format = formats.sorted(by: {
            let dim0 = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            let dim1 = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
            return dim0.width * dim0.height < dim1.width * dim1.height
        }).first(where: {
            let dim = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return dim.width >= 640
        }) ?? formats.last else {
            throw WErr("No suitable camera format found")
        }

        try await capturer.startCapture(with: device, format: format, fps: 30)

        try await produceVideoTrack(track)

        // Camera activation can reconfigure AVAudioSession and interrupt audio.
        // Re-force audio session and ensure audio producer stays enabled.
        Self.forceCurrentAudioRoute(self.currentAudioRoute)
        audioProducer?.track.isEnabled = true
        audioProducer?.resume()

        localVideoSource = source
        cameraCapturer = capturer
        localVideoTrack = track
        cameraPosition = position
    }

    func stopCamera() {
        cameraCapturer?.stopCapture()
        videoProducer?.close()
        videoProducer = nil
        cameraCapturer = nil
        localVideoTrack = nil
        localVideoSource = nil
    }

    func switchCamera() throws {
        let newPosition: AVCaptureDevice.Position = (cameraPosition == .front) ? .back : .front
        guard let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == newPosition }) else {
            throw WErr("No camera found for position \(newPosition.rawValue)")
        }

        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        guard let format = formats.sorted(by: {
            let dim0 = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            let dim1 = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
            return dim0.width * dim0.height < dim1.width * dim1.height
        }).first(where: {
            let dim = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return dim.width >= 640
        }) ?? formats.last else {
            throw WErr("No suitable camera format found")
        }

        cameraCapturer?.stopCapture()
        cameraCapturer?.startCapture(with: device, format: format, fps: 30)
        cameraPosition = newPosition
    }

    // MARK: - Cleanup

    func cleanup() {
        cameraCapturer?.stopCapture()
        cameraCapturer = nil
        localVideoTrack = nil
        localVideoSource = nil
        audioProducer?.close(); audioProducer = nil
        videoProducer?.close(); videoProducer = nil
        audioConsumer?.close(); audioConsumer = nil
        videoConsumer?.close(); videoConsumer = nil
        sendTransport?.close(); sendTransport = nil
        _recvTransport?.close(); _recvTransport = nil
        device = nil
        RTCCleanupSSL()
    }

    // MARK: - Audio Output Control
    
    /// Current audio output route
    public private(set) var currentAudioRoute: AudioOutputRoute = .speaker
    
    /// Set audio output route (speaker or earpiece)
    public func setAudioOutput(_ route: AudioOutputRoute) {
        currentAudioRoute = route
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.lockForConfiguration()
        do {
            // Update the WebRTC audio session config so internal reconfigurations
            // don't revert our choice. `.defaultToSpeaker` must be removed for earpiece.
            let config = RTCAudioSessionConfiguration.webRTC()
            config.category = AVAudioSession.Category.playAndRecord.rawValue
            config.mode = AVAudioSession.Mode.voiceChat.rawValue

            switch route {
            case .speaker:
                config.categoryOptions = [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
                try rtcSession.setConfiguration(config)
                try rtcSession.overrideOutputAudioPort(.speaker)
                print("[WebRTCManager] ✅ Audio output set to SPEAKER")
            case .earpiece:
                config.categoryOptions = [.allowBluetooth, .allowBluetoothA2DP]
                try rtcSession.setConfiguration(config)
                try rtcSession.overrideOutputAudioPort(.none)
                print("[WebRTCManager] ✅ Audio output set to EARPIECE")
            }
        } catch {
            print("[WebRTCManager] ❌ Failed to set audio output to \(route): \(error)")
        }
        rtcSession.unlockForConfiguration()
    }
    
    /// Toggle audio output between speaker and earpiece
    public func toggleAudioOutput() {
        let newRoute: AudioOutputRoute = currentAudioRoute == .speaker ? .earpiece : .speaker
        setAudioOutput(newRoute)
    }

    // MARK: - Private helpers

    /// Force audio output to the loudspeaker using WebRTC's RTCAudioSession.
    static func forceOutputToSpeaker() {
        forceCurrentAudioRoute(.speaker)
    }

    /// Force audio output to the given route using WebRTC's RTCAudioSession.
    static func forceCurrentAudioRoute(_ route: AudioOutputRoute) {
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.lockForConfiguration()
        do {
            let config = RTCAudioSessionConfiguration.webRTC()
            config.category = AVAudioSession.Category.playAndRecord.rawValue
            config.mode = AVAudioSession.Mode.voiceChat.rawValue

            switch route {
            case .speaker:
                config.categoryOptions = [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
                try rtcSession.setConfiguration(config)
                try rtcSession.overrideOutputAudioPort(.speaker)
            case .earpiece:
                config.categoryOptions = [.allowBluetooth, .allowBluetoothA2DP]
                try rtcSession.setConfiguration(config)
                try rtcSession.overrideOutputAudioPort(.none)
            }
        } catch {
            print("[WebRTCManager] Failed to override output to \(route): \(error)")
        }
        rtcSession.unlockForConfiguration()
    }

    private func js(_ v: Any?) throws -> String {
        guard let v = v else { throw WErr("Missing JSON param") }
        if let s = v as? String { return s }
        guard let d = try? JSONSerialization.data(withJSONObject: v),
              let s = String(data: d, encoding: .utf8) else { throw WErr("JSON encode failed") }
        return s
    }
}

// MARK: - Transport Delegates (SendTransportDelegate + ReceiveTransportDelegate)
// Both inherit TransportDelegate, so onConnect/onConnectionStateChange are declared once.
// We distinguish send vs recv by matching transport.id.

extension WebRTCManager: SendTransportDelegate, ReceiveTransportDelegate {
    func onConnect(transport: Transport, dtlsParameters: String) async {
        print("[WebRTCManager] 🔵 onConnect - transport: \(transport.id), isSend: \(transport.id == sendTransport?.id)")
        if transport.id == sendTransport?.id {
            guard let h = onSendTransportConnect else {
                print("[WebRTCManager] ⚠️ onSendTransportConnect handler is nil!")
                return
            }
            do { try await h(dtlsParameters) }
            catch { self.onError?(error) }
        } else {
            guard let h = onRecvTransportConnect else {
                print("[WebRTCManager] ⚠️ onRecvTransportConnect handler is nil!")
                return
            }
            do { try await h(dtlsParameters) }
            catch { self.onError?(error) }
        }
    }

    func onConnectionStateChange(transport: Transport, connectionState: TransportConnectionState) {}

    func onProduce(transport: Transport, kind: MediaKind, rtpParameters: String,
                   appData: String, callback: @escaping (String?) -> Void) {
        onProduceCallback?(transport.id, kind == .audio ? "audio" : "video", rtpParameters, callback)
    }

    func onProduceData(transport: Transport, sctpParameters: String, label: String,
                       protocol p: String, appData: String, callback: @escaping (String?) -> Void) {
        callback(nil)
    }
}

// MARK: - ProducerDelegate

extension WebRTCManager: ProducerDelegate {
    func onTransportClose(in producer: Producer) {
        print("[WebRTCManager] Producer transport closed: \(producer.id)")
    }
}

// MARK: - ConsumerDelegate

extension WebRTCManager: ConsumerDelegate {
    func onTransportClose(in consumer: Consumer) {
        print("[WebRTCManager] Consumer transport closed: \(consumer.id)")
    }
}

// MARK: - Private error type

private struct WErr: Error, CustomStringConvertible {
    let description: String
    init(_ msg: String) { description = msg }
    var localizedDescription: String { description }
}
