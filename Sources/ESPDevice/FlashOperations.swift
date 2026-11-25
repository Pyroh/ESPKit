// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPImage
import ESPSupport
import ESPTargets

/// Settings of `ESPDevice.writeFlash(_:options:)`.
public struct WriteFlashOptions: Hashable, Sendable {
    /// `.automatic`: zlib, except under the ESP8266 ROM.
    public var compression: Compression = .automatic
    /// How the data travels over the link.
    public enum Compression: Hashable, Sendable {
        /// zlib whenever the chip can inflate it.
        case automatic
        /// Always zlib (FLASH_DEFL_* commands).
        case zlib
        /// Raw (FLASH_* commands).
        case none
    }
    /// Erase the whole flash before writing (stub required).
    public var eraseAll: Bool = false
    /// Applied to the region holding a bootloader (detected at `chip.bootloaderOffset`).
    public var headerOverrides: FlashHeaderOverrides = .keep
    /// What to check once a region is written.
    public var verification: Verification = .md5
    /// Post-write check.
    public enum Verification: Hashable, Sendable {
        /// Compare the chip's MD5 of the region with the data's (`FlashError.md5Mismatch`).
        case md5
        /// No check.
        case none
    }
    /// Differential reflash: content assumed to be present already, matched to the new regions
    /// by address. Only the 4 KiB sectors that differ are sent; missing bytes count as 0xFF.
    /// Cannot be combined with `skipIfUnchanged` or encrypted regions.
    public var previousContents: [FlashRegion]? = nil
    /// With `previousContents`: do not ask the chip for the MD5 of the old content first.
    /// Without it, a region whose flash does not hold the old content is written in full.
    public var trustPreviousContents: Bool = false
    /// Compare MD5s first and write nothing if the flash already holds the data.
    /// Not applied to encrypted regions.
    public var skipIfUnchanged: Bool = false
    /// Write `encrypt` regions even if the eFuses do not enable flash encryption.
    public var ignoreEncryptionEfuses: Bool = false
    /// Disable the safeguards (active security, image incompatible with the chip).
    public var force: Bool = false
    /// Flash wiring, for boards that do not use the default pins.
    public var spiConnection: SPIConnection = .default
    /// Only `.nor` is supported for now.
    public var flashType: FlashType = .nor

    /// The defaults: automatic compression, MD5 check, no erase, no differential write.
    public init() {}
}

/// Result of `ESPDevice.writeFlash(_:options:)`.
public struct WriteFlashReport: Hashable, Sendable {
    /// One entry per region, in the order written.
    public var regions: [Region]

    /// What happened to one region.
    public struct Region: Hashable, Sendable {
        /// Flash offset actually written (sector-aligned under ROM).
        public var address: UInt32
        /// Bytes written, after alignment and header patching.
        public var byteCount: Int
        /// Bytes sent over the link, after compression and the differential reflash.
        public var bytesSent: Int
        /// True if nothing was written: `skipIfUnchanged` found the data already in place,
        /// or `previousContents` held the same bytes.
        public var skipped: Bool
        /// True if the bootloader header was changed (`headerOverrides`).
        public var headerPatched: Bool
        /// MD5 of the written data (plaintext). `nil` for an encrypted region, which is not verified.
        public var md5: MD5Digest?
        /// Time spent on this region, verification included.
        public var duration: Duration
    }
}

/// Outcome of ``ESPDevice/verifyFlash(_:)`` for one region.
public enum VerifyResult: Hashable, Sendable {
    /// The flash holds exactly the region's data.
    case match(address: UInt32)
    /// The flash differs; `firstDifferences` lists at most the first 16 differing bytes.
    case mismatch(address: UInt32, firstDifferences: [ByteDifference])
}

/// One byte that differs between the expected data and the flash.
public struct ByteDifference: Hashable, Sendable {
    /// Offset from the start of the region.
    public var offset: Int
    /// Byte of the data.
    public var expected: UInt8
    /// Byte read from the flash.
    public var actual: UInt8

