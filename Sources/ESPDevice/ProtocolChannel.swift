// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPProtocol
import ESPTransport

/// Command/response exchange over a `Transport`: SLIP framing, waiting for the matching
/// response, status checking and tracing.
actor ProtocolChannel {
    let transport: any Transport
    private let trace: AsyncStream<TraceEvent>.Continuation?
    private var decoder = SLIPDecoder()
    private var pending: [Data] = []

    /// Size of the status block at the end of a response; `nil` until the chip is identified.
    var statusLength: Int?

    static let defaultTimeout: Duration = .seconds(3)
    /// Maximum number of packets read to find the expected response
    /// (the ESP8266 sends extra SYNC responses).
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

    /// Forgets everything received but not yet read.
    func discardInput() async throws {
        try await transport.discardInput()
        decoder.reset()
        pending.removeAll()
        flushStrayBytes()
    }

    // MARK: Commands

    struct Reply: Sendable {
        var value: UInt32
        var payload: Data
    }

    /// Sends `command` and waits for its response. Throws `ProtocolError.deviceError` if the chip
    /// reports a failure.
    func execute(_ command: Command, timeout: Duration = defaultTimeout) async throws -> Reply {
        try await send(command)
        let response = try await receive(opcode: command.opcode, timeout: timeout)
        return try check(response, opcode: command.opcode)
    }

    func send(_ command: Command) async throws {
        emit(.sent(opcode: command.opcode, payload: command.payload))
        try await transport.write(SLIP.encode(command.encoded()))
    }

    /// Reads packets until a response to `opcode` shows up. Other packets are ignored.
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
                throw ProtocolError.invalidResponse("no response to \(hex(opcode)) among \(skipped) packets")
            }
        }
    }

    /// Sends a SLIP frame outside the command protocol (READ_FLASH acknowledgement).
    func sendRaw(_ payload: Data) async throws {
        emit(.rawBytes(direction: .sent, payload))
        try await transport.write(SLIP.encode(payload))
    }

    /// Next received frame, whatever it is: the stub's `OHAI`, a READ_FLASH block…
    func receivePacket(timeout: Duration, opcode: UInt8? = nil) async throws -> Data {
        let deadline = ContinuousClock().now + timeout
        return try await nextPacket(until: deadline, opcode: opcode, timeout: timeout)
    }

    /// Checks a response's status and returns its value and payload.
    func checked(_ response: Response) throws -> Reply {
        try check(response, opcode: response.opcode)
    }

    /// Reads the available bytes until no packet arrives for `quietPeriod`.
    /// Used to drain extra SYNC responses.
    func drain(quietPeriod: Duration) async throws {
        while true {
            let data = try await transport.read(maxCount: 4096, timeout: quietPeriod)
            if data.isEmpty { break }
            pending.append(contentsOf: try decode(data))
        }
        pending.removeAll()
        flushStrayBytes()
    }

    // MARK: Internals

    private func check(_ response: Response, opcode: UInt8) throws -> Reply {
        let length = statusLength ?? (response.body.count >= 4 ? 4 : 2)
        guard let split = response.split(statusLength: length) else {
            throw ProtocolError.invalidResponse("response to \(hex(opcode)) too short (\(response.body.count) bytes)")
        }
        emit(.received(opcode: response.opcode, value: response.value, payload: split.payload, status: split.status))
        guard split.status == 0 else {
            // The ROM puts 1 in the status byte and the reason in the next one; stub v2 sends
            // a big-endian 16-bit code (0xC000…), whose first byte only is non-zero.
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
            throw ProtocolError.invalidResponse("invalid SLIP frame (\(error))")
        }
    }

    private func flushStrayBytes() {
        let stray = decoder.takeStrayBytes()
        if !stray.isEmpty { emit(.rawBytes(direction: .received, stray)) }
    }
}
