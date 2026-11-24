// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPProtocol
import ESPImage
import ESPTargets

extension ESPDevice {
    /// Reads memory (ROM, RAM, registers) one 32-bit word at a time with READ_REG.
    /// `address` must be a multiple of 4; `count` is rounded up to whole words, then trimmed.
    /// Reading an unmapped address can hang or reset the chip.
    /// - Throws: `UsageError.invalidArgument`, `UsageError.unavailableInSecureDownloadMode`,
    ///   `ProtocolError`, `TransportError`, `CancellationError`.
    public nonisolated func readMemory(at address: UInt32, count: Int) -> ESPOperation<Data> {
        ESPOperation { sink in try await self.performReadMemory(at: address, count: count, sink: sink) }
    }

    /// Copies `image` into RAM with the memory commands, then jumps to its entry point.
    /// Ends the session: the actor moves to `.closed` without a reset, and the transport is closed.
    /// Works under ROM and under the stub. Segments must target RAM; flash-mapped segments
    /// (IROM/DROM) are refused.
    /// - Throws: `UsageError.invalidArgument`, `UsageError.unavailableInSecureDownloadMode`,
    ///   `ProtocolError`, `TransportError`.
    public func loadRAMAndRun(_ image: FirmwareImage) async throws {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("Loading code into RAM")
            if let target = image.chip, target != chip {
                throw UsageError.imageIncompatible("the image targets \(target.displayName), the chip is an \(chip)")
            }
            guard !image.segments.isEmpty else { throw UsageError.invalidArgument("the image has no segment") }
            let flashMapped: [MemoryRegion] = [.irom, .drom, .flash]
            if let flashMapped = image.segments.first(where: { $0.region.map(flashMapped.contains) == true }) {
                throw UsageError.invalidArgument("segment at \(hex(flashMapped.loadAddress)) is mapped from flash")
            }
            for segment in image.segments where !segment.data.isEmpty && segment.region != .padding {
                try await rawLoadSegment(segment.data, at: segment.loadAddress)
            }
            // MEM_END: first word 0 to jump to the entry point. Some ROMs jump before answering.
            try await channel.send(Command(.memEnd, payload: .le(UInt32(0), image.entryPoint)))
            if let packet = try? await channel.receivePacket(timeout: .milliseconds(500), opcode: Opcode.memEnd.rawValue),
               let response = Response(packet: packet), response.opcode == Opcode.memEnd.rawValue {
                _ = try await channel.checked(response)
            }
            await close()
        }
    }

    /// Leaves the bootloader and starts the application in flash. Ends the session.
    ///
    /// The chip is reset with the boot strapping released, like `disconnect(.hard)` (over
    /// USB-Serial-JTAG, the port goes away while the chip restarts). The ROM's FLASH_END
    /// "run user code" is not used: it only calls a ROM user-start hook, empty by default, so the
    /// application does not start (seen on the ESP32, which prints "user code done", and on the
    /// ESP32-S3); the stub v2 does not implement it either.
    /// - Throws: `UsageError.unavailableInSecureDownloadMode`, `TransportError`.
    public func runFlashApplication() async throws {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("Starting the application")
            let overUSB = channel.transport.usbIdentity?.isEspressifUSBSerialJTAG ?? false
            try await performReset(.hardReset(overUSB: overUSB))
            await close()
        }
    }

    // MARK: Flash status registers and SFDP

    /// Reads the flash status register: RDSR (0x05), then RDSR2 (0x35) and RDSR3 (0x15),
    /// one byte each, the first one in the low byte.
    /// - Throws: `UsageError.invalidArgument` (`byteCount` outside 1…3), `ProtocolError`, `TransportError`.
    public func readFlashStatus(byteCount: Int = 2) async throws -> UInt32 {
        try await exclusive {
            try await ensureFlashAttached("Reading the flash status")
            return try await rawReadFlashStatus(byteCount: byteCount)
        }
    }

    /// Writes the flash status register. `nonVolatile` sends WREN (0x06), which makes the value
    /// survive a power cycle; otherwise "volatile SR write enable" (0x50).
    /// The value is first written as a single WRSR (0x01) of `byteCount` bytes; if the read-back
    /// differs, each byte is written on its own (WRSR 0x01, WRSR2 0x31, WRSR3 0x11). WRDI (0x04) at the end.
    /// A wrong value can write-protect the flash or disable its quad mode.
    /// - Throws: `UsageError.invalidArgument`, `FlashError.statusMismatch`, `ProtocolError`, `TransportError`.
    public func writeFlashStatus(_ value: UInt32, byteCount: Int = 2, nonVolatile: Bool = false) async throws {
        try await exclusive {
            try await ensureFlashAttached("Writing the flash status")
            guard (1...3).contains(byteCount) else { throw UsageError.invalidArgument("status of \(byteCount) bytes (1 to 3)") }
            guard value >> (8 * UInt32(byteCount)) == 0 else {
                throw UsageError.invalidArgument("\(hex(value)) does not fit in \(byteCount) bytes")
            }
            let enable: UInt8 = nonVolatile ? 0x06 : 0x50
            let bytes = (0..<byteCount).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) }

            _ = try await rawSPICommand(enable, data: Data(), readBits: 0)
            _ = try await rawSPICommand(0x01, data: Data(bytes), readBits: 0)
            try await waitForFlashIdle()
            var actual = try await rawReadFlashStatus(byteCount: byteCount)
            if actual != value && byteCount > 1 {
                for (opcode, byte) in zip([UInt8(0x01), 0x31, 0x11], bytes) {
                    _ = try await rawSPICommand(enable, data: Data(), readBits: 0)
                    _ = try await rawSPICommand(opcode, data: Data([byte]), readBits: 0)
                    try await waitForFlashIdle()
                }
                actual = try await rawReadFlashStatus(byteCount: byteCount)
            }
            _ = try await rawSPICommand(0x04, data: Data(), readBits: 0)
            guard actual == value else { throw FlashError.statusMismatch(expected: value, actual: actual) }
        }
    }

    /// Reads the flash SFDP table (RDSFDP, 0x5A: 24-bit address and 8 dummy cycles), 4 bytes per transaction.
    /// - Throws: `UsageError.invalidArgument`, `ProtocolError`, `TransportError`.
    public func readSFDP(at address: UInt32, count: Int) async throws -> Data {
        try await exclusive {
            try await ensureFlashAttached("Reading the SFDP table")
            guard count > 0, Int(address) + count <= 1 << 24 else {
                throw UsageError.invalidArgument("SFDP read of \(count) bytes at \(hex(address))")
            }
            var out = Data(capacity: count)
            while out.count < count {
                try Task.checkCancellation()
                let word = try await rawSPICommand(0x5A, data: Data(), readBits: 32,
                                                   address: address + UInt32(out.count), addressBits: 24, dummyBits: 8)
                out.append(Data.le(word).prefix(count - out.count))
            }
            return out
        }
    }
}

