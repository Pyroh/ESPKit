// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPProtocol
import ESPSupport
import ESPTargets

/// Données à écrire à une adresse de la flash.
public struct FlashRegion: Hashable, Sendable {
    public var address: UInt32
    public var data: Data
    /// Chiffrer cette région à l'écriture (chiffrement flash actif requis). Phase 6.
    public var encrypt: Bool = false

    public init(address: UInt32, data: Data, encrypt: Bool = false) {
        self.address = address
        self.data = data
        self.encrypt = encrypt
    }
}

public struct WriteFlashOptions: Hashable, Sendable {
    /// `.automatic` : zlib, sauf sous ROM ESP8266.
    public var compression: Compression = .automatic
    public enum Compression: Hashable, Sendable { case automatic, zlib, none }
    /// Effacer toute la flash avant d'écrire (stub requis).
    public var eraseAll: Bool = false
    /// Appliqué à la région qui contient un bootloader (détectée à `chip.bootloaderOffset`).
    public var headerOverrides: FlashHeaderOverrides = .keep
    public var verification: Verification = .md5
    public enum Verification: Hashable, Sendable { case md5, none }
    /// Reflash différentiel : contenu supposé déjà présent, par adresse. Phase 6.
    public var previousContents: [FlashRegion]? = nil
    /// Avec `previousContents` : ne pas relire pour vérifier les secteurs inchangés. Phase 6.
    public var trustPreviousContents: Bool = false
    /// Comparer d'abord les MD5 et ne rien écrire si la flash contient déjà les données.
    public var skipIfUnchanged: Bool = false
    /// Ignorer la config eFuse de chiffrement pour les régions `encrypt`. Phase 6.
    public var ignoreEncryptionEfuses: Bool = false
    /// Désactiver les garde-fous (sécurité active, image incompatible avec la puce).
    public var force: Bool = false
    public var spiConnection: SPIConnection = .default
    public var flashType: FlashType = .nor

    public init() {}
}

public struct WriteFlashReport: Hashable, Sendable {
    public var regions: [Region]

    public struct Region: Hashable, Sendable {
        public var address: UInt32
        /// Octets écrits, après alignement et patch d'en-tête.
        public var byteCount: Int
        /// Octets envoyés sur la liaison, après compression.
        public var bytesSent: Int
        /// Vrai si `skipIfUnchanged` a trouvé les données déjà en place.
        public var skipped: Bool
        public var headerPatched: Bool
        /// MD5 des données écrites.
        public var md5: MD5Digest?
        public var duration: Duration
    }
}

public enum VerifyResult: Hashable, Sendable {
    case match(address: UInt32)
    case mismatch(address: UInt32, firstDifferences: [ByteDifference])
}

public struct ByteDifference: Hashable, Sendable {
    public var offset: Int
    public var expected: UInt8
    public var actual: UInt8

    public init(offset: Int, expected: UInt8, actual: UInt8) {
        self.offset = offset
        self.expected = expected
        self.actual = actual
    }
}

extension ESPDevice {
    /// Écrit les régions dans l'ordre donné. Rien ne part avant qu'on parcoure l'opération
    /// ou qu'on attende `.value`.
    /// - Rejette les régions vides, qui se chevauchent ou débordent de la flash (`UsageError.invalidArgument`).
    /// - Patche l'en-tête du bootloader selon `headerOverrides` et recalcule son SHA-256.
    /// - Refuse une image prévue pour une autre puce, ou une écriture sous 0x8000 avec Secure Boot actif,
    ///   sauf `force`.
    /// - En cas d'annulation : la flash est partiellement écrite, la puce reste dans le stub.
    ///
    /// - Throws: `TransportError`, `ConnectionError.disconnected`, `ProtocolError`, `UsageError`
    ///   (régions invalides, garde-fous, fonctions de la phase 6), `FlashError.md5Mismatch`, `CancellationError`.
    public nonisolated func writeFlash(_ regions: [FlashRegion],
                                       options: WriteFlashOptions = .init()) -> ESPOperation<WriteFlashReport> {
        ESPOperation { sink in try await self.performWriteFlash(regions, options: options, sink: sink) }
    }

    /// Lit la flash. `count == nil` : jusqu'à la fin de la flash détectée.
    /// Avec le stub, la lecture est contrôlée par le MD5 que la puce envoie à la fin.
    /// - Throws: `TransportError`, `ConnectionError.disconnected`, `ProtocolError`, `UsageError`,
    ///   `FlashError.md5Mismatch`, `CancellationError`.
    public nonisolated func readFlash(at address: UInt32, count: Int?) -> ESPOperation<Data> {
        ESPOperation { sink in try await self.performReadFlash(at: address, count: count, sink: sink) }
    }

