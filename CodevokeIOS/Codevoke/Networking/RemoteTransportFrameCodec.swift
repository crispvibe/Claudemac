import Foundation
import ChatCore

/// JSON codec for the Remote VNC control frames carried by any transport.
///
/// Keeping encode/decode here prevents subtle drift between LAN WebSocket and
/// WebRTC DataChannel implementations. It also keeps ChatViewModel transport-
/// agnostic: transports emit already-decoded envelopes/acks and accept typed
/// resume/command frames.
struct RemoteTransportFrameCodec {
    enum DecodedFrame: Equatable {
        case panelState(PanelStateEnvelope)
        case commandAck(CommandAck)
        case recoveryResponse(RemoteRecoveryResponse)
        case hello
        case ignored(type: String)
    }

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func encodeResume(sessionId: UUID?, lastRevision: Int?) throws -> String {
        try encode(ResumeRequest(sessionId: sessionId, lastRevision: lastRevision))
    }

    func encodeCommand(_ command: Command) throws -> String {
        try encode(command)
    }

    func encodeRecoveryRequest(_ request: RemoteRecoveryRequest) throws -> String {
        try encode(request)
    }

    func decode(text: String) throws -> DecodedFrame {
        let payload = Data(text.utf8)
        guard
            let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let type = json["type"] as? String
        else {
            throw RemoteTransportFrameCodecError.missingType(preview: String(text.prefix(200)))
        }

        switch type {
        case RemoteVNCFrameType.panelState:
            return .panelState(try decoder.decode(PanelStateEnvelope.self, from: payload))
        case RemoteVNCFrameType.commandAck:
            return .commandAck(try decoder.decode(CommandAck.self, from: payload))
        case RemoteVNCFrameType.recoveryResponse:
            return .recoveryResponse(try decoder.decode(RemoteRecoveryResponse.self, from: payload))
        case "hello":
            return .hello
        default:
            return .ignored(type: type)
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RemoteTransportFrameCodecError.nonUTF8EncodedFrame
        }
        return text
    }
}

enum RemoteTransportFrameCodecError: LocalizedError {
    case missingType(preview: String)
    case nonUTF8EncodedFrame

    var errorDescription: String? {
        switch self {
        case .missingType(let preview):
            "Remote frame missing type: \(preview)"
        case .nonUTF8EncodedFrame:
            "Remote frame could not be encoded as UTF-8."
        }
    }
}
