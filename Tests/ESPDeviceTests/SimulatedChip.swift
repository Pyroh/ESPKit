// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPProtocol
import ESPSupport
import ESPTargets
import ESPTransport

/// Simulated chip that speaks the ROM protocol and, once the stub is loaded, the stub v2 one:
/// SYNC, registers, GET_SECURITY_INFO, SPI_ATTACH, "USR" SPI transactions on RDID,
/// memory commands, flash writes (raw, zlib and "encrypted"), MD5, reads with acknowledgements,
/// erasing, flash status registers and SFDP.
actor SimulatedChip: Transport {
    nonisolated let usbIdentity: USBIdentity?

    var registers: [UInt32: UInt32]
    /// GET_SECURITY_INFO response; `nil`: the ROM does not know the command.
    var securityInfo: Data?
    var jedecID: UInt32
    var spiBase: UInt32
    var spiW0: UInt32
    var spiUSR2: UInt32
    var spiAddressInMSB: Bool
    /// Flash status registers SR1, SR2, SR3.
    var flashStatus: [UInt8] = [0, 0, 0]
    /// False: a WRSR (0x01) only takes its first byte, like flashes that want WRSR2 for SR2.
    var acceptsWideStatusWrite = true
    var sfdp = Data("SFDP".utf8) + Data([0x06, 0x01, 0x01, 0xFF, 0x00, 0x06, 0x01, 0x10, 0x30, 0x00, 0x00, 0xFF])
    /// "Encryption" of the simulated chip: every byte XORed with this value.
    static let encryptionMask: UInt8 = 0xA5
    /// ESP32 eFuses as burned (BLOCK0 to BLOCK3); `nil` until the first PGM or READ command,
    /// then filled from the read registers.
    var efuses: [[UInt32]]?
    /// Extra bits set by the next PGM command (block, word, bits): simulates a faulty burn.
    var efuseGlitch: (block: Int, word: Int, bits: UInt32)?
    /// PGM commands that burn nothing, before the controller behaves.
    var efuseIgnoredPrograms = 0
    private(set) var efusePrograms = 0
    /// SYNCs ignored before answering (simulates a chip slow to enter download mode).
    var ignoredSyncs = 0
    var statusLength = 4
    /// The ROM does not answer MEM_END before jumping (some ROMs cut the response).
    var dropMemEndResponse = false
    /// The stub does not start (no `OHAI`).
    var stubFailsToStart = false
    /// Flips a byte on every flash write (tests the MD5 check).
    var corruptWrites = false
    /// Loses the READ_FLASH block at this index once (0 = first block sent).
    var dropReadPacket: Int?
    private var readPacketsSent = 0

    private(set) var isOpen = false
    private(set) var baudRate = 0
    private(set) var lineChanges: [(dtr: Bool?, rts: Bool?)] = []
    private(set) var receivedOpcodes: [UInt8] = []
    private(set) var registerWrites: [(address: UInt32, value: UInt32)] = []
    private(set) var attachPayloads: [Data] = []
    private(set) var baudPayloads: [Data] = []
    private(set) var flashBeginPayloads: [Data] = []
    private(set) var flashEndPayloads: [Data] = []
    private(set) var memEndPayloads: [Data] = []
    /// SPI opcodes run through the "USR" transactions, in order.
    private(set) var spiOpcodes: [UInt8] = []
    private(set) var flashParamsSize: UInt32?
    private(set) var stubRunning = false
    private(set) var chipErases = 0
    /// RAM written by MEM_DATA, by segment start address.
    private(set) var memory: [UInt32: Data] = [:]
    var flash: Data

    private var output = Data()
    private var decoder = SLIPDecoder()
    private var lastSPIOpcode: UInt8 = 0
    private var memSegment: (address: UInt32, size: Int)?
    private var pendingWrite: (offset: Int, remaining: Int, inflater: Zlib.Inflater?, encrypt: Bool)?
    private var statusWriteEnabled = false
    private var pendingRead: (address: Int, remaining: Int, sent: Data)?

    init(registers: [UInt32: UInt32], securityInfo: Data?, jedecID: UInt32,
         spiBase: UInt32, spiW0: UInt32, spiUSR2: UInt32, spiAddressInMSB: Bool, usbIdentity: USBIdentity? = nil) {
        self.registers = registers
        self.securityInfo = securityInfo
        self.jedecID = jedecID
        self.spiBase = spiBase
        self.spiW0 = spiW0
        self.spiUSR2 = spiUSR2
        self.spiAddressInMSB = spiAddressInMSB
        self.usbIdentity = usbIdentity
        let capacity = (jedecID >> 16) & 0xFF
        flash = Data(repeating: 0xFF, count: 1 << Int(capacity))
    }

    /// ESP32 in ROM: magic-value detection, MAC in eFuse words 1 and 2.
    /// Simulated MAC: 24:0A:C4:12:34:56; 4 MB Winbond flash.
    static func esp32() -> SimulatedChip {
        SimulatedChip(
            // UART0 divider 347: 40 MHz APB at 115,200 baud.
            registers: [0x4000_1000: 0x00F0_1D83, 0x3FF5_A004: 0xC412_3456, 0x3FF5_A008: 0x00AB_240A,
                        0x3FF4_0014: 347],
            securityInfo: nil, jedecID: 0x16_40EF,
            spiBase: 0x3FF4_2000, spiW0: 0x3FF4_2080, spiUSR2: 0x3FF4_2024, spiAddressInMSB: true)
    }

    /// ESP32-S3 in ROM over USB-Serial-JTAG: chip ID 9 through GET_SECURITY_INFO.
    /// Simulated MAC: 34:85:C4:12:34:56; 16 MB GigaDevice flash.
    static func esp32s3(usbSerialJTAG: Bool = true, flags: UInt32 = 0) -> SimulatedChip {
        var info = Data.le(flags)                         // flags
        info.append(0)                                    // flash_crypt_cnt
        info.append(contentsOf: [0, 0, 0, 0, 0, 0, 0])    // purposes
        info.append(.le(UInt32(9), UInt32(0)))            // chip ID, API
        return SimulatedChip(
            registers: [0x6000_7044: 0xC412_3456, 0x6000_7048: 0x0000_3485, 0x6000_80B4: 0x0000_0001],
            securityInfo: info, jedecID: 0x18_40C8,
            spiBase: 0x6000_2000, spiW0: 0x6000_2058, spiUSR2: 0x6000_2020, spiAddressInMSB: false,
            usbIdentity: usbSerialJTAG ? USBIdentity(vendorID: 0x303A, productID: 0x1001) : nil)
    }

    func ignoreSyncs(_ count: Int) { ignoredSyncs = count }
    func setDropMemEndResponse(_ value: Bool) { dropMemEndResponse = value }
    func setStubFailsToStart(_ value: Bool) { stubFailsToStart = value }
    func setCorruptWrites(_ value: Bool) { corruptWrites = value }
    func setDropReadPacket(_ index: Int?) { dropReadPacket = index }
    func setFlashStatus(_ bytes: [UInt8]) { flashStatus = bytes }
    func setAcceptsWideStatusWrite(_ value: Bool) { acceptsWideStatusWrite = value }
    func setRegister(_ address: UInt32, _ value: UInt32) { registers[address] = value }
    func setEfuseGlitch(block: Int, word: Int, bits: UInt32) { efuseGlitch = (block, word, bits) }
    func setEfuseIgnoredPrograms(_ count: Int) { efuseIgnoredPrograms = count }
    func setFlash(_ data: Data, at address: Int) { flash.replaceSubrange(address..<address + data.count, with: data) }

    // MARK: Transport

    func open() async throws { isOpen = true }
    func close() async { isOpen = false }

    func write(_ data: Data) async throws {
        guard isOpen else { throw TransportError.closed }
        for packet in try decoder.feed(data) {
            handle(packet)
        }
    }

    func read(maxCount: Int, timeout: Duration) async throws -> Data {
        guard isOpen else { throw TransportError.closed }
        if output.isEmpty {
            try await Task.sleep(for: min(timeout, .milliseconds(5)))
            return Data()
        }
        let chunk = output.prefix(maxCount)
        output.removeFirst(chunk.count)
        return Data(chunk)
    }

    func discardInput() async throws { output.removeAll() }
    func setBaudRate(_ rate: Int) async throws { baudRate = rate }
    func setControlLines(dtr: Bool?, rts: Bool?) async throws { lineChanges.append((dtr, rts)) }

    // MARK: Protocol

    private func handle(_ packet: Data) {
        if pendingRead != nil {
            handleReadAcknowledgement(packet)
            return
        }
        guard packet.count >= 8, packet[0] == 0x00 else { return }
        let opcode = packet[1]
        let payload = packet.subdata(in: 8..<packet.count)
        receivedOpcodes.append(opcode)
        switch Opcode(rawValue: opcode) {
        case .sync:
            if ignoredSyncs > 0 {
                ignoredSyncs -= 1
                return
            }
            for _ in 0..<8 { reply(opcode, value: stubRunning ? 0 : 0x2012_0707) }
        case .readReg:
            reply(opcode, value: registers[payload.readLE(UInt32.self, at: 0)] ?? 0)
        case .writeReg:
            let address = payload.readLE(UInt32.self, at: 0)
            let value = payload.readLE(UInt32.self, at: 4)
            registerWrites.append((address, value))
            writeRegister(address, value)
            reply(opcode)
        case .getSecurityInfo:
            if let securityInfo { reply(opcode, payload: securityInfo) } else { fail(opcode) }
        case .spiAttach:
            attachPayloads.append(payload)
            reply(opcode)
        case .spiSetParams:
            flashParamsSize = payload.readLE(UInt32.self, at: 4)
            reply(opcode)
        case .changeBaudRate:
            baudPayloads.append(payload)
            reply(opcode)
        case .memBegin:
            memSegment = (payload.readLE(UInt32.self, at: 12), Int(payload.readLE(UInt32.self, at: 0)))
            if let memSegment { memory[memSegment.address] = Data() }
            reply(opcode)
        case .memData:
            guard let memSegment else { return fail(opcode) }
            memory[memSegment.address, default: Data()].append(payload.subdata(in: 16..<payload.count))
            reply(opcode)
        case .memEnd:
            memEndPayloads.append(payload)
            if !dropMemEndResponse { reply(opcode) }
            if payload.readLE(UInt32.self, at: 0) == 0 && !stubFailsToStart {
                stubRunning = true
                statusLength = 2
                output.append(SLIP.encode(Data("OHAI".utf8)))
            }
        case .flashBegin, .flashDeflBegin:
            flashBeginPayloads.append(payload)
            let size = Int(payload.readLE(UInt32.self, at: 0))
            let offset = Int(payload.readLE(UInt32.self, at: 12))
            eraseSectors(from: offset, count: size)
            let encrypt = payload.count >= 20 && payload.readLE(UInt32.self, at: 16) == 1
            pendingWrite = (offset, size, opcode == Opcode.flashDeflBegin.rawValue ? try? Zlib.Inflater() : nil, encrypt)
            reply(opcode)
        case .flashEnd:
            flashEndPayloads.append(payload)
            reply(opcode)
        case .flashData, .flashDeflData:
            guard var current = pendingWrite else { return fail(opcode) }
            let chunk = payload.subdata(in: 16..<payload.count)
            guard Command.checksum(of: chunk) == packet.readLE(UInt32.self, at: 4) else { return fail(opcode, code: 0x07) }
            var bytes = chunk
            if let inflater = current.inflater {
                guard let inflated = try? inflater.feed(chunk) else { return fail(opcode, code: 0x0B) }
                bytes = inflated
            }
            if stubRunning { bytes = bytes.prefix(current.remaining) }
            if corruptWrites, !bytes.isEmpty { bytes[bytes.startIndex] ^= 0xFF }
            if current.encrypt { bytes = Data(bytes.map { $0 ^ Self.encryptionMask }) }
            let end = min(flash.count, current.offset + bytes.count)
            flash.replaceSubrange(current.offset..<end, with: bytes.prefix(end - current.offset))
            current.offset += bytes.count
            current.remaining = max(0, current.remaining - bytes.count)
            pendingWrite = current
            reply(opcode)
        case .spiFlashMD5:
            let address = Int(payload.readLE(UInt32.self, at: 0))
            let count = Int(payload.readLE(UInt32.self, at: 4))
            let digest = MD5.hash(flash.subdata(in: address..<address + count))
            if stubRunning {
                reply(opcode, payload: digest)
            } else {
                reply(opcode, payload: Data(digest.map { String(format: "%02x", $0) }.joined().utf8))
            }
        case .readFlashSlow where !stubRunning:
            let address = Int(payload.readLE(UInt32.self, at: 0))
            reply(opcode, payload: flash.subdata(in: address..<min(flash.count, address + 64)))
        case .readFlash where stubRunning:
            let address = Int(payload.readLE(UInt32.self, at: 0))
            let count = Int(payload.readLE(UInt32.self, at: 4))
            reply(opcode)
            pendingRead = (address, count, Data())
            sendNextReadPacket()
        case .eraseFlash where stubRunning:
            chipErases += 1
            flash = Data(repeating: 0xFF, count: flash.count)
            reply(opcode)
        case .eraseRegion where stubRunning:
            eraseSectors(from: Int(payload.readLE(UInt32.self, at: 0)), count: Int(payload.readLE(UInt32.self, at: 4)))
            reply(opcode)
        default:
            fail(opcode)
        }
    }

    private func sendNextReadPacket() {
        guard var current = pendingRead else { return }
        if current.remaining == 0 {
            output.append(SLIP.encode(MD5.hash(current.sent)))
            pendingRead = nil
            return
        }
        let size = min(0x1000, current.remaining)
        let packet = flash.subdata(in: current.address..<current.address + size)
        current.sent.append(packet)
        current.address += size
        current.remaining -= size
        pendingRead = current
        defer { readPacketsSent += 1 }
        if readPacketsSent == dropReadPacket {
            dropReadPacket = nil                // lost on the way: the host never sees it
            return
        }
        output.append(SLIP.encode(packet))
    }

    private func handleReadAcknowledgement(_ packet: Data) {
        guard let current = pendingRead else { return }
        guard packet.count == 4 else {
            // A frame that is not an acknowledgement: the stub stops reading and sends the MD5.
            output.append(SLIP.encode(MD5.hash(current.sent)))
            pendingRead = nil
            return
        }
        if Int(packet.readLE(UInt32.self, at: 0)) == current.sent.count { sendNextReadPacket() }
    }

    private func eraseSectors(from offset: Int, count: Int) {
        let start = offset / 0x1000 * 0x1000
        let end = min(flash.count, (offset + count + 0xFFF) / 0x1000 * 0x1000)
        guard start < end else { return }
        flash.replaceSubrange(start..<end, with: Data(repeating: 0xFF, count: end - start))
    }

    private func writeRegister(_ address: UInt32, _ value: UInt32) {
        registers[address] = value
        if address == spiUSR2 { lastSPIOpcode = UInt8(value & 0xFF) }
        if address == 0x3FF5_A104 { runEfuseCommand(value) }
        if address == spiBase, value & (1 << 18) != 0 {
            runSPITransaction()
            registers[spiBase] = 0
        }
    }

    /// ESP32 eFuse controller: PGM (opcode 0x5A5A) ORs the WDATA registers into the fuses, READ
    /// (opcode 0x5AA5) copies them to the RDATA registers, blocks with their RD_DIS bit reading 0.
    private func runEfuseCommand(_ command: UInt32) {
        let base: UInt32 = 0x3FF5_A000
        let read: [(UInt32, Int)] = [(base, 7), (base + 0x38, 8), (base + 0x58, 8), (base + 0x78, 8)]
        let write: [(UInt32, Int)] = [(base + 0x1C, 7), (base + 0x98, 8), (base + 0xB8, 8), (base + 0xD8, 8)]
        if efuses == nil {
            efuses = read.map { address, count in (0..<count).map { registers[address + UInt32($0 * 4)] ?? 0 } }
        }
        let opcode = (registers[base + 0xFC] ?? 0) & 0xFFFF
        if command & 2 != 0 && opcode == 0x5A5A {
            efusePrograms += 1
            if efuseIgnoredPrograms > 0 {
                efuseIgnoredPrograms -= 1
            } else {
                for (block, (address, count)) in write.enumerated() {
                    for word in 0..<count { efuses![block][word] |= registers[address + UInt32(word * 4)] ?? 0 }
                }
                if let glitch = efuseGlitch {
                    efuses![glitch.block][glitch.word] |= glitch.bits
                    efuseGlitch = nil
                }
            }
        }
        if command & 1 != 0 && opcode == 0x5AA5 {
            let readDisable = efuses![0][0] >> 16 & 0xF
            for (block, (address, count)) in read.enumerated() {
                let hidden = block > 0 && readDisable >> UInt32(block - 1) & 1 == 1
                for word in 0..<count { registers[address + UInt32(word * 4)] = hidden ? 0 : efuses![block][word] }
            }
        }
        registers[base + 0x104] = 0
    }

    private func runSPITransaction() {
        spiOpcodes.append(lastSPIOpcode)
        let w0 = registers[spiW0] ?? 0
        switch lastSPIOpcode {
        case 0x9F: registers[spiW0] = jedecID
        case 0x05: registers[spiW0] = UInt32(flashStatus[0])
        case 0x35: registers[spiW0] = UInt32(flashStatus[1])
        case 0x15: registers[spiW0] = UInt32(flashStatus[2])
        case 0x06, 0x50: statusWriteEnabled = true
        case 0x04: statusWriteEnabled = false
        case 0x01 where statusWriteEnabled:
            flashStatus[0] = UInt8(truncatingIfNeeded: w0)
            if acceptsWideStatusWrite { flashStatus[1] = UInt8(truncatingIfNeeded: w0 >> 8) }
            statusWriteEnabled = false
        case 0x31 where statusWriteEnabled:
            flashStatus[1] = UInt8(truncatingIfNeeded: w0)
            statusWriteEnabled = false
        case 0x11 where statusWriteEnabled:
            flashStatus[2] = UInt8(truncatingIfNeeded: w0)
            statusWriteEnabled = false
        case 0x5A:
            let raw = registers[spiBase + 4] ?? 0
            let address = Int(spiAddressInMSB ? raw >> 8 : raw)
            var word: UInt32 = 0
            for index in 0..<4 where address + index < sfdp.count {
                word |= UInt32(sfdp[address + index]) << (8 * UInt32(index))
            }
            registers[spiW0] = word
        default: break
        }
    }

    /// Failure in the ROM format (1, code) or the stub format (big-endian 16-bit code, 0xC3 00 by default).
    private func fail(_ opcode: UInt8, code: UInt8 = 0x05) {
        if stubRunning {
            reply(opcode, status: code == 0x05 ? 0xC3 : 0xC1, error: 0)
        } else {
            reply(opcode, status: 1, error: code)
        }
    }

    private func reply(_ opcode: UInt8, value: UInt32 = 0, payload: Data = Data(), status: UInt8 = 0, error: UInt8 = 0) {
        var body = payload
        body.append(contentsOf: [status, error])
        if statusLength == 4 { body.append(contentsOf: [0, 0]) }
        var packet = Data([0x01, opcode])
        packet.appendLE(UInt16(body.count))
        packet.appendLE(value)
        packet.append(body)
        output.append(SLIP.encode(packet))
    }
}