    /// MD5 calculé par la puce, sans transférer les données.
    /// - Throws: `UsageError.unsupported` sous ROM ESP8266, `ProtocolError`, `TransportError`.
    public func flashMD5(at address: UInt32, count: Int) async throws -> MD5Digest {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("Le MD5 de la flash")
            if attachedFlash == nil { _ = try await rawAttachFlash(.default, type: .nor) }
            return try await rawFlashMD5(at: address, count: count)
        }
    }

    /// Rend une entrée par région : correspondance, ou premiers octets différents.
    public nonisolated func verifyFlash(_ regions: [FlashRegion]) -> ESPOperation<[VerifyResult]> {
        ESPOperation { sink in try await self.performVerifyFlash(regions, sink: sink) }
    }

    /// Effacement total, qui peut prendre plusieurs dizaines de secondes. Stub requis. Refusé si une
    /// sécurité est active, sauf `force`. La progression n'a qu'une étape : la puce ne rend pas
    /// compte de l'avancement.
    public nonisolated func eraseFlash(force: Bool = false) -> ESPOperation<Void> {
        ESPOperation { sink in try await self.performEraseFlash(force: force, sink: sink) }
    }

    /// Efface une zone. `address` et `count` multiples de 4 096. Stub requis.
    public func eraseRegion(at address: UInt32, count: Int, force: Bool = false) async throws {
        try await exclusive {
            try ensureFlashCommandsAvailable("L'effacement de zone")
            guard address % 0x1000 == 0, count % 0x1000 == 0, count > 0 else {
                throw UsageError.invalidArgument("adresse et taille multiples de 4 096 octets")
            }
            if !force { try checkEraseGuards() }
            _ = try await channel.execute(Command(.eraseRegion, payload: .le(address, UInt32(count))),
                                          timeout: FlashTimeouts.eraseRegion(bytes: count))
        }
    }
}

// MARK: - Implémentation

