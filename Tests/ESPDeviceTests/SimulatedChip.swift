// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPProtocol
import ESPTargets
import ESPTransport

/// Puce simulée qui parle le protocole de la ROM : SYNC, registres, GET_SECURITY_INFO,
/// SPI_ATTACH et transactions SPI « USR » sur RDID.
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

    private(set) var isOpen = false
    private(set) var baudRate = 0
    private(set) var lineChanges: [(dtr: Bool?, rts: Bool?)] = []
    private(set) var receivedOpcodes: [UInt8] = []
    private(set) var registerWrites: [(address: UInt32, value: UInt32)] = []
    private(set) var attachPayloads: [Data] = []
    private var output = Data()
    private var decoder = SLIPDecoder()
    private var lastSPIOpcode: UInt8 = 0

    init(registers: [UInt32: UInt32], securityInfo: Data?, jedecID: UInt32,
         spiBase: UInt32, spiW0: UInt32, spiUSR2: UInt32, usbIdentity: USBIdentity? = nil) {
        self.registers = registers
        self.securityInfo = securityInfo
        self.jedecID = jedecID
        self.spiBase = spiBase
        self.spiW0 = spiW0
        self.spiUSR2 = spiUSR2
        self.usbIdentity = usbIdentity
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
    static func esp32s3(usbSerialJTAG: Bool = true) -> SimulatedChip {
        var info = Data.le(UInt32(0))                     // flags
        info.append(0)                                    // flash_crypt_cnt
        info.append(contentsOf: [0, 0, 0, 0, 0, 0, 0])    // purposes
        info.append(.le(UInt32(9), UInt32(0)))            // chip ID, API
        return SimulatedChip(
            registers: [0x6000_7044: 0xC412_3456, 0x6000_7048: 0x0000_3485, 0x6000_80B4: 0x0000_0001],
            securityInfo: info, jedecID: 0x18_40C8,
            spiBase: 0x6000_2000, spiW0: 0x6000_2058, spiUSR2: 0x6000_2020,
            usbIdentity: usbSerialJTAG ? USBIdentity(vendorID: 0x303A, productID: 0x1001) : nil)
    }

    func ignoreSyncs(_ count: Int) {
        ignoredSyncs = count
    }

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
            try await Task.sleep(for: min(timeout, .milliseconds(20)))
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
            for _ in 0..<8 { reply(opcode, value: 0x2012_0707) }
        case .readReg:
            reply(opcode, value: registers[payload.readLE(UInt32.self, at: 0)] ?? 0)
        case .writeReg:
            let address = payload.readLE(UInt32.self, at: 0)
            let value = payload.readLE(UInt32.self, at: 4)
            registerWrites.append((address, value))
            writeRegister(address, value)
            reply(opcode)
        case .getSecurityInfo:
            if let securityInfo { reply(opcode, payload: securityInfo) } else { reply(opcode, status: 1, error: 0x05) }
        case .spiAttach:
            attachPayloads.append(payload)
            reply(opcode)
        case .changeBaudRate:
            reply(opcode)
        default:
            reply(opcode, status: 1, error: 0x05)
        }
    }

    private func writeRegister(_ address: UInt32, _ value: UInt32) {
        registers[address] = value
        if address == spiUSR2 { lastSPIOpcode = UInt8(value & 0xFF) }
        if address == spiBase, value & (1 << 18) != 0 {
            if lastSPIOpcode == 0x9F { registers[spiW0] = jedecID }
            registers[spiBase] = 0
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
