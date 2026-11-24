// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPProtocol
import ESPTargets
import ESPTransport

extension ESPDevice {
    /// Ouvre le transport, fait le reset d'entrée, se synchronise, détecte la puce,
    /// puis applique `options.stub` et `options.baudRate`.
    ///
    /// - Throws: `TransportError`, `ConnectionError` (`noResponse`, `chipMismatch`, `unknownChip`),
    ///   `ProtocolError`, `StubError`, `UsageError`, `CancellationError`.
    ///   En cas d'échec, le transport est refermé.
    public static func connect(_ transport: some Transport,
                               options: ConnectOptions = .init()) async throws -> ESPDevice {
        let channel = ProtocolChannel(transport: transport, trace: options.trace)
        do {
            return try await establish(on: channel, options: options)
        } catch {
            await transport.close()
            options.trace?.finish()
            throw error
        }
    }

    public static func connect(port path: String,
                               options: ConnectOptions = .init()) async throws -> ESPDevice {
        try await connect(SerialPort(path: path), options: options)
    }

    /// Essaie chaque port correspondant au filtre et rend le premier qui répond.
    /// - Throws: `ConnectionError.noMatchingPort` si aucun port ne correspond ; sinon l'erreur
    ///   du dernier port essayé.
    public static func connectFirstAvailable(matching filter: PortFilter = .init(),
                                             options: ConnectOptions = .init()) async throws -> ESPDevice {
        let ports = try SerialPorts.available(matching: filter)
        guard !ports.isEmpty else { throw ConnectionError.noMatchingPort }
        var lastError: any Error = ConnectionError.noMatchingPort
        for port in ports {
            try Task.checkCancellation()
            do {
                return try await connect(port: port.path, options: options)
            } catch let error as CancellationError {
                throw error
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: - Séquence de connexion

    private static func establish(on channel: ProtocolChannel, options: ConnectOptions) async throws -> ESPDevice {
        let transport = channel.transport
        let initialRate = min(options.initialBaudRate, 115_200)
        try await transport.open()
        try await transport.setBaudRate(initialRate)

        var stubAlreadyRunning = false
        if !options.skipSync {
            stubAlreadyRunning = try await resetAndSync(channel, options: options)
        }

        let detection = try await detectChip(channel, stubRunning: stubAlreadyRunning)
        if let expected = options.expectedChip, expected != detection.chip {
            throw ConnectionError.chipMismatch(expected: expected, detected: detection.chip)
        }
        let descriptor = ChipDescriptor(family: detection.chip)
        await channel.setStatusLength(descriptor.statusLength(stubRunning: stubAlreadyRunning))

        let state: State
        if stubAlreadyRunning {
            state = .stub(.custom("déjà actif"))
        } else if detection.secureDownloadMode {
            state = .secureDownloadMode
        } else {
            state = .rom
        }
        let device = ESPDevice(channel: channel, chip: detection.chip, state: state,
                               baudRate: initialRate, securityInfo: detection.securityInfo)

        try await device.exclusive { try await device.disableWatchdogsForUSBSerialJTAG() }

        if options.vddsdioOverride != nil {
            throw UsageError.unsupported(feature: "Le forçage VDDSDIO (phase 6)", chip: detection.chip, state: state)
        }
        switch options.stub {
        case .romOnly: break
        case .load: if state == .rom { try await device.loadStub() }
        case .custom(let image): if state == .rom { try await device.loadStub(image) }
        }
        if let rate = options.baudRate, rate != initialRate {
            try await device.changeBaudRate(rate)
        }
        return device
    }

    /// Reset d'entrée puis SYNC, avec la rotation des stratégies sur les tentatives.
    /// - Returns: `true` si un stub répondait déjà (valeur 0 dans les réponses SYNC).
    private static func resetAndSync(_ channel: ProtocolChannel, options: ConnectOptions) async throws -> Bool {
        let sequences = entrySequences(for: options.entryReset, usb: channel.transport.usbIdentity)
        let attempts = options.connectAttempts
        var attempt = 0
        while attempts == 0 || attempt < attempts {
            try Task.checkCancellation()
            if let sequence = sequences.isEmpty ? nil : sequences[attempt % sequences.count] {
                for step in sequence.steps {
                    await channel.emit(.resetStep(step))
                    try await channel.transport.perform(step)
                }
            }
            try await channel.discardInput()
            if let stubRunning = try await sync(channel) {
                return stubRunning
            }
            attempt += 1
        }
        throw ConnectionError.noResponse(attempts: attempts)
    }

    /// Jusqu'à 5 SYNC de 100 ms. `nil` si la puce ne répond pas.
    private static func sync(_ channel: ProtocolChannel) async throws -> Bool? {
        // 07 07 12 20 puis 32 × 0x55 : la ROM cale son auto-baud sur ce motif.
        let payload = Data([0x07, 0x07, 0x12, 0x20] + [UInt8](repeating: 0x55, count: 32))
        for _ in 0..<5 {
            try Task.checkCancellation()
            try await channel.send(Command(.sync, payload: payload))
            do {
                let response = try await channel.receive(opcode: Opcode.sync.rawValue, timeout: .milliseconds(100))
                // La ROM envoie plusieurs réponses à un SYNC : on vide les suivantes.
                try await channel.drain(quietPeriod: .milliseconds(100))
                return response.value == 0
            } catch is ProtocolError {
                continue
            }
        }
        return nil
    }

    static func entrySequences(for reset: EntryReset, usb: USBIdentity?) -> [ResetSequence] {
        switch reset {
        case .none: []
        case .classic(let hold): [.classic(holdBootFor: hold)]
        case .unixTight(let hold): [.unixTight(holdBootFor: hold)]
        case .usbSerialJTAG: [.usbSerialJTAG]
        case .custom(let sequence): [sequence]
        case .automatic:
            if usb?.isEspressifUSBSerialJTAG == true {
                [.usbSerialJTAG]
            } else {
                // Délai standard, puis délai allongé de 500 ms pour les cartes lentes à démarrer.
                [.unixTight(holdBootFor: .milliseconds(50)), .unixTight(holdBootFor: .milliseconds(550)),
                 .classic(holdBootFor: .milliseconds(50)), .classic(holdBootFor: .milliseconds(550))]
            }
        }
    }

    struct Detection {
        var chip: ChipFamily
        var secureDownloadMode: Bool
        var securityInfo: SecurityInfo?
    }

    /// GET_SECURITY_INFO d'abord (chip ID des puces récentes, valable en Secure Download Mode),
    /// sinon lecture de la valeur magique de la ROM.
    static func detectChip(_ channel: ProtocolChannel, stubRunning: Bool) async throws -> Detection {
        await channel.setStatusLength(stubRunning ? 2 : nil)

        var info: SecurityInfo?
        do {
            info = try await ESPDevice.readSecurityInfo(channel)
        } catch let error as ProtocolError {
            // ESP8266 et ESP32 ne connaissent pas la commande : elles répondent par un échec
            // ou ne répondent pas.
            if case .timeout = error { try await channel.discardInput() }
        }
        let secureDownload = info?.flags.contains(.secureDownloadEnable) ?? false
        if let id = info?.chipID {
            guard id <= UInt16.max, let chip = ChipFamily(imageChipID: UInt16(id)) else {
                throw ConnectionError.unknownChip(magic: nil, chipID: id)
            }
            return Detection(chip: chip, secureDownloadMode: secureDownload, securityInfo: info)
        }

        let magic: UInt32
        do {
            magic = try await channel.execute(Command(.readReg, payload: .le(ChipDescriptor.magicRegister))).value
        } catch ProtocolError.deviceError where info != nil {
            // Lecture refusée et sécurité lisible sans chip ID : ESP32-S2 en Secure Download Mode.
            return Detection(chip: .esp32s2, secureDownloadMode: true, securityInfo: info)
        }
        guard let chip = ChipDescriptor.family(forMagic: magic) else {
            throw ConnectionError.unknownChip(magic: magic, chipID: nil)
        }
        return Detection(chip: chip, secureDownloadMode: secureDownload, securityInfo: info)
    }
}
