import CryptoKit
import Foundation

/// Codex's proxy forwards raw socket bytes, including RFC 6455 upgrade and framing.
/// It is not the JSONL transport exposed by `app-server --listen stdio://`.
final class ProxyWebSocket {
    private let command: BoundedCommand
    private var sequence = 0

    init(_ command: BoundedCommand) throws {
        self.command = command
        let key = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString()
        let request =
            "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            + "Sec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n"
        try command.write(Data(request.utf8))
        let response = try command.receive(until: Data("\r\n\r\n".utf8), limit: 16_384)
        let lines = String(decoding: response, as: UTF8.self).components(separatedBy: "\r\n")
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let name = parts[0].lowercased()
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                headers[name] = headers[name].map { $0 + "," + value } ?? value
            }
        }
        let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8)))
            .base64EncodedString()
        guard lines.first?.hasPrefix("HTTP/1.1 101 ") == true,
            headers["upgrade"]?.lowercased() == "websocket",
            headers["connection"]?.lowercased().split(separator: ",").contains(where: {
                $0.trimmingCharacters(in: .whitespaces) == "upgrade"
            }) == true,
            headers["sec-websocket-accept"] == accept,
            headers["sec-websocket-extensions"] == nil,
            headers["sec-websocket-protocol"] == nil
        else { throw ActionFailure("Codex proxy did not accept the WebSocket connection.") }
    }

    func notify(_ method: String) throws { try send(["method": method]) }

    func request(_ method: String, params: [String: Any]) throws -> [String: Any] {
        sequence += 1
        try send(["id": sequence, "method": method, "params": params])
        while true {
            let data = try message()
            guard String(data: data, encoding: .utf8) != nil,
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw ActionFailure("Invalid Codex protocol response.") }
            guard object["id"] as? Int == sequence else { continue }
            guard object["error"] == nil, let result = object["result"] as? [String: Any] else {
                throw ActionFailure("Codex cannot verify this session on its local app server.")
            }
            return result
        }
    }

    private func send(_ value: [String: Any]) throws {
        try frame(JSONSerialization.data(withJSONObject: value), opcode: 1)
    }

    private func frame(_ data: Data, opcode: UInt8) throws {
        var bytes = Data([0x80 | opcode])
        switch data.count {
        case 0..<126: bytes.append(0x80 | UInt8(data.count))
        case 126...65_535:
            bytes.append(0x80 | 126)
            bytes.append(UInt8(data.count >> 8))
            bytes.append(UInt8(data.count & 255))
        default: throw ActionFailure("Codex control request exceeded the size limit.")
        }
        // RFC 6455 §5.3 requires an unpredictable mask even over a local Unix socket.
        let mask = (0..<4).map { _ in UInt8.random(in: .min ... .max) }
        bytes.append(contentsOf: mask)
        bytes.append(contentsOf: data.enumerated().map { $0.element ^ mask[$0.offset % 4] })
        try command.write(bytes)
    }

    private func message() throws -> Data {
        var message = Data()
        var fragmented = false
        while true {
            let header = [UInt8](try command.receive(count: 2))
            let final = header[0] & 0x80 != 0
            let opcode = header[0] & 0x0F
            guard header[0] & 0x70 == 0, header[1] & 0x80 == 0 else {
                throw ActionFailure("Unsupported Codex WebSocket frame.")
            }
            let sizeCode = header[1] & 0x7F
            var size = UInt64(sizeCode)
            switch sizeCode {
            case 126: size = try command.receive(count: 2).reduce(0) { ($0 << 8) | UInt64($1) }
            case 127: size = try command.receive(count: 8).reduce(0) { ($0 << 8) | UInt64($1) }
            default: break
            }
            guard size <= 1_048_576,
                sizeCode != 126 || size >= 126, sizeCode != 127 || size > 65_535,
                opcode < 8 || (final && size <= 125)
            else { throw ActionFailure("Invalid or oversized Codex WebSocket frame.") }
            let payload = try command.receive(count: Int(size))
            switch opcode {
            case 8: throw ActionFailure("Codex closed the app-server connection.")
            case 9:
                try frame(payload, opcode: 10)
                continue
            case 10: continue
            case 1:
                guard !fragmented else { throw ActionFailure("Invalid Codex message fragments.") }
                fragmented = true
            case 0:
                guard fragmented else { throw ActionFailure("Unexpected Codex continuation frame.") }
            default: throw ActionFailure("Expected a Codex text response.")
            }
            message.append(payload)
            guard message.count <= 1_048_576 else {
                throw ActionFailure("Codex message exceeded the size limit.")
            }
            if final { return message }
        }
    }
}
