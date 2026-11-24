// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPProtocol
import ESPTargets
import ESPTransport

/// Session open with a chip in download mode.
///
/// Operations are serialized: even when called from several tasks, two exchanges
/// with the chip never interleave.
public actor ESPDevice {
    /// Chip detected when connecting.
    public nonisolated let chip: ChipFamily
    public private(set) var state: State
    public private(set) var baudRate: Int

    public enum State: Hashable, Sendable, CustomStringConvertible {
        /// Bootloader ROM.
        case rom
        /// Restricted ROM.
        case secureDownloadMode
        case stub(StubImage.Version)
        case closed

        public var description: String {
            switch self {
            case .rom: "ROM"
            case .secureDownloadMode: "Secure Download Mode"
            case .stub(let version): "stub \(version)"
            case .closed: "closed"
            }
        }
    }

    let channel: ProtocolChannel
    let descriptor: ChipDescriptor
    var cachedSecurityInfo: SecurityInfo?
    var attachedFlash: FlashInfo?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(channel: ProtocolChannel, chip: ChipFamily, state: State, baudRate: Int, securityInfo: SecurityInfo?) {
        self.channel = channel
        self.chip = chip
        self.descriptor = ChipDescriptor(family: chip)
        self.state = state
        self.baudRate = baudRate
        self.cachedSecurityInfo = securityInfo
    }

    // MARK: Lifecycle

    /// Loads a stub unless one is already running. Does nothing if a stub runs.
    /// `nil`: the bundled stub v2 for `chip`.
    /// - Throws: `StubError` (image refused, no bundled stub, no `OHAI`),
    ///   `UsageError.unavailableInSecureDownloadMode`, `TransportError`, `ProtocolError`.
    public func loadStub(_ stub: StubImage? = nil) async throws {
        try await exclusive {
            try ensureOpen()
            if case .stub = state { return }
            if state == .secureDownloadMode {
                throw UsageError.unavailableInSecureDownloadMode(operation: "Loading the stub")
            }
            guard let image = stub ?? StubImage.bundled(for: chip) else { throw StubError.noBundledStub(chip) }
            guard image.chip == chip else { throw StubError.chipMismatch(stub: image.chip, device: chip) }
            try await rawLoadStub(image)
        }
    }

    /// Changes the baud rate on both sides.
    ///
    /// With the stub, every chip. Under ROM, `UsageError.unsupported` on the ESP8266, ESP32
    /// and ESP32-C2, whose ROM computes the divider wrongly for the crystal: load the stub first.
    public func changeBaudRate(_ rate: Int) async throws {
        try await exclusive {
            try ensureOpen()
            guard rate > 0 else { throw UsageError.invalidArgument("baud rate \(rate)") }
            guard rate != baudRate else { return }
            let stubRunning: Bool
            switch state {
            case .stub: stubRunning = true
            case .rom: stubRunning = false
            default: throw UsageError.unsupported(feature: "Changing the baud rate", chip: chip, state: state)
            }
            if !stubRunning && [.esp8266, .esp32, .esp32c2].contains(chip) {
                throw UsageError.unsupported(feature: "Changing the baud rate under ROM", chip: chip, state: state)
            }
            // The stub also wants the old baud rate; the ROM expects 0.
            let payload = Data.le(UInt32(rate), stubRunning ? UInt32(baudRate) : 0)
            _ = try await channel.execute(Command(.changeBaudRate, payload: payload))
            try await channel.transport.setBaudRate(rate)
            try await Task.sleep(for: .milliseconds(50))
            try await channel.discardInput()
            baudRate = rate
            await channel.emit(.baudRateChanged(rate))
        }
    }

    /// Applies the exit strategy then closes the transport. The actor is unusable afterwards:
    /// every operation throws `ConnectionError.disconnected`.
    ///
    /// `.soft` needs the stub: under ROM, ESPKit performs a `.hard` instead.
    /// `.watchdog` is only implemented for the ESP32-S3; elsewhere, `.hard`.
    public func disconnect(_ exitReset: ExitReset = .hard) async {
        await exclusiveIgnoringErrors {
            guard state != .closed else { return }
            switch exitReset {
            case .stayInBootloader, .stayInStub:
                break
            case .watchdog where descriptor.rtcWatchdog != nil:
                try? await watchdogReset()
            case .hard, .soft, .watchdog:
                let overUSB = channel.transport.usbIdentity?.isEspressifUSBSerialJTAG ?? false
                try? await perform(.hardReset(overUSB: overUSB))
            }
            await channel.transport.close()
            await channel.finishTrace()
            state = .closed
        }
    }

    // MARK: Identity

    /// Security state of the chip. Also available in Secure Download Mode.
    /// - Throws: `UsageError.unsupported` on the ESP8266 and ESP32, whose ROM lacks the command.
    public func securityInfo() async throws -> SecurityInfo {
        try await exclusive {
            try ensureOpen()
            if [.esp8266, .esp32].contains(chip) {
                throw UsageError.unsupported(feature: "GET_SECURITY_INFO", chip: chip, state: state)
            }
            let info = try await Self.readSecurityInfo(channel)
            cachedSecurityInfo = info
            return info
        }
    }

    public func macAddress() async throws -> MACAddress {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("Reading the MAC")
            let bytes: Data
            switch descriptor.macLayout {
            case .esp8266OTP:
                let mac0 = try await rawReadRegister(ChipDescriptor.esp8266OTPMAC0)
                let mac1 = try await rawReadRegister(ChipDescriptor.esp8266OTPMAC1)
                let mac3 = try await rawReadRegister(ChipDescriptor.esp8266OTPMAC3)
                let oui: [UInt8]
                if mac3 != 0 {
                    oui = [UInt8(truncatingIfNeeded: mac3 >> 16), UInt8(truncatingIfNeeded: mac3 >> 8),
                           UInt8(truncatingIfNeeded: mac3)]
                } else {
                    // OUI not programmed: it follows from one byte of MAC1.
                    switch (mac1 >> 16) & 0xFF {
                    case 0: oui = [0x18, 0xFE, 0x34]
                    case 1: oui = [0xAC, 0xD0, 0x74]
                    default: throw ProtocolError.invalidResponse("unknown ESP8266 OUI")
                    }
                }
                bytes = Data(oui + [UInt8(truncatingIfNeeded: mac1 >> 8), UInt8(truncatingIfNeeded: mac1),
                                    UInt8(truncatingIfNeeded: mac0 >> 24)])
            case .esp32Efuse(let base):
                let word1 = try await rawReadRegister(base + 4)
                let word2 = try await rawReadRegister(base + 8)
                bytes = Self.bigEndian(word2).suffix(2) + Self.bigEndian(word1)
            case .register(let address):
                let low = try await rawReadRegister(address)
                let high = try await rawReadRegister(address + 4)
                bytes = Self.bigEndian(high).suffix(2) + Self.bigEndian(low)
            }
            guard let mac = MACAddress(bytes: Data(bytes)) else {
                throw ProtocolError.invalidResponse("MAC of \(bytes.count) bytes")
            }
            return mac
        }
    }

    /// ESP8266 chip ID (OTP), the equivalent of `system_get_chip_id()`.
    ///
    /// Other families have no chip ID of their own: use `macAddress()`. Their
    /// family identifier is in `securityInfo().chipID`.
    /// - Throws: `UsageError.unsupported` on chips other than the ESP8266.
    public func chipID() async throws -> UInt32 {
        try await exclusive {
            try ensureOpen()
            guard chip == .esp8266 else {
                throw UsageError.unsupported(feature: "The chip ID", chip: chip, state: state)
            }
            let id0 = try await rawReadRegister(ChipDescriptor.esp8266OTPMAC0)
            let id1 = try await rawReadRegister(ChipDescriptor.esp8266OTPMAC1)
            return (id0 >> 24) | ((id1 & 0xFF_FFFF) << 8)
        }
    }

    // MARK: Registers

    public func readRegister(_ address: UInt32) async throws -> UInt32 {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("Reading a register")
            return try await rawReadRegister(address)
        }
    }

    public func writeRegister(_ address: UInt32, _ value: UInt32,
                              mask: UInt32 = .max, delay: Duration = .zero) async throws {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("Writing a register")
            try await rawWriteRegister(address, value, mask: mask, delay: delay)
        }
    }

    // MARK: Flash

    /// Attaches the SPI flash and reads its identity. Called implicitly by every flash operation;
    /// call it explicitly for non-standard `SPIConnection` wiring.
    public func attachFlash(_ connection: SPIConnection = .default,
                            type: FlashType = .nor) async throws -> FlashInfo {
        try await exclusive {
            try await rawAttachFlash(connection, type: type)
        }
    }

    public func flashInfo() async throws -> FlashInfo {
        try await exclusive {
            if let attachedFlash { return attachedFlash }
            return try await rawAttachFlash(.default, type: .nor)
        }
    }

    /// Raw SPI command (opcode, outgoing data, number of bits to read back).
    /// At most 64 bytes sent and 32 bits read back.
    public func spiFlashCommand(_ opcode: UInt8, data: Data = .init(), readBits: Int = 0) async throws -> UInt32 {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("Raw SPI commands")
            return try await rawSPICommand(opcode, data: data, readBits: readBits)
        }
    }

    // MARK: - Internals

    /// Serializes operations: the actor is reentrant, this lock is not.
    func exclusive<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
        defer {
            if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
        }
        return try await body()
    }

    private func exclusiveIgnoringErrors(_ body: () async -> Void) async {
        _ = try? await exclusive { await body() }
    }

    func ensureOpen() throws {
        if state == .closed { throw ConnectionError.disconnected }
    }

    func ensureNotSecureDownload(_ operation: String) throws {
        if state == .secureDownloadMode { throw UsageError.unavailableInSecureDownloadMode(operation: operation) }
    }

    var stubRunning: Bool {
        if case .stub = state { return true }
        return false
    }

    func rawReadRegister(_ address: UInt32) async throws -> UInt32 {
        try await channel.execute(Command(.readReg, payload: .le(address))).value
    }

    func rawWriteRegister(_ address: UInt32, _ value: UInt32, mask: UInt32 = .max, delay: Duration = .zero) async throws {
        let microseconds = UInt32(clamping: delay.components.seconds * 1_000_000
                                  + delay.components.attoseconds / 1_000_000_000_000)
        _ = try await channel.execute(Command(.writeReg, payload: .le(address, value, mask, microseconds)))
    }

    /// Copies the stub into RAM with the ROM memory commands, starts it and waits for its `OHAI`.
    private func rawLoadStub(_ image: StubImage) async throws {
        let blockSize = 0x1800
        for (segment, address) in [(image.text, image.textAddress), (image.data, image.dataAddress)] where !segment.isEmpty {
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
        // MEM_END: first word 0 to jump to the entry point.
        try await channel.send(Command(.memEnd, payload: .le(image.entry == 0 ? UInt32(1) : 0, image.entry)))
        let deadline = ContinuousClock.now + .seconds(3)
        while true {
            let remaining = deadline - .now
            let packet: Data
            do {
                packet = try await channel.receivePacket(timeout: max(remaining, .zero), opcode: Opcode.memEnd.rawValue)
            } catch is ProtocolError {
                throw StubError.failedToStart(image.version)
            }
            if packet == Data("OHAI".utf8) { break }
            if let response = Response(packet: packet), response.opcode == Opcode.memEnd.rawValue {
                _ = try await channel.checked(response)       // a ROM refusal is propagated
            }
        }
        await channel.setStatusLength(descriptor.statusLength(stubRunning: true))
        state = .stub(image.version)
        await channel.emit(.stubStarted(image.version))
    }

    private func perform(_ sequence: ResetSequence) async throws {
        for step in sequence.steps {
            await channel.emit(.resetStep(step))
            try await channel.transport.perform(step)
        }
    }

    func rawAttachFlash(_ connection: SPIConnection, type: FlashType) async throws -> FlashInfo {
        try ensureOpen()
        try ensureNotSecureDownload("Flash access")
        guard type == .nor else {
            throw UsageError.unsupported(feature: "NAND flash", chip: chip, state: state)
        }
        if chip == .esp8266 {
            if !stubRunning {
                // The ESP8266 ROM has no SPI_ATTACH: an empty FLASH_BEGIN attaches the flash.
                _ = try await channel.execute(Command(.flashBegin, payload: .le(UInt32(0), UInt32(0), UInt32(0x400), UInt32(0))))
            }
        } else {
            let config: UInt32
            switch connection {
            case .default, .spi: config = 0
            case .hspi:
                guard chip == .esp32 else { throw UsageError.invalidArgument("HSPI only exists on the ESP32") }
                config = 1
            case .pins(let clk, let q, let d, let hd, let cs):
                config = UInt32(hd) << 24 | UInt32(cs) << 18 | UInt32(d) << 12 | UInt32(q) << 6 | UInt32(clk)
            }
            // The ROM expects 4 more bytes (a "legacy" flag set to 0 and 3 reserved bytes).
            let payload = stubRunning ? Data.le(config) : Data.le(config, UInt32(0))
            _ = try await channel.execute(Command(.spiAttach, payload: payload))
        }
        let id = try await rawSPICommand(0x9F, data: Data(), readBits: 24)
        if [0xFF_FFFF, 0x00_0000, 0xFF_FF3F].contains(id) { throw FlashError.notDetected(jedecID: id) }
        let info = FlashInfo(jedecID: id, type: type)
        if stubRunning || chip != .esp8266 {
            // Geometry: only the size varies (4 MB if the JEDEC ID does not give it, like esptool).
            let size = UInt32(info.detectedSize?.byteCount ?? FlashSize.mb4.byteCount)
            _ = try await channel.execute(Command(.spiSetParams, payload: .le(UInt32(0), size, UInt32(0x1_0000),
                                                                              UInt32(0x1000), UInt32(0x100), UInt32(0xFFFF))))
        }
        attachedFlash = info
        return info
    }

    /// SPI transaction in "USR" mode on the SPI1 controller, driven through READ_REG/WRITE_REG.
    func rawSPICommand(_ opcode: UInt8, data: Data, readBits: Int,
                       address: UInt32? = nil, addressBits: Int = 0, dummyBits: Int = 0) async throws -> UInt32 {
        guard data.count <= 64 else { throw UsageError.invalidArgument("at most 64 bytes per SPI command") }
        guard (0...32).contains(readBits) else { throw UsageError.invalidArgument("at most 32 bits read back") }

        let regs = descriptor.spi
        let usr = regs.base + regs.usr, usr1 = regs.base + regs.usr1, usr2 = regs.base + regs.usr2
        let w0 = regs.base + regs.w0
        let dataBits = data.count * 8

        let savedUSR = try await rawReadRegister(usr)
        let savedUSR2 = try await rawReadRegister(usr2)

        var usr1Value: UInt32 = 0
        if address != nil, addressBits > 0 { usr1Value |= UInt32(addressBits - 1) << 26 }
        if dummyBits > 0 { usr1Value |= UInt32(dummyBits - 1) }
        if let mosi = regs.mosiDataLength, let miso = regs.misoDataLength {
            if dataBits > 0 { try await rawWriteRegister(regs.base + mosi, UInt32(dataBits - 1)) }
            if readBits > 0 { try await rawWriteRegister(regs.base + miso, UInt32(readBits - 1)) }
            if usr1Value != 0 { try await rawWriteRegister(usr1, usr1Value) }
        } else {
            // ESP8266: MISO and MOSI lengths are stored in USR1.
            usr1Value |= UInt32(max(readBits - 1, 0)) << 8 | UInt32(max(dataBits - 1, 0)) << 17
            try await rawWriteRegister(usr1, usr1Value)
        }

        var flags: UInt32 = 1 << 31                              // command phase
        if address != nil, addressBits > 0 { flags |= 1 << 30 }  // address phase
        if dummyBits > 0 { flags |= 1 << 29 }                    // dummy cycles
        if readBits > 0 { flags |= 1 << 28 }                     // read (MISO)
        if dataBits > 0 { flags |= 1 << 27 }                     // write (MOSI)
        try await rawWriteRegister(usr, flags)
        try await rawWriteRegister(usr2, 7 << 28 | UInt32(opcode))   // 8-bit command

        if let address, addressBits > 0 {
            let value = regs.addressInMSB ? address << (32 - UInt32(addressBits)) : address
            try await rawWriteRegister(regs.base + 0x04, value)
        }
        if data.isEmpty {
            try await rawWriteRegister(w0, 0)
        } else {
            var padded = data
            while padded.count % 4 != 0 { padded.append(0) }
            for index in 0..<(padded.count / 4) {
                try await rawWriteRegister(w0 + UInt32(index * 4), padded.readLE32(at: index * 4))
            }
        }

        let userBit: UInt32 = 1 << 18
        try await rawWriteRegister(regs.cmd, userBit)
        var done = false
        for _ in 0..<10 where !done {
            done = try await rawReadRegister(regs.cmd) & userBit == 0
        }
        guard done else { throw ProtocolError.invalidResponse("SPI transaction \(hex(opcode)) does not complete") }

        let result = try await rawReadRegister(w0)
        try await rawWriteRegister(usr, savedUSR)
        try await rawWriteRegister(usr2, savedUSR2)
        return readBits == 32 ? result : result & ((1 << UInt32(readBits)) - 1)
    }

    private func watchdogReset() async throws {
        guard let wdt = descriptor.rtcWatchdog else { return }
        try await rawWriteRegister(wdt.wdtWriteProtect, wdt.wdtKey)        // unlock
        try await rawWriteRegister(wdt.wdtConfig1, 2000)                   // timeout
        try await rawWriteRegister(wdt.wdtConfig0, 1 << 31 | 5 << 28 | 1 << 8 | 2)  // enable, stage 0: system reset
        try await rawWriteRegister(wdt.wdtWriteProtect, 0)                 // lock again
        try await Task.sleep(for: .milliseconds(50))
    }

    /// Disables the RTC watchdog and makes the super watchdog auto-feed: over USB-Serial-JTAG,
    /// the ROM does not do it and the chip would reboot in the middle of an operation.
    func disableWatchdogsForUSBSerialJTAG() async throws {
        guard let wdt = descriptor.rtcWatchdog,
              channel.transport.usbIdentity?.isEspressifUSBSerialJTAG == true,
              state != .secureDownloadMode else { return }
        try await rawWriteRegister(wdt.wdtWriteProtect, wdt.wdtKey)
        try await rawWriteRegister(wdt.wdtConfig0, 0)
        try await rawWriteRegister(wdt.wdtWriteProtect, 0)
        try await rawWriteRegister(wdt.swdWriteProtect, wdt.swdKey)
        let swd = try await rawReadRegister(wdt.swdConfig)
        try await rawWriteRegister(wdt.swdConfig, swd | wdt.swdAutoFeed)
        try await rawWriteRegister(wdt.swdWriteProtect, 0)
    }

    static func readSecurityInfo(_ channel: ProtocolChannel) async throws -> SecurityInfo {
        let reply = try await channel.execute(Command(.getSecurityInfo))
        guard let info = SecurityInfo(payload: reply.payload) else {
            throw ProtocolError.invalidResponse("GET_SECURITY_INFO: \(reply.payload.count) bytes")
        }
        return info
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
