// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPProtocol
import ESPTargets
import ESPTransport

/// Session ouverte avec une puce en mode téléchargement.
///
/// Les opérations sont sérialisées : même appelées depuis plusieurs tâches, deux échanges
/// avec la puce ne s'entrelacent jamais.
public actor ESPDevice {
    /// Puce détectée à la connexion.
    public nonisolated let chip: ChipFamily
    public private(set) var state: State
    public private(set) var baudRate: Int

    public enum State: Hashable, Sendable, CustomStringConvertible {
        /// Bootloader ROM.
        case rom
        /// ROM restreint.
        case secureDownloadMode
        case stub(StubImage.Version)
        case closed

        public var description: String {
            switch self {
            case .rom: "ROM"
            case .secureDownloadMode: "Secure Download Mode"
            case .stub(let version): "stub \(version)"
            case .closed: "fermée"
            }
        }
    }

    let channel: ProtocolChannel
    let descriptor: ChipDescriptor
    private var cachedSecurityInfo: SecurityInfo?
    private var attachedFlash: FlashInfo?
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

    // MARK: Cycle de vie

    /// Charge un stub s'il n'en tourne pas déjà un. Sans effet si un stub tourne.
    /// `nil` : le stub v2 embarqué pour `chip`.
    /// - Throws: `StubError` (image refusée, pas de stub embarqué, pas de `OHAI`),
    ///   `UsageError.unavailableInSecureDownloadMode`, `TransportError`, `ProtocolError`.
    ///
    /// Phase 0 : le chargement arrive en phase 1. Sans stub embarqué, lève `StubError.noBundledStub`.
    public func loadStub(_ stub: StubImage? = nil) async throws {
        try await exclusive {
            try ensureOpen()
            if case .stub = state { return }
            if state == .secureDownloadMode {
                throw UsageError.unavailableInSecureDownloadMode(operation: "Le chargement du stub")
            }
            guard let image = stub ?? StubImage.bundled(for: chip) else { throw StubError.noBundledStub(chip) }
            guard image.chip == chip else { throw StubError.chipMismatch(stub: image.chip, device: chip) }
            throw UsageError.unsupported(feature: "Le chargement du stub (phase 1)", chip: chip, state: state)
        }
    }

    /// Change le débit des deux côtés. Sous ROM, ESP8266 : `UsageError.unsupported`.
    ///
    /// Phase 0 : disponible sous ROM pour les puces sans correction d'horloge
    /// (pas l'ESP32, pas l'ESP32-C2) ; le reste arrive avec le stub en phase 1.
    public func changeBaudRate(_ rate: Int) async throws {
        try await exclusive {
            try ensureOpen()
            guard rate > 0 else { throw UsageError.invalidArgument("débit \(rate)") }
            guard rate != baudRate else { return }
            let stubRunning: Bool
            switch state {
            case .stub: stubRunning = true
            case .rom: stubRunning = false
            default: throw UsageError.unsupported(feature: "Le changement de débit", chip: chip, state: state)
            }
            if !stubRunning && [.esp8266, .esp32, .esp32c2].contains(chip) {
                throw UsageError.unsupported(feature: "Le changement de débit sous ROM", chip: chip, state: state)
            }
            // Le stub veut aussi l'ancien débit ; la ROM attend 0.
            let payload = Data.le(UInt32(rate), stubRunning ? UInt32(baudRate) : 0)
            _ = try await channel.execute(Command(.changeBaudRate, payload: payload))
            try await channel.transport.setBaudRate(rate)
            try await Task.sleep(for: .milliseconds(50))
            try await channel.discardInput()
            baudRate = rate
            await channel.emit(.baudRateChanged(rate))
        }
    }

    /// Applique la stratégie de sortie puis ferme le transport. L'acteur est ensuite inutilisable :
    /// toute opération lève `ConnectionError.disconnected`.
    ///
    /// `.soft` demande le stub : sous ROM, ESPKit fait un `.hard` à la place.
    /// `.watchdog` n'est implémenté que pour l'ESP32-S3 ; ailleurs, `.hard`.
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

    // MARK: Identité

    /// État de sécurité de la puce. Disponible aussi en Secure Download Mode.
    /// - Throws: `UsageError.unsupported` sur ESP8266 et ESP32, dont la ROM ne connaît pas la commande.
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
            try ensureNotSecureDownload("La lecture de la MAC")
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
                    // OUI non programmé : il se déduit d'un octet de MAC1.
                    switch (mac1 >> 16) & 0xFF {
                    case 0: oui = [0x18, 0xFE, 0x34]
                    case 1: oui = [0xAC, 0xD0, 0x74]
                    default: throw ProtocolError.invalidResponse("OUI de l'ESP8266 inconnu")
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
                throw ProtocolError.invalidResponse("MAC de \(bytes.count) octets")
            }
            return mac
        }
    }

    /// Identifiant de puce de l'ESP8266 (OTP), l'équivalent de `system_get_chip_id()`.
    ///
    /// Les autres familles n'ont pas d'identifiant propre : utiliser `macAddress()`. Leur
    /// identifiant de famille est dans `securityInfo().chipID`.
    /// - Throws: `UsageError.unsupported` hors ESP8266.
    public func chipID() async throws -> UInt32 {
        try await exclusive {
            try ensureOpen()
            guard chip == .esp8266 else {
                throw UsageError.unsupported(feature: "L'identifiant de puce", chip: chip, state: state)
            }
            let id0 = try await rawReadRegister(ChipDescriptor.esp8266OTPMAC0)
            let id1 = try await rawReadRegister(ChipDescriptor.esp8266OTPMAC1)
            return (id0 >> 24) | ((id1 & 0xFF_FFFF) << 8)
        }
    }

    // MARK: Registres

    public func readRegister(_ address: UInt32) async throws -> UInt32 {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("La lecture de registre")
            return try await rawReadRegister(address)
        }
    }

    public func writeRegister(_ address: UInt32, _ value: UInt32,
                              mask: UInt32 = .max, delay: Duration = .zero) async throws {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("L'écriture de registre")
            try await rawWriteRegister(address, value, mask: mask, delay: delay)
        }
    }

    // MARK: Flash

    /// Attache la flash SPI et en lit l'identité. Appelé implicitement par toute opération flash ;
    /// à appeler explicitement pour un câblage `SPIConnection` non standard.
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

    /// Commande SPI brute (opcode, données sortantes, nombre de bits à relire).
    /// Au plus 64 octets envoyés et 32 bits relus.
    public func spiFlashCommand(_ opcode: UInt8, data: Data = .init(), readBits: Int = 0) async throws -> UInt32 {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("Les commandes SPI brutes")
            return try await rawSPICommand(opcode, data: data, readBits: readBits)
        }
    }

    // MARK: - Interne

    /// Sérialise les opérations : l'acteur est réentrant, ce verrou ne l'est pas.
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

    private func perform(_ sequence: ResetSequence) async throws {
        for step in sequence.steps {
            await channel.emit(.resetStep(step))
            try await channel.transport.perform(step)
        }
    }

    private func rawAttachFlash(_ connection: SPIConnection, type: FlashType) async throws -> FlashInfo {
        try ensureOpen()
        try ensureNotSecureDownload("L'accès à la flash")
        guard type == .nor else {
            throw UsageError.unsupported(feature: "La flash NAND", chip: chip, state: state)
        }
        if chip == .esp8266 {
            if !stubRunning {
                // La ROM ESP8266 n'a pas de SPI_ATTACH : un FLASH_BEGIN vide attache la flash.
                _ = try await channel.execute(Command(.flashBegin, payload: .le(UInt32(0), UInt32(0), UInt32(0x400), UInt32(0))))
            }
        } else {
            let config: UInt32
            switch connection {
            case .default, .spi: config = 0
            case .hspi:
                guard chip == .esp32 else { throw UsageError.invalidArgument("HSPI n'existe que sur l'ESP32") }
                config = 1
            case .pins(let clk, let q, let d, let hd, let cs):
                config = UInt32(hd) << 24 | UInt32(cs) << 18 | UInt32(d) << 12 | UInt32(q) << 6 | UInt32(clk)
            }
            // La ROM attend 4 octets de plus (indicateur « legacy » à 0 et 3 réservés).
            let payload = stubRunning ? Data.le(config) : Data.le(config, UInt32(0))
            _ = try await channel.execute(Command(.spiAttach, payload: payload))
        }
        let id = try await rawSPICommand(0x9F, data: Data(), readBits: 24)
        if [0xFF_FFFF, 0x00_0000, 0xFF_FF3F].contains(id) { throw FlashError.notDetected(jedecID: id) }
        let info = FlashInfo(jedecID: id, type: type)
        attachedFlash = info
        return info
    }

    /// Transaction SPI en mode « USR » sur le contrôleur SPI1, pilotée par READ_REG/WRITE_REG.
    func rawSPICommand(_ opcode: UInt8, data: Data, readBits: Int,
                       address: UInt32? = nil, addressBits: Int = 0, dummyBits: Int = 0) async throws -> UInt32 {
        guard data.count <= 64 else { throw UsageError.invalidArgument("au plus 64 octets par commande SPI") }
        guard (0...32).contains(readBits) else { throw UsageError.invalidArgument("au plus 32 bits relus") }

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
            // ESP8266 : longueurs MISO et MOSI rangées dans USR1.
            usr1Value |= UInt32(max(readBits - 1, 0)) << 8 | UInt32(max(dataBits - 1, 0)) << 17
            try await rawWriteRegister(usr1, usr1Value)
        }

        var flags: UInt32 = 1 << 31                              // phase commande
        if address != nil, addressBits > 0 { flags |= 1 << 30 }  // phase adresse
        if dummyBits > 0 { flags |= 1 << 29 }                    // cycles d'attente
        if readBits > 0 { flags |= 1 << 28 }                     // lecture (MISO)
        if dataBits > 0 { flags |= 1 << 27 }                     // écriture (MOSI)
        try await rawWriteRegister(usr, flags)
        try await rawWriteRegister(usr2, 7 << 28 | UInt32(opcode))   // commande sur 8 bits

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
        guard done else { throw ProtocolError.invalidResponse("la transaction SPI \(hex(opcode)) ne se termine pas") }

        let result = try await rawReadRegister(w0)
        try await rawWriteRegister(usr, savedUSR)
        try await rawWriteRegister(usr2, savedUSR2)
        return readBits == 32 ? result : result & ((1 << UInt32(readBits)) - 1)
    }

    private func watchdogReset() async throws {
        guard let wdt = descriptor.rtcWatchdog else { return }
        try await rawWriteRegister(wdt.wdtWriteProtect, wdt.wdtKey)        // déverrouille
        try await rawWriteRegister(wdt.wdtConfig1, 2000)                   // délai
        try await rawWriteRegister(wdt.wdtConfig0, 1 << 31 | 5 << 28 | 1 << 8 | 2)  // active, étape 0 : reset système
        try await rawWriteRegister(wdt.wdtWriteProtect, 0)                 // reverrouille
        try await Task.sleep(for: .milliseconds(50))
    }

    /// Neutralise le watchdog RTC et fait nourrir le super-watchdog : sur l'USB-Serial-JTAG,
    /// la ROM ne le fait pas et la puce redémarrerait en pleine opération.
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
            throw ProtocolError.invalidResponse("GET_SECURITY_INFO : \(reply.payload.count) octets")
        }
        return info
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