// MARK: - Implementation

extension ESPDevice {
    func performReadMemory(at address: UInt32, count: Int, sink: ProgressSink) async throws -> Data {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("Reading memory")
            guard address % 4 == 0 else { throw UsageError.invalidArgument("address \(hex(address)) is not a multiple of 4") }
            guard count > 0, UInt64(address) + UInt64(count) <= 1 << 32 else {
                throw UsageError.invalidArgument("reading \(count) bytes at \(hex(address))")
            }
            let words = (count + 3) / 4
            var out = Data(capacity: words * 4)
            for index in 0..<words {
                try Task.checkCancellation()
                out.append(.le(try await rawReadRegister(address + UInt32(index * 4))))
                if index % 256 == 255 || index == words - 1 {
                    sink.report(OperationProgress(stage: .reading, regionIndex: 0, regionCount: 1,
                                                  completedBytes: min(out.count, count), totalBytes: count))
                }
            }
            return out.prefix(count)
        }
    }

    /// One segment in RAM: MEM_BEGIN then MEM_DATA blocks of 6 KiB.
    func rawLoadSegment(_ segment: Data, at address: UInt32) async throws {
        let blockSize = 0x1800
        let blocks = (segment.count + blockSize - 1) / blockSize
        _ = try await channel.execute(Command(.memBegin, payload: .le(UInt32(segment.count), UInt32(blocks),
                                                                     UInt32(blockSize), address)))
        for sequence in 0..<blocks {
            let start = segment.startIndex + sequence * blockSize
            let chunk = segment.subdata(in: start..<min(start + blockSize, segment.endIndex))
            var payload = Data.le(UInt32(chunk.count), UInt32(sequence), UInt32(0), UInt32(0))
            payload.append(chunk)
            _ = try await channel.execute(Command(.memData, payload: payload, checksum: Command.checksum(of: chunk)))
        }
    }

    private func ensureFlashAttached(_ operation: String) async throws {
        try ensureOpen()
        try ensureNotSecureDownload(operation)
        if attachedFlash == nil { _ = try await rawAttachFlash(.default, type: .nor) }
    }

    private func rawReadFlashStatus(byteCount: Int) async throws -> UInt32 {
        guard (1...3).contains(byteCount) else { throw UsageError.invalidArgument("status of \(byteCount) bytes (1 to 3)") }
        var value: UInt32 = 0
        for (index, opcode) in [UInt8(0x05), 0x35, 0x15].prefix(byteCount).enumerated() {
            value |= try await rawSPICommand(opcode, data: Data(), readBits: 8) << (8 * UInt32(index))
        }
        return value
    }

    /// Polls the WIP bit (status bit 0) for up to about a second.
    private func waitForFlashIdle() async throws {
        for _ in 0..<100 {
            if try await rawSPICommand(0x05, data: Data(), readBits: 8) & 1 == 0 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ProtocolError.invalidResponse("the flash stays busy after a status write")
    }
}