    /// A difference at `offset`.
    public init(offset: Int, expected: UInt8, actual: UInt8) {
        self.offset = offset
        self.expected = expected
        self.actual = actual
    }
}

extension ESPDevice {
    /// Writes the regions in the given order. Nothing is sent until the operation is iterated
    /// or `.value` is awaited.
    /// - Rejects empty regions, overlapping regions and regions past the end of the flash (`UsageError.invalidArgument`).
    /// - Patches the bootloader header according to `headerOverrides` and recomputes its SHA-256.
    /// - Refuses an image built for another chip, or a write below 0x8000 with Secure Boot enabled,
    ///   unless `force`.
    /// - On cancellation: the flash is partially written and the chip stays in the stub.
    /// - Encrypted regions (`FlashRegion.encrypt`): the chip encrypts with its own key while
    ///   writing. They are sent uncompressed, padded with 0xFF to 16 bytes (32 on the ESP32), and
    ///   not verified (the flash holds the ciphertext). Their address must be aligned the same way.
    ///   Refused unless flash encryption is enabled in the eFuses, or `ignoreEncryptionEfuses`.
    ///   Needs the stub on the ESP32 (its ROM cannot encrypt); refused on the ESP8266.
    ///
    /// - Throws: `TransportError`, `ConnectionError.disconnected`, `ProtocolError`, `UsageError`
    ///   (invalid regions, safeguards), `FlashError.md5Mismatch`, `CancellationError`.
    public nonisolated func writeFlash(_ regions: [FlashRegion],
                                       options: WriteFlashOptions = .init()) -> ESPOperation<WriteFlashReport> {
        ESPOperation { sink in try await self.performWriteFlash(regions, options: options, sink: sink) }
    }

    /// Writes a build without giving its addresses: the bootloader at the chip's
    /// `bootloaderOffset`, the partition table at `regions.partitionTableOffset`, the application
    /// in the partition the bootloader boots, and an erased `otadata` partition if the table has one.
    ///
    /// The addresses are resolved with `FlashRegions.resolved(for:)` for the connected chip when
    /// the operation runs; everything else is the same as writing those regions.
    ///
    /// - Throws: `PartitionTableError` if the partition table cannot be read or the files do not
    ///   fit, then the errors of ``writeFlash(_:options:)-([FlashRegion],_)``.
    public nonisolated func writeFlash(_ regions: FlashRegions,
                                       options: WriteFlashOptions = .init()) -> ESPOperation<WriteFlashReport> {
        ESPOperation { sink in
            try await self.performWriteFlash(regions.resolved(for: self.chip), options: options, sink: sink)
        }
    }

    /// Reads the flash. `count == nil`: up to the end of the detected flash.
    /// With the stub, the read is checked against the MD5 the chip sends at the end.
    /// - Throws: `TransportError`, `ConnectionError.disconnected`, `ProtocolError`, `UsageError`,
    ///   `FlashError.md5Mismatch`, `CancellationError`.
    public nonisolated func readFlash(at address: UInt32, count: Int?) -> ESPOperation<Data> {
        ESPOperation { sink in try await self.performReadFlash(at: address, count: count, sink: sink) }
    }

    /// MD5 computed by the chip, without transferring the data.
    /// - Throws: `UsageError.unsupported` under the ESP8266 ROM, `ProtocolError`, `TransportError`.
    public func flashMD5(at address: UInt32, count: Int) async throws -> MD5Digest {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("The flash MD5")
            if attachedFlash == nil { _ = try await rawAttachFlash(.default, type: .nor) }
            return try await rawFlashMD5(at: address, count: count)
        }
    }

    /// Returns one entry per region: a match, or the first differing bytes.
    public nonisolated func verifyFlash(_ regions: [FlashRegion]) -> ESPOperation<[VerifyResult]> {
        ESPOperation { sink in try await self.performVerifyFlash(regions, sink: sink) }
    }

    /// Full erase, which can take tens of seconds. Stub required. Refused if a security
    /// feature is enabled, unless `force`. Progress has a single step: the chip does not report
    /// how far it got.
    public nonisolated func eraseFlash(force: Bool = false) -> ESPOperation<Void> {
        ESPOperation { sink in try await self.performEraseFlash(force: force, sink: sink) }
    }

    /// Erases a region. `address` and `count` must be multiples of 4,096. Stub required.
    public func eraseRegion(at address: UInt32, count: Int, force: Bool = false) async throws {
        try await exclusive {
            try ensureFlashCommandsAvailable("Erasing a region")
            guard address % 0x1000 == 0, count % 0x1000 == 0, count > 0 else {
                throw UsageError.invalidArgument("address and size must be multiples of 4,096 bytes")
            }
            if !force { try checkEraseGuards() }
            _ = try await channel.execute(Command(.eraseRegion, payload: .le(address, UInt32(count))),
                                          timeout: FlashTimeouts.eraseRegion(bytes: count))
        }
    }
}