/// Délais calqués sur les valeurs par défaut d'esptool.
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
    }

    func performWriteFlash(_ regions: [FlashRegion], options: WriteFlashOptions,
                           sink: ProgressSink) async throws -> WriteFlashReport {
        try await exclusive {
            try ensureOpen()
            try ensureNotSecureDownload("L'écriture flash")
            guard options.flashType == .nor else {
                throw UsageError.unsupported(feature: "La flash NAND", chip: chip, state: state)
            }
            if options.previousContents != nil {
                throw UsageError.unsupported(feature: "Le reflash différentiel (phase 6)", chip: chip, state: state)
            }
            if regions.contains(where: \.encrypt) {
                throw UsageError.unsupported(feature: "L'écriture chiffrée (phase 6)", chip: chip, state: state)
            }
            if chip == .esp8266 && !stubRunning {
                // La ROM de l'ESP8266 efface trop large ; le stub n'a pas ce défaut.
                throw UsageError.unsupported(feature: "L'écriture flash sous ROM (charger le stub)", chip: chip, state: state)
            }
            let compress = options.compression != .none

            let flash = options.spiConnection == .default && attachedFlash != nil
                ? attachedFlash!
                : try await rawAttachFlash(options.spiConnection, type: .nor)
            let flashSize = flash.detectedSize?.byteCount ?? FlashSize.mb4.byteCount
            try validate(regions, flashSize: flashSize)
            if !options.force { try checkWriteGuards(regions) }

            let prepared = try regions.map { try prepare($0, overrides: options.headerOverrides, flash: flash) }
            let total = prepared.reduce(0) { $0 + $1.data.count }
            sink.report(OperationProgress(stage: .preparing, regionIndex: 0, regionCount: prepared.count,
                                          completedBytes: 0, totalBytes: total))
            if options.eraseAll {
                guard stubRunning else {
                    throw UsageError.unsupported(feature: "L'effacement total", chip: chip, state: state)
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
                if options.skipIfUnchanged, try await rawFlashMD5(at: region.address, count: region.data.count) == md5 {
                    done += region.data.count
                    sink.report(OperationProgress(stage: .writing, regionIndex: index, regionCount: prepared.count,
                                                  completedBytes: done, totalBytes: total))
                    reports.append(.init(address: region.address, byteCount: region.data.count, bytesSent: 0,
                                         skipped: true, headerPatched: region.headerPatched, md5: md5,
                                         duration: .now - started))
                    continue
                }
                let base = done
                let sent = try await rawWrite(region.data, at: region.address, compress: compress) { written in
                    sink.report(OperationProgress(stage: .writing, regionIndex: index, regionCount: prepared.count,
                                                  completedBytes: base + written, totalBytes: total))
                }
                done += region.data.count
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
            try ensureNotSecureDownload("La lecture flash")
            let flash = try await currentFlash()
            let flashSize = flash.detectedSize?.byteCount ?? FlashSize.mb4.byteCount
            let length = count ?? (flashSize - Int(address))
            guard length > 0, Int(address) + length <= flashSize else {
                throw UsageError.invalidArgument("lecture de \(length) octets à \(hex(address)) hors de la flash (\(flashSize) octets)")
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
            try ensureNotSecureDownload("La vérification flash")
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
            try ensureFlashCommandsAvailable("L'effacement total")
            if !force { try checkEraseGuards() }
            sink.report(OperationProgress(stage: .erasing, regionIndex: 0, regionCount: 1, completedBytes: 0, totalBytes: 1))
            _ = try await channel.execute(Command(.eraseFlash), timeout: FlashTimeouts.chipErase)
            sink.report(OperationProgress(stage: .erasing, regionIndex: 0, regionCount: 1, completedBytes: 1, totalBytes: 1))
        }
    }

    // MARK: Primitives (appelées sous `exclusive`)

    private func currentFlash() async throws -> FlashInfo {
        if let attachedFlash { return attachedFlash }
        return try await rawAttachFlash(.default, type: .nor)
    }

    private func ensureFlashCommandsAvailable(_ operation: String) throws {
        try ensureOpen()
        try ensureNotSecureDownload(operation)
        guard stubRunning else { throw UsageError.unsupported(feature: "\(operation) (stub requis)", chip: chip, state: state) }
    }

    /// Envoie `data` à `address` par blocs : 16 Kio avec le stub, 1 Kio sous ROM.
    /// - Returns: le nombre d'octets envoyés (après compression).
    private func rawWrite(_ data: Data, at address: UInt32, compress: Bool,
                          progress: (Int) -> Void) async throws -> Int {
        let blockSize = stubRunning ? 0x4000 : 0x400
        let wire = compress ? try Zlib.compress(data) : data
        let blocks = max(1, (wire.count + blockSize - 1) / blockSize)
        // Rapport décompressé/compressé : sert à estimer le travail de la puce par bloc.
        let ratio = Double(data.count) / Double(max(wire.count, 1))

        // Le stub veut la taille décompressée ; la ROM, la taille à effacer.
        let size = stubRunning || !compress ? data.count : (data.count + 0xFFF) / 0x1000 * 0x1000
        var begin = Data.le(UInt32(size), UInt32(blocks), UInt32(blockSize), address)
        if !stubRunning && descriptor.romFlashBeginHasEncryptionWord { begin.appendLE(UInt32(0)) }
        // La ROM efface toute la zone dans FLASH_BEGIN ; le stub efface au fil de l'eau.
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
            // Le stub accuse réception avant d'écrire : le délai couvre aussi le bloc précédent.
            let work = Int(Double(blockSize) * ratio)
            _ = try await channel.execute(Command(compress ? .flashDeflData : .flashData, payload: payload,
                                                  checksum: Command.checksum(of: chunk)),
                                          timeout: FlashTimeouts.eraseWrite(bytes: 2 * work))
            progress(min(data.count, Int(Double((sequence + 1) * blockSize) * ratio)))
        }
        // Barrière : le stub ne répond qu'une fois le dernier bloc réellement écrit.
        _ = try await channel.execute(Command(.readReg, payload: .le(ChipDescriptor.magicRegister)),
                                      timeout: FlashTimeouts.eraseWrite(bytes: Int(Double(blockSize) * ratio)))
        return wire.count
    }

    func rawFlashMD5(at address: UInt32, count: Int) async throws -> MD5Digest {
        if chip == .esp8266 && !stubRunning {
            throw UsageError.unsupported(feature: "SPI_FLASH_MD5 sous ROM", chip: chip, state: state)
        }
        let reply = try await channel.execute(Command(.spiFlashMD5, payload: .le(address, UInt32(count), UInt32(0), UInt32(0))),
                                              timeout: FlashTimeouts.md5(bytes: count))
        // La ROM rend 32 caractères hexadécimaux, le stub 16 octets bruts.
        let bytes: Data?
        switch reply.payload.count {
        case 32...: bytes = Self.decodeHex(reply.payload.prefix(32))
        case 16...: bytes = reply.payload.prefix(16)
        default: bytes = nil
        }
        guard let bytes, let digest = MD5Digest(bytes: Data(bytes)) else {
            throw ProtocolError.invalidResponse("SPI_FLASH_MD5 : \(reply.payload.count) octets")
        }
        return digest
    }

    private func rawReadFlash(at address: UInt32, count: Int, progress: (Int) -> Void) async throws -> Data {
        guard stubRunning else { return try await rawReadFlashSlow(at: address, count: count, progress: progress) }
        // Si une trame se perd, le stub attend un accusé que l'hôte ne peut pas envoyer : la lecture
        // s'interrompt sur un délai dépassé. On relance alors la lecture à partir du dernier
        // tronçon complet, deux fois au plus.
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

    /// Une commande READ_FLASH : blocs de 4 Kio, un accusé par bloc, puis le MD5 du stub.
    private func rawReadFlashStream(at address: UInt32, count: Int, progress: (Int) -> Void) async throws -> Data {
        _ = try await channel.execute(Command(.readFlash, payload: .le(address, UInt32(count), UInt32(0x1000), UInt32(1))))
        var out = Data(capacity: count)
        do {
            while out.count < count {
                try Task.checkCancellation()
                let packet = try await channel.receivePacket(timeout: FlashTimeouts.minimum, opcode: Opcode.readFlash.rawValue)
                out.append(packet)
                guard out.count <= count else {
                    throw ProtocolError.invalidResponse("READ_FLASH : \(out.count) octets reçus pour \(count) demandés")
                }
                // Accusé de réception : total reçu jusqu'ici.
                try await channel.sendRaw(.le(UInt32(out.count)))
                progress(out.count)
            }
            let digest = try await channel.receivePacket(timeout: FlashTimeouts.minimum, opcode: Opcode.readFlash.rawValue)
            guard let expected = MD5Digest(bytes: digest) else {
                throw ProtocolError.invalidResponse("READ_FLASH : MD5 final de \(digest.count) octets")
            }
            let actual = MD5Digest(bytes: MD5.hash(out))!
            guard actual == expected else { throw FlashError.md5Mismatch(address: address, expected: expected, actual: actual) }
            return out
        } catch {
            // Interrompt la boucle d'envoi du stub : une trame qui n'est pas un accusé l'arrête.
            try? await channel.sendRaw(Data([0]))
            try? await channel.drain(quietPeriod: .milliseconds(200))
            throw error
        }
    }

    /// Lecture ROM : 64 octets par commande.
    private func rawReadFlashSlow(at address: UInt32, count: Int, progress: (Int) -> Void) async throws -> Data {
        var out = Data(capacity: count)
        while out.count < count {
            try Task.checkCancellation()
            let wanted = min(64, count - out.count)
            let reply = try await channel.execute(Command(.readFlashSlow, payload: .le(address + UInt32(out.count), UInt32(64))))
            guard reply.payload.count >= wanted else {
                throw ProtocolError.invalidResponse("READ_FLASH_SLOW : \(reply.payload.count) octets")
            }
            out.append(reply.payload.prefix(wanted))
            if out.count % 0x1000 == 0 || out.count == count { progress(out.count) }
        }
        return out
    }

    // MARK: Préparation et garde-fous

    private func validate(_ regions: [FlashRegion], flashSize: Int) throws {
        for region in regions {
            guard !region.data.isEmpty else { throw UsageError.invalidArgument("région vide à \(hex(region.address))") }
            guard Int(region.address) + region.data.count <= flashSize else {
                throw UsageError.invalidArgument("la région \(hex(region.address)) (\(region.data.count) octets) déborde de la flash (\(flashSize) octets)")
            }
        }
        let sorted = regions.sorted { $0.address < $1.address }
        for (previous, next) in zip(sorted, sorted.dropFirst())
        where Int(previous.address) + previous.data.count > Int(next.address) {
            throw UsageError.invalidArgument("les régions \(hex(previous.address)) et \(hex(next.address)) se chevauchent")
        }
    }

    private func checkWriteGuards(_ regions: [FlashRegion]) throws {
        if cachedSecurityInfo?.flags.contains(.secureBootEnabled) == true,
           let low = regions.first(where: { $0.address < 0x8000 }) {
            throw UsageError.securityRestriction("Secure Boot actif : écriture à \(hex(low.address)), sous 0x8000")
        }
        guard chip != .esp8266, let expected = chip.imageChipID else { return }
        for region in regions where region.data.count >= 24 && region.data[region.data.startIndex] == 0xE9 {
            let id = UInt16(region.data[region.data.startIndex + 12]) | UInt16(region.data[region.data.startIndex + 13]) << 8
            guard id == expected else {
                let target = ChipFamily(imageChipID: id).map(\.displayName) ?? "chip ID \(id)"
                throw UsageError.imageIncompatible("l'image à \(hex(region.address)) vise \(target), la puce est un \(chip)")
            }
        }
    }

    private func checkEraseGuards() throws {
        guard let info = cachedSecurityInfo else { return }
        if info.flags.contains(.secureBootEnabled) || info.flashEncryptionEnabled {
            throw UsageError.securityRestriction("Secure Boot ou chiffrement flash actif : effacement refusé")
        }
    }

    /// Alignement sur 4 octets, patch d'en-tête, et alignement sur secteur sous ROM.
    private func prepare(_ region: FlashRegion, overrides: FlashHeaderOverrides, flash: FlashInfo) throws -> PreparedRegion {
        var data = Data(region.data)
        var patched = false
        if region.address == chip.bootloaderOffset {
            patched = try patchHeader(&data, overrides: overrides, flash: flash)
        }
        if data.count % 4 != 0 { data.append(Data(repeating: 0xFF, count: 4 - data.count % 4)) }
        var address = region.address
        if !stubRunning, address % 0x1000 != 0 {
            // La ROM efface par secteurs entiers : on complète le début du secteur par 0xFF.
            let misalignment = Int(address % 0x1000)
            data = Data(repeating: 0xFF, count: misalignment) + data
            address -= UInt32(misalignment)
        }
        return PreparedRegion(address: address, data: data, headerPatched: patched)
    }

    /// Octets 2 et 3 de l'en-tête : mode, puis taille (quartet haut) et fréquence (quartet bas).
    /// Recalcule le SHA-256 final quand l'image en porte un.
    private func patchHeader(_ data: inout Data, overrides: FlashHeaderOverrides, flash: FlashInfo) throws -> Bool {
        guard overrides != .keep, data.count >= 8, data[0] == 0xE9 else { return false }
        var mode = data[2], sizeAndFrequency = data[3]
        if case .set(let value) = overrides.mode { mode = ChipDescriptor.headerCode(for: value) }
        let size: FlashSize?
        switch overrides.size {
        case .keep: size = nil
        case .set(let value): size = value
        case .detect:
            guard let detected = flash.detectedSize else {
                throw UsageError.invalidArgument("taille de flash non détectée (ID JEDEC \(hex(flash.jedecID)))")
            }
            size = detected
        }
        if let size {
            guard let code = descriptor.headerCode(for: size) else {
                throw UsageError.invalidArgument("taille \(size) non encodable pour \(chip)")
            }
            sizeAndFrequency = sizeAndFrequency & 0x0F | code << 4
        }
        if case .set(let frequency) = overrides.frequency {
            guard let code = descriptor.headerCode(for: frequency) else {
                throw UsageError.invalidArgument("fréquence \(frequency) non encodable pour \(chip)")
            }
            sizeAndFrequency = sizeAndFrequency & 0xF0 | code
        }
        guard mode != data[2] || sizeAndFrequency != data[3] else { return false }
        data[2] = mode
        data[3] = sizeAndFrequency
        if chip != .esp8266, data.count >= 24, data[23] == 1, let end = Self.imageEnd(data), data.count >= end + 32 {
            data.replaceSubrange(end..<end + 32, with: SHA256.hash(data.prefix(end)))
        }
        return true
    }

    /// Fin d'une image ESP32-x, octet de somme de contrôle compris (avant l'empreinte SHA-256).
    static func imageEnd(_ data: Data) -> Int? {
        guard data.count >= 24 else { return nil }
        var offset = 24
        for _ in 0..<Int(data[1]) {
            guard offset + 8 <= data.count else { return nil }
            offset += 8 + Int(data.readLE32(at: offset + 4))
            guard offset <= data.count else { return nil }
        }
        // Remplissage jusqu'à 16 n − 1, puis l'octet de somme de contrôle.
        return (offset + 1 + 15) / 16 * 16
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
