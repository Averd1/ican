import AVFoundation
import Flutter
import Foundation

final class AudioPlaybackChannel: NSObject, AVAudioPlayerDelegate {
    private static let channelName = "com.ican/audio_player"
    private static let shared = AudioPlaybackChannel()
    private static var channel: FlutterMethodChannel?
    private static var registeredMessenger: AnyObject?

    private var player: AVAudioPlayer?
    private var pendingResult: FlutterResult?

    static func register(with messenger: FlutterBinaryMessenger) {
        let messengerObject = messenger as AnyObject
        if registeredMessenger === messengerObject { return }
        registeredMessenger = messengerObject

        let method = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        method.setMethodCallHandler { call, result in
            shared.handle(call, result: result)
        }
        channel = method
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "playMp3":
            guard
                let args = call.arguments as? [String: Any],
                let typed = args["bytes"] as? FlutterStandardTypedData
            else {
                result(FlutterError(code: "INVALID_ARGS",
                                    message: "bytes (Uint8List) required",
                                    details: nil))
                return
            }
            play(data: typed.data, result: result)
        case "stop":
            stop()
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func play(data: Data, result: @escaping FlutterResult) {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [
                .allowBluetooth,
                .allowBluetoothA2DP,
                .defaultToSpeaker,
            ])
            try session.setActive(true)

            let nextPlayer = try AVAudioPlayer(data: data)
            nextPlayer.delegate = self
            nextPlayer.prepareToPlay()
            pendingResult = result
            player = nextPlayer
            if !nextPlayer.play() {
                pendingResult = nil
                player = nil
                result(FlutterError(code: "PLAYBACK_FAILED",
                                    message: "AVAudioPlayer could not start.",
                                    details: nil))
            }
        } catch {
            pendingResult = nil
            player = nil
            result(FlutterError(code: "PLAYBACK_FAILED",
                                message: error.localizedDescription,
                                details: nil))
        }
    }

    private func stop() {
        player?.stop()
        player = nil
        if let pending = pendingResult {
            pending(true)
            pendingResult = nil
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        if let pending = pendingResult {
            pending(flag)
            pendingResult = nil
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        self.player = nil
        if let pending = pendingResult {
            pending(FlutterError(code: "DECODE_FAILED",
                                 message: error?.localizedDescription ?? "MP3 decode failed.",
                                 details: nil))
            pendingResult = nil
        }
    }
}