// MARK: - Implementation

/// Timeouts modelled on esptool's defaults.
enum FlashTimeouts {
    static let minimum: Duration = .seconds(3)
    static let chipErase: Duration = .seconds(120)

    static func eraseWrite(bytes: Int) -> Duration { scaled(secondsPerMB: 40, bytes: bytes) }
    static func md5(bytes: Int) -> Duration { scaled(secondsPerMB: 8, bytes: bytes) }
    static func eraseRegion(bytes: Int) -> Duration { scaled(secondsPerMB: 30, bytes: bytes) }

    private static func scaled(secondsPerMB: Double, bytes: Int) -> Duration {
        max(minimum, .milliseconds(Int(secondsPerMB * 1000 * Double(bytes) / 1_048_576)))
    }
}

extension ESPDevice {
    struct PreparedRegion {
        var address: UInt32
        var data: Data
        var headerPatched: Bool
        var encrypt = false
    }

    func performWriteFlash(_ regions: [FlashRegion], options: WriteFlashOptions,
                           sink: ProgressSink) async throws -> WriteFlashReport {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("Writing the flash")
            guard options.flashType == .nor else {
                throw UsageError.unsupported(feature: "NAND flash", chip: chip, state: state)
            }
            let encrypted = regions.contains(where: \.encrypt)
            if options.previousContents != nil {
                if encrypted { throw UsageError.invalidArgument("a differential reflash cannot write encrypted regions") }
                if options.skipIfUnchanged { throw UsageError.invalidArgument("previousContents and skipIfUnchanged exclude each other") }
            }
            if encrypted {
                if chip == .esp8266 { throw UsageError.unsupported(feature: "Encrypted writes", chip: chip, state: state) }
                if !stubRunning && !descriptor.romFlashBeginHasEncryptionWord {
                    throw UsageError.unsupported(feature: "Encrypted writes under ROM (load the stub)", chip: chip, state: state)
                }
                if !options.ignoreEncryptionEfuses, try await !rawFlashEncryptionEnabled() {
                    throw UsageError.securityRestriction("flash encryption is not enabled in the eFuses (ignoreEncryptionEfuses to write anyway)")
                }
            }
            if chip == .esp8266 && !stubRunning {
                // The ESP8266 ROM erases too much; the stub does not have this flaw.
                throw UsageError.unsupported(feature: "Writing the flash under ROM (load the stub)", chip: chip, state: state)
            }
            let compress = options.compression != .none

            let flash = options.spiConnection == .default && attachedFlash != nil
                ? attachedFlash!
                : try await rawAttachFlash(options.spiConnection, type: .nor)
            let flashSize = flash.detectedSize?.byteCount ?? FlashSize.mb4.byteCount
            try validate(regions, flashSize: flashSize)
            if !options.force { try checkWriteGuards(regions) }

            let prepared = try regions.map { try prepare($0, overrides: options.headerOverrides, flash: flash) }
            let previous = try options.previousContents.map { contents in
                try Dictionary(contents.map { ($0.address, try prepare($0, overrides: options.headerOverrides, flash: flash).data) },
                               uniquingKeysWith: { _, last in last })
            }
            let total = prepared.reduce(0) { $0 + $1.data.count }
            sink.report(OperationProgress(stage: .preparing, regionIndex: 0, regionCount: prepared.count,
                                          completedBytes: 0, totalBytes: total))
            if options.eraseAll {
                guard stubRunning else {
                    throw UsageError.unsupported(feature: "Full erase", chip: chip, state: state)
                }
                if !options.force { try checkEraseGuards() }
                sink.report(OperationProgress(stage: .erasing, regionIndex: 0, regionCount: prepared.count,
                                              completedBytes: 0, totalBytes: total))
                _ = try await channel.execute(Command(.eraseFlash), timeout: FlashTimeouts.chipErase)
            }

            var reports: [WriteFlashReport.Region] = []
            var done = 0
            for (index, region) in prepared.enumerated() {
                try Task.checkCancellation()
                let started = ContinuousClock.now
                let md5 = MD5Digest(bytes: MD5.hash(region.data))!
                var chunks = [0..<region.data.count]
                if let old = previous?[region.address] {
                    chunks = Self.changedChunks(old: old, new: region.data, address: region.address)
                    if !chunks.isEmpty && !options.trustPreviousContents {
                        let expected = Self.padded(old, to: region.data.count)
                        if try await rawFlashMD5(at: region.address, count: region.data.count) != MD5Digest(bytes: MD5.hash(expected))! {
                            chunks = [0..<region.data.count]       // the flash does not hold the old content
                        }
                    }
                }
                var unchanged = chunks.isEmpty
                if !unchanged && options.skipIfUnchanged && !region.encrypt {
                    unchanged = try await rawFlashMD5(at: region.address, count: region.data.count) == md5
                }
                if unchanged {
                    done += region.data.count
                    sink.report(OperationProgress(stage: .writing, regionIndex: index, regionCount: prepared.count,
                                                  completedBytes: done, totalBytes: total))
                    reports.append(.init(address: region.address, byteCount: region.data.count, bytesSent: 0,
                                         skipped: true, headerPatched: region.headerPatched, md5: md5,
                                         duration: .now - started))
                    continue
                }
                var sent = 0
                let chunkTotal = chunks.reduce(0) { $0 + $1.count }
                var chunkDone = 0
                for chunk in chunks {
                    let base = done, before = chunkDone
                    let data = region.data.subdata(in: region.data.startIndex + chunk.lowerBound..<region.data.startIndex + chunk.upperBound)
                    sent += try await rawWrite(data, at: region.address + UInt32(chunk.lowerBound),
                                               compress: compress && !region.encrypt, encrypt: region.encrypt) { written in
                        // Progress counts the whole region; a differential write covers it proportionally.
                        let fraction = Double(before + written) / Double(max(chunkTotal, 1))
                        sink.report(OperationProgress(stage: .writing, regionIndex: index, regionCount: prepared.count,
                                                      completedBytes: base + Int(fraction * Double(region.data.count)), totalBytes: total))
                    }
                    chunkDone += chunk.count
                }
                done += region.data.count
                if region.encrypt {
                    reports.append(.init(address: region.address, byteCount: region.data.count, bytesSent: sent,
                                         skipped: false, headerPatched: region.headerPatched, md5: nil,
                                         duration: .now - started))
                    continue
                }
                if options.verification == .md5 {
                    sink.report(OperationProgress(stage: .verifying, regionIndex: index, regionCount: prepared.count,
                                                  completedBytes: done, totalBytes: total))
                    let actual = try await rawFlashMD5(at: region.address, count: region.data.count)
                    guard actual == md5 else {
                        throw FlashError.md5Mismatch(address: region.address, expected: md5, actual: actual)
                    }
                }
                reports.append(.init(address: region.address, byteCount: region.data.count, bytesSent: sent,
                                     skipped: false, headerPatched: region.headerPatched, md5: md5,
                                     duration: .now - started))
            }
            return WriteFlashReport(regions: reports)
        }
    }

    func performReadFlash(at address: UInt32, count: Int?, sink: ProgressSink) async throws -> Data {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("Reading the flash")
            let flash = try await currentFlash()
            let flashSize = flash.detectedSize?.byteCount ?? FlashSize.mb4.byteCount
            let length = count ?? (flashSize - Int(address))
            guard length > 0, Int(address) + length <= flashSize else {
                throw UsageError.invalidArgument("reading \(length) bytes at \(hex(address)) goes past the flash (\(flashSize) bytes)")
            }
            return try await rawReadFlash(at: address, count: length) { read in
                sink.report(OperationProgress(stage: .reading, regionIndex: 0, regionCount: 1,
                                              completedBytes: read, totalBytes: length))
            }
        }
    }

    func performVerifyFlash(_ regions: [FlashRegion], sink: ProgressSink) async throws -> [VerifyResult] {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("Verifying the flash")
            _ = try await currentFlash()
            let total = regions.reduce(0) { $0 + $1.data.count }
            var done = 0
            var results: [VerifyResult] = []
            for (index, region) in regions.enumerated() {
                try Task.checkCancellation()
                guard !region.data.isEmpty else { results.append(.match(address: region.address)); continue }
                let expected = MD5Digest(bytes: MD5.hash(region.data))!
                if try await rawFlashMD5(at: region.address, count: region.data.count) == expected {
                    results.append(.match(address: region.address))
                } else {
                    let base = done
                    let actual = try await rawReadFlash(at: region.address, count: region.data.count) { read in
                        sink.report(OperationProgress(stage: .verifying, regionIndex: index, regionCount: regions.count,
                                                      completedBytes: base + read, totalBytes: total))
                    }
                    results.append(.mismatch(address: region.address,
                                             firstDifferences: Self.differences(expected: region.data, actual: actual)))
                }
                done += region.data.count
                sink.report(OperationProgress(stage: .verifying, regionIndex: index, regionCount: regions.count,
                                              completedBytes: done, totalBytes: total))
            }
            return results
        }
    }

    func performEraseFlash(force: Bool, sink: ProgressSink) async throws {
        try await exclusive {
            try ensureFlashCommandsAvailable("Full erase")
            if !force { try checkEraseGuards() }
            sink.report(OperationProgress(stage: .erasing, regionIndex: 0, regionCount: 1, completedBytes: 0, totalBytes: 1))
            _ = try await channel.execute(Command(.eraseFlash), timeout: FlashTimeouts.chipErase)
            sink.report(OperationProgress(stage: .erasing, regionIndex: 0, regionCount: 1, completedBytes: 1, totalBytes: 1))
        }
    }

    // MARK: Primitives (called under `exclusive`)

    private func currentFlash() async throws -> FlashInfo {
        if let attachedFlash { return attachedFlash }
        return try await rawAttachFlash(.default, type: .nor)
    }

    private func ensureFlashCommandsAvailable(_ operation: String) throws {
        try ensureOpen()
        try ensureNotSecureDownload(operation)
        guard stubRunning else { throw UsageError.unsupported(feature: "\(operation) (stub required)", chip: chip, state: state) }
    }

    /// Sends `data` to `address` in blocks: 16 KiB with the stub, 1 KiB under ROM.
    /// - Returns: the number of bytes sent (after compression).
    private func rawWrite(_ data: Data, at address: UInt32, compress: Bool, encrypt: Bool = false,
                          progress: (Int) -> Void) async throws -> Int {
        let blockSize = stubRunning ? 0x4000 : 0x400
        let wire = compress ? try Zlib.compress(data) : data
        let blocks = max(1, (wire.count + blockSize - 1) / blockSize)
        // Uncompressed/compressed ratio: used to estimate the chip's work per block.
        let ratio = Double(data.count) / Double(max(wire.count, 1))

        // The stub wants the uncompressed size; the ROM, the size to erase.
        let size = stubRunning || !compress ? data.count : (data.count + 0xFFF) / 0x1000 * 0x1000
        var begin = Data.le(UInt32(size), UInt32(blocks), UInt32(blockSize), address)
        // Fifth word, "encrypt": always expected by the S2+ ROM, accepted by the stub.
        if encrypt || (!stubRunning && descriptor.romFlashBeginHasEncryptionWord) { begin.appendLE(UInt32(encrypt ? 1 : 0)) }
        // The ROM erases the whole area in FLASH_BEGIN; the stub erases as it goes.
        let beginTimeout = stubRunning ? FlashTimeouts.minimum : FlashTimeouts.eraseWrite(bytes: data.count)
        _ = try await channel.execute(Command(compress ? .flashDeflBegin : .flashBegin, payload: begin), timeout: beginTimeout)

        for sequence in 0..<blocks {
            try Task.checkCancellation()
            let start = wire.startIndex + sequence * blockSize
            var chunk = wire.subdata(in: start..<min(start + blockSize, wire.endIndex))
            if !compress && chunk.count < blockSize {
                chunk.append(Data(repeating: 0xFF, count: blockSize - chunk.count))
            }
            var payload = Data.le(UInt32(chunk.count), UInt32(sequence), UInt32(0), UInt32(0))
            payload.append(chunk)
            // The stub acknowledges before writing: the timeout also covers the previous block.
            let work = Int(Double(blockSize) * ratio)
            _ = try await channel.execute(Command(compress ? .flashDeflData : .flashData, payload: payload,
                                                  checksum: Command.checksum(of: chunk)),
                                          timeout: FlashTimeouts.eraseWrite(bytes: 2 * work))
            progress(min(data.count, Int(Double((sequence + 1) * blockSize) * ratio)))
        }
        // Barrier: the stub only answers once the last block is actually written.
        _ = try await channel.execute(Command(.readReg, payload: .le(ChipDescriptor.magicRegister)),
                                      timeout: FlashTimeouts.eraseWrite(bytes: Int(Double(blockSize) * ratio)))
        return wire.count
    }

    func rawFlashMD5(at address: UInt32, count: Int) async throws -> MD5Digest {
        if chip == .esp8266 && !stubRunning {
            throw UsageError.unsupported(feature: "SPI_FLASH_MD5 under ROM", chip: chip, state: state)
        }
        let reply = try await channel.execute(Command(.spiFlashMD5, payload: .le(address, UInt32(count), UInt32(0), UInt32(0))),
                                              timeout: FlashTimeouts.md5(bytes: count))
        // The ROM returns 32 hex characters, the stub 16 raw bytes.
        let bytes: Data?
        switch reply.payload.count {
        case 32...: bytes = Self.decodeHex(reply.payload.prefix(32))
        case 16...: bytes = reply.payload.prefix(16)
        default: bytes = nil
        }
        guard let bytes, let digest = MD5Digest(bytes: Data(bytes)) else {
            throw ProtocolError.invalidResponse("SPI_FLASH_MD5: \(reply.payload.count) bytes")
        }
        return digest
    }

    private func rawReadFlash(at address: UInt32, count: Int, progress: (Int) -> Void) async throws -> Data {
        guard stubRunning else { return try await rawReadFlashSlow(at: address, count: count, progress: progress) }
        // If a frame is lost, the stub waits for an acknowledgement the host cannot send: the read
        // stops on a timeout. The read is then restarted from the last complete
        // chunk, at most twice.
        var out = Data(capacity: count)
        var retries = 0
        while out.count < count {
            let done = out.count
            do {
                out.append(try await rawReadFlashStream(at: address + UInt32(done), count: count - done) {
                    progress(done + $0)
                })
            } catch let error as ProtocolError {
                guard case .timeout = error, retries < 2 else { throw error }
                retries += 1
            }
        }
        return out
    }

    /// One READ_FLASH command: 4 KiB blocks, one acknowledgement per block, then the stub's MD5.
    private func rawReadFlashStream(at address: UInt32, count: Int, progress: (Int) -> Void) async throws -> Data {
        _ = try await channel.execute(Command(.readFlash, payload: .le(address, UInt32(count), UInt32(0x1000), UInt32(1))))
        var out = Data(capacity: count)
        do {
            while out.count < count {
                try Task.checkCancellation()
                let packet = try await channel.receivePacket(timeout: FlashTimeouts.minimum, opcode: Opcode.readFlash.rawValue)
                out.append(packet)
                guard out.count <= count else {
                    throw ProtocolError.invalidResponse("READ_FLASH: \(out.count) bytes received for \(count) requested")
                }
                // Acknowledgement: total received so far.
                try await channel.sendRaw(.le(UInt32(out.count)))
                progress(out.count)
            }
            let digest = try await channel.receivePacket(timeout: FlashTimeouts.minimum, opcode: Opcode.readFlash.rawValue)
            guard let expected = MD5Digest(bytes: digest) else {
                throw ProtocolError.invalidResponse("READ_FLASH: final MD5 of \(digest.count) bytes")
            }
            let actual = MD5Digest(bytes: MD5.hash(out))!
            guard actual == expected else { throw FlashError.md5Mismatch(address: address, expected: expected, actual: actual) }
            return out
        } catch {
            // Breaks the stub's send loop: a frame that is not an acknowledgement stops it.
            try? await channel.sendRaw(Data([0]))
            try? await channel.drain(quietPeriod: .milliseconds(200))
            throw error
        }
    }

    /// ROM read: 64 bytes per command.
    private func rawReadFlashSlow(at address: UInt32, count: Int, progress: (Int) -> Void) async throws -> Data {
        var out = Data(capacity: count)
        while out.count < count {
            try Task.checkCancellation()
            let wanted = min(64, count - out.count)
            let reply = try await channel.execute(Command(.readFlashSlow, payload: .le(address + UInt32(out.count), UInt32(64))))
            guard reply.payload.count >= wanted else {
                throw ProtocolError.invalidResponse("READ_FLASH_SLOW: \(reply.payload.count) bytes")
            }
            out.append(reply.payload.prefix(wanted))
            if out.count % 0x1000 == 0 || out.count == count { progress(out.count) }
        }
        return out
    }

    // MARK: Preparation and safeguards

    private func validate(_ regions: [FlashRegion], flashSize: Int) throws {
        for region in regions {
            guard !region.data.isEmpty else { throw UsageError.invalidArgument("empty region at \(hex(region.address))") }
            guard Int(region.address) + region.data.count <= flashSize else {
                throw UsageError.invalidArgument("region \(hex(region.address)) (\(region.data.count) bytes) goes past the flash (\(flashSize) bytes)")
            }
        }
        let sorted = regions.sorted { $0.address < $1.address }
        for (previous, next) in zip(sorted, sorted.dropFirst())
        where Int(previous.address) + previous.data.count > Int(next.address) {
            throw UsageError.invalidArgument("regions \(hex(previous.address)) and \(hex(next.address)) overlap")
        }
    }

    private func checkWriteGuards(_ regions: [FlashRegion]) throws {
        if cachedSecurityInfo?.flags.contains(.secureBootEnabled) == true,
           let low = regions.first(where: { $0.address < 0x8000 }) {
            throw UsageError.securityRestriction("Secure Boot enabled: write at \(hex(low.address)), below 0x8000")
        }
        guard chip != .esp8266, let expected = chip.imageChipID else { return }
        for region in regions where region.data.count >= 24 && region.data[region.data.startIndex] == 0xE9 {
            let id = UInt16(region.data[region.data.startIndex + 12]) | UInt16(region.data[region.data.startIndex + 13]) << 8
            guard id == expected else {
                let target = ChipFamily(imageChipID: id).map(\.displayName) ?? "chip ID \(id)"
                throw UsageError.imageIncompatible("the image at \(hex(region.address)) targets \(target), the chip is an \(chip)")
            }
        }
    }

    private func checkEraseGuards() throws {
        guard let info = cachedSecurityInfo else { return }
        if info.flags.contains(.secureBootEnabled) || info.flashEncryptionEnabled {
            throw UsageError.securityRestriction("Secure Boot or flash encryption enabled: erase refused")
        }
    }

    /// 4-byte alignment, header patching, and sector alignment under ROM.
    private func prepare(_ region: FlashRegion, overrides: FlashHeaderOverrides, flash: FlashInfo) throws -> PreparedRegion {
        var data = Data(region.data)
        var patched = false
        if region.address == chip.bootloaderOffset {
            patched = try patchHeader(&data, overrides: overrides, flash: flash)
        }
        let alignment = region.encrypt ? (chip == .esp32 ? 32 : 16) : 4
        if region.encrypt && region.address % UInt32(alignment) != 0 {
            throw UsageError.invalidArgument("encrypted region at \(hex(region.address)): address not a multiple of \(alignment)")
        }
        if data.count % alignment != 0 { data.append(Data(repeating: 0xFF, count: alignment - data.count % alignment)) }
        var address = region.address
        if !stubRunning, address % 0x1000 != 0 {
            // The ROM erases whole sectors: the start of the sector is filled with 0xFF.
            let misalignment = Int(address % 0x1000)
            data = Data(repeating: 0xFF, count: misalignment) + data
            address -= UInt32(misalignment)
        }
        return PreparedRegion(address: address, data: data, headerPatched: patched, encrypt: region.encrypt)
    }

    /// Flash encryption enabled: an odd number of bits in the eFuse counter. The ESP32 has no
    /// GET_SECURITY_INFO: FLASH_CRYPT_CNT is read from BLOCK0 (word 0, bits 20 to 26).
    private func rawFlashEncryptionEnabled() async throws -> Bool {
        if chip == .esp32 {
            let word = try await rawReadRegister(0x3FF5_A000)
            return ((word >> 20) & 0x7F).nonzeroBitCount % 2 == 1
        }
        if let cachedSecurityInfo { return cachedSecurityInfo.flashEncryptionEnabled }
        let info = try await Self.readSecurityInfo(channel)
        cachedSecurityInfo = info
        return info.flashEncryptionEnabled
    }

    /// Ranges of `new` (offsets) whose 4 KiB flash sectors differ from `old`, contiguous sectors
    /// merged. Sectors follow absolute flash addresses; missing bytes of `old` count as 0xFF.
    static func changedChunks(old: Data, new: Data, address: UInt32) -> [Range<Int>] {
        let old = padded(old, to: new.count)
        var chunks: [Range<Int>] = []
        var start = 0
        while start < new.count {
            let end = min(new.count, Int((UInt64(address) + UInt64(start)) / 0x1000 + 1) * 0x1000 - Int(address))
            let range = start..<end
            if old[old.startIndex + range.lowerBound..<old.startIndex + range.upperBound]
                != new[new.startIndex + range.lowerBound..<new.startIndex + range.upperBound] {
                if let last = chunks.last, last.upperBound == range.lowerBound {
                    chunks[chunks.count - 1] = last.lowerBound..<range.upperBound
                } else {
                    chunks.append(range)
                }
            }
            start = end
        }
        return chunks
    }

    /// `data` cut or completed with 0xFF to `count` bytes.
    static func padded(_ data: Data, to count: Int) -> Data {
        data.count >= count ? Data(data.prefix(count)) : Data(data) + Data(repeating: 0xFF, count: count - data.count)
    }

    /// Header bytes 2 and 3 (mode, size, frequency), then the final SHA-256 recomputed.
    private func patchHeader(_ data: inout Data, overrides: FlashHeaderOverrides, flash: FlashInfo) throws -> Bool {
        do {
            return try ImageHeader.patch(&data, chip: chip, overrides: overrides, detectedSize: flash.detectedSize)
        } catch let error as ImageError {
            throw UsageError.invalidArgument(error.description)
        }
    }

    static func differences(expected: Data, actual: Data, limit: Int = 16) -> [ByteDifference] {
        var out: [ByteDifference] = []
        for (offset, (e, a)) in zip(expected, actual).enumerated() where e != a {
            out.append(ByteDifference(offset: offset, expected: e, actual: a))
            if out.count == limit { break }
        }
        return out
    }

    static func decodeHex(_ text: Data) -> Data? {
        guard text.count % 2 == 0 else { return nil }
        var out = Data(capacity: text.count / 2)
        var iterator = text.makeIterator()
        while let high = iterator.next(), let low = iterator.next() {
            guard let h = hexValue(high), let l = hexValue(low) else { return nil }
            out.append(h << 4 | l)
        }
        return out
    }

    private static func hexValue(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): c - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): c - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): c - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
