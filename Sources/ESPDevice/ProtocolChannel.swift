// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPProtocol
import ESPTransport

/// Échange commande/réponse sur un `Transport` : encadrement SLIP, attente de la réponse
/// correspondante, contrôle de l'état et trace.
actor ProtocolChannel {
    let transport: any Transport
    private let trace: AsyncStream<TraceEvent>.Continuation?
    private var decoder = SLIPDecoder()
    private var pending: [Data] = []

    /// Taille du bloc d'état en fin de réponse ; `nil` tant que la puce n'est pas identifiée.
    var statusLength: Int?

    static let defaultTimeout: Duration = .seconds(3)
    /// Nombre maximal de paquets lus pour trouver la réponse attendue
    /// (l'ESP8266 renvoie des réponses SYNC en trop).
    static let maxSkippedPackets = 100

    init(transport: any Transport, trace: AsyncStream<TraceEvent>.Continuation?) {
        self.transport = transport
        self.trace = trace
    }

    func emit(_ event: TraceEvent) {
        trace?.yield(event)
    }

    func finishTrace() {
        trace?.finish()
    }

    func setStatusLength(_ length: Int?) {
        statusLength = length
    }

    /// Oublie tout ce qui a été reçu et pas encore lu.
    func discardInput() async throws {
        try await transport.discardInput()
        decoder.reset()
        pending.removeAll()
        flushStrayBytes()
    }

    // MARK: Commandes

    struct Reply: Sendable {
        var value: UInt32
        var payload: Data
    }

    /// Envoie `command` et attend sa réponse. Lève `ProtocolError.deviceError` si la puce
    /// signale un échec.
    func execute(_ command: Command, timeout: Duration = defaultTimeout) async throws -> Reply {
        try await send(command)
        let response = try await receive(opcode: command.opcode, timeout: timeout)
        return try check(response, opcode: command.opcode)
    }

    func send(_ command: Command) async throws {
        emit(.sent(opcode: command.opcode, payload: command.payload))
        try await transport.write(SLIP.encode(command.encoded()))
    }

    /// Lit des paquets jusqu'à trouver une réponse à `opcode`. Les autres paquets sont ignorés.
    func receive(opcode: UInt8, timeout: Duration) async throws -> Response {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var skipped = 0
        while true {
            let packet = try await nextPacket(until: deadline, opcode: opcode, timeout: timeout)
            if let response = Response(packet: packet), response.opcode == opcode {
                return response
            }
            skipped += 1
            if skipped >= Self.maxSkippedPackets {
                throw ProtocolError.invalidResponse("aucune réponse à \(hex(opcode)) parmi \(skipped) paquets")
            }
        }
    }

    /// Envoie une trame SLIP hors protocole de commande (accusé de réception de READ_FLASH).
    func sendRaw(_ payload: Data) async throws {
        emit(.rawBytes(direction: .sent, payload))
        try await transport.write(SLIP.encode(payload))
    }

    /// Prochaine trame reçue, quelle qu'elle soit : `OHAI` du stub, bloc de READ_FLASH…
    func receivePacket(timeout: Duration, opcode: UInt8? = nil) async throws -> Data {
        let deadline = ContinuousClock().now + timeout
        return try await nextPacket(until: deadline, opcode: opcode, timeout: timeout)
    }

    /// Contrôle l'état d'une réponse et rend sa valeur et ses données utiles.
    func checked(_ response: Response) throws -> Reply {
        try check(response, opcode: response.opcode)
    }

    /// Lit les octets disponibles jusqu'à ce qu'aucun paquet n'arrive pendant `quietPeriod`.
    /// Sert à vider les réponses SYNC excédentaires.
    func drain(quietPeriod: Duration) async throws {
        while true {
            let data = try await transport.read(maxCount: 4096, timeout: quietPeriod)
            if data.isEmpty { break }
            pending.append(contentsOf: try decode(data))
        }
        pending.removeAll()
        flushStrayBytes()
    }

    // MARK: Interne

    private func check(_ response: Response, opcode: UInt8) throws -> Reply {
        let length = statusLength ?? (response.body.count >= 4 ? 4 : 2)
        guard let split = response.split(statusLength: length) else {
            throw ProtocolError.invalidResponse("réponse à \(hex(opcode)) trop courte (\(response.body.count) o)")
        }
        emit(.received(opcode: response.opcode, value: response.value, payload: split.payload, status: split.status))
        guard split.status == 0 else {
            // La ROM met 1 dans l'octet d'état et la raison dans le suivant ; le stub v2 envoie
            // un code sur 16 bits en big-endian (0xC000…), dont seul le premier octet est non nul.
            let code = split.error != 0 ? split.error : split.status
            throw ProtocolError.deviceError(opcode: opcode, code: DeviceErrorCode(rawValue: code))
        }
        return Reply(value: response.value, payload: split.payload)
    }

    private func nextPacket(until deadline: ContinuousClock.Instant, opcode: UInt8?,
                            timeout: Duration) async throws -> Data {
        let clock = ContinuousClock()
        while pending.isEmpty {
            let remaining = deadline - clock.now
            guard remaining > .zero else { throw ProtocolError.timeout(opcode: opcode, after: timeout) }
            try Task.checkCancellation()
            let data = try await transport.read(maxCount: 4096, timeout: min(remaining, .milliseconds(100)))
            if !data.isEmpty {
                pending.append(contentsOf: try decode(data))
            }
        }
        return pending.removeFirst()
    }

    private func decode(_ data: Data) throws -> [Data] {
        do {
            let packets = try decoder.feed(data)
            flushStrayBytes()
            return packets
        } catch {
            flushStrayBytes()
            throw ProtocolError.invalidResponse("trame SLIP invalide (\(error))")
        }
    }

    private func flushStrayBytes() {
        let stray = decoder.takeStrayBytes()
        if !stray.isEmpty { emit(.rawBytes(direction: .received, stray)) }
    }
}
