// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTargets
import ESPTransport

extension ESPDevice {
    /// Opens the transport, performs the entry reset, syncs, detects the chip,
    /// then applies `options.stub` and `options.baudRate`.
    ///
    /// - Throws: `TransportError`, `ConnectionError` (`noResponse`, `chipMismatch`, `unknownChip`),
    ///   `ProtocolError`, `StubError`, `UsageError`, `CancellationError`.
    ///   On failure, the transport is closed again.
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

    /// Connects through the serial port at `path`, for example "/dev/cu.usbserial-0001".
    ///
    /// The same as ``connect(_:options:)`` with a `SerialPort`.
    public static func connect(port path: String,
                               options: ConnectOptions = .init()) async throws -> ESPDevice {
        try await connect(SerialPort(path: path), options: options)
    }

    /// Tries each port matching the filter and returns the first one that answers.
    /// - Throws: `ConnectionError.noMatchingPort` if no port matches; otherwise the error
    ///   of the last port tried.
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

    // MARK: - Connection sequence

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
            state = .stub(.custom("already running"))
        } else if detection.secureDownloadMode {
            state = .secureDownloadMode
        } else {
            state = .rom
        }
        let device = ESPDevice(channel: channel, chip: detection.chip, state: state,
                               baudRate: initialRate, securityInfo: detection.securityInfo)

        try await device.exclusive { try await device.disableWatchdogsForUSBSerialJTAG() }

        if options.vddsdioOverride != nil {
            throw UsageError.unsupported(feature: "VDDSDIO override (phase 6)", chip: detection.chip, state: state)
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

    /// Entry reset then SYNC, rotating strategies across attempts.
    /// - Returns: `true` if a stub was already answering (value 0 in the SYNC responses).
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

    /// Up to 5 SYNCs of 100 ms. `nil` if the chip does not answer.
    private static func sync(_ channel: ProtocolChannel) async throws -> Bool? {
        // 07 07 12 20 then 32 × 0x55: the ROM locks its auto-baud on this pattern.
        let payload = Data([0x07, 0x07, 0x12, 0x20] + [UInt8](repeating: 0x55, count: 32))
        for _ in 0..<5 {
            try Task.checkCancellation()
            try await channel.send(Command(.sync, payload: payload))
            do {
                let response = try await channel.receive(opcode: Opcode.sync.rawValue, timeout: .milliseconds(100))
                // The ROM sends several responses to one SYNC: drain the extra ones.
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
                // Standard delay, then a delay 500 ms longer for boards that are slow to start.
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

    /// GET_SECURITY_INFO first (chip ID of recent chips, also valid in Secure Download Mode),
    /// otherwise read the ROM magic value.
    static func detectChip(_ channel: ProtocolChannel, stubRunning: Bool) async throws -> Detection {
        await channel.setStatusLength(stubRunning ? 2 : nil)

        var info: SecurityInfo?
        do {
            info = try await ESPDevice.readSecurityInfo(channel)
        } catch let error as ProtocolError {
            // The ESP8266 and ESP32 do not know the command: they answer with a failure
            // or not at all.
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
            // Read refused and security info readable without a chip ID: ESP32-S2 in Secure Download Mode.
            return Detection(chip: .esp32s2, secureDownloadMode: true, securityInfo: info)
        }
        guard let chip = ChipDescriptor.family(forMagic: magic) else {
            throw ConnectionError.unknownChip(magic: magic, chipID: nil)
        }
        return Detection(chip: chip, secureDownloadMode: secureDownload, securityInfo: info)
    }
}
