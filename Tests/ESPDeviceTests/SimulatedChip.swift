// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPProtocol
import ESPSupport
import ESPTargets
import ESPTransport

/// Puce simulée qui parle le protocole de la ROM puis, une fois le stub chargé, celui du stub v2 :
/// SYNC, registres, GET_SECURITY_INFO, SPI_ATTACH, transactions SPI « USR » sur RDID,
/// commandes mémoire, écriture flash (brute et zlib), MD5, lecture avec accusés, effacement.
actor SimulatedChip: Transport {
    nonisolated let usbIdentity: USBIdentity?

    var registers: [UInt32: UInt32]
    /// Réponse de GET_SECURITY_INFO ; `nil` : la ROM ne connaît pas la commande.
    var securityInfo: Data?
    var jedecID: UInt32
    var spiBase: UInt32
    var spiW0: UInt32
    var spiUSR2: UInt32
    /// SYNC ignorés avant de répondre (simule une puce lente à entrer en téléchargement).
    var ignoredSyncs = 0
    var statusLength = 4
    /// La ROM ne répond pas à MEM_END avant de sauter (certaines ROM coupent la réponse).
    var dropMemEndResponse = false
    /// Le stub ne démarre pas (pas de `OHAI`).
    var stubFailsToStart = false
    /// Inverse un octet à chaque écriture flash (test du contrôle MD5).
    var corruptWrites = false
    /// Perd une fois le bloc de READ_FLASH de ce rang (0 = premier bloc envoyé).
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
    private(set) var flashParamsSize: UInt32?
    private(set) var stubRunning = false
    private(set) var chipErases = 0
    /// RAM écrite par MEM_DATA, par adresse de début de segment.
    private(set) var memory: [UInt32: Data] = [:]
    var flash: Data

    private var output = Data()
    private var decoder = SLIPDecoder()
    private var lastSPIOpcode: UInt8 = 0
    private var memSegment: (address: UInt32, size: Int)?
    private var pendingWrite: (offset: Int, remaining: Int, inflater: Zlib.Inflater?)?
    private var pendingRead: (address: Int, remaining: Int, sent: Data)?

    init(registers: [UInt32: UInt32], securityInfo: Data?, jedecID: UInt32,
         spiBase: UInt32, spiW0: UInt32, spiUSR2: UInt32, usbIdentity: USBIdentity? = nil) {
        self.registers = registers
        self.securityInfo = securityInfo
        self.jedecID = jedecID
        self.spiBase = spiBase
        self.spiW0 = spiW0
        self.spiUSR2 = spiUSR2
        self.usbIdentity = usbIdentity
        let capacity = (jedecID >> 16) & 0xFF
        flash = Data(repeating: 0xFF, count: 1 << Int(capacity))
    }

    /// ESP32 en ROM : détection par valeur magique, MAC dans les mots eFuse 1 et 2.
    /// MAC simulée : 24:0A:C4:12:34:56 ; flash Winbond 4 Mo.
    static func esp32() -> SimulatedChip {
        SimulatedChip(
            registers: [0x4000_1000: 0x00F0_1D83, 0x3FF5_A004: 0xC412_3456, 0x3FF5_A008: 0x00AB_240A],
            securityInfo: nil, jedecID: 0x16_40EF,
            spiBase: 0x3FF4_2000, spiW0: 0x3FF4_2080, spiUSR2: 0x3FF4_2024)
    }

    /// ESP32-S3 en ROM sur l'USB-Serial-JTAG : chip ID 9 par GET_SECURITY_INFO.
    /// MAC simulée : 34:85:C4:12:34:56 ; flash GigaDevice 16 Mo.
    static func esp32s3(usbSerialJTAG: Bool = true, flags: UInt32 = 0) -> SimulatedChip {
        var info = Data.le(flags)                         // flags
        info.append(0)                                    // flash_crypt_cnt
        info.append(contentsOf: [0, 0, 0, 0, 0, 0, 0])    // purposes
        info.append(.le(UInt32(9), UInt32(0)))            // chip ID, API
        return SimulatedChip(
            registers: [0x6000_7044: 0xC412_3456, 0x6000_7048: 0x0000_3485, 0x6000_80B4: 0x0000_0001],
            securityInfo: info, jedecID: 0x18_40C8,
            spiBase: 0x6000_2000, spiW0: 0x6000_2058, spiUSR2: 0x6000_2020,
            usbIdentity: usbSerialJTAG ? USBIdentity(vendorID: 0x303A, productID: 0x1001) : nil)
    }

    func ignoreSyncs(_ count: Int) { ignoredSyncs = count }
    func setDropMemEndResponse(_ value: Bool) { dropMemEndResponse = value }
    func setStubFailsToStart(_ value: Bool) { stubFailsToStart = value }
    func setCorruptWrites(_ value: Bool) { corruptWrites = value }
    func setDropReadPacket(_ index: Int?) { dropReadPacket = index }
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

    // MARK: Protocole

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
            pendingWrite = (offset, size, opcode == Opcode.flashDeflBegin.rawValue ? try? Zlib.Inflater() : nil)
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
            dropReadPacket = nil                // perdu en route : l'hôte ne le verra jamais
            return
        }
        output.append(SLIP.encode(packet))
    }

    private func handleReadAcknowledgement(_ packet: Data) {
        guard let current = pendingRead else { return }
        guard packet.count == 4 else {
            // Trame qui n'est pas un accusé : le stub interrompt la lecture et envoie le MD5.
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
        if address == spiBase, value & (1 << 18) != 0 {
            if lastSPIOpcode == 0x9F { registers[spiW0] = jedecID }
            registers[spiBase] = 0
        }
    }

    /// Échec au format de la ROM (1, code) ou du stub (code sur 16 bits big-endian, 0xC3 00 par défaut).
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
