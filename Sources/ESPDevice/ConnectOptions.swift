// SPDX-License-Identifier: MIT OR Apache-2.0

import ESPTargets
import ESPTransport

/// Settings for `ESPDevice.connect`.
public struct ConnectOptions: Sendable {
    /// How the chip is put into download mode. `.automatic` picks the USB-Serial-JTAG sequence
    /// when the port reports that peripheral, otherwise tries UnixTight then classic.
    public var entryReset: EntryReset = .automatic
    /// Sync baud rate, capped at 115,200 as esptool does.
    public var initialBaudRate: Int = 115_200
    /// Working baud rate, applied after the stub is loaded. `nil` = stay at the initial rate.
    public var baudRate: Int? = 460_800
    /// Whether to load a flasher stub after the sync (faster, more commands).
    public var stub: StubPolicy = .load
    /// `nil`: automatic detection. Otherwise, an error if the detected chip differs.
    public var expectedChip: ChipFamily? = nil
    /// 0 = unlimited.
    public var connectAttempts: Int = 7
    /// Skips the sync (`--before no-reset-no-sync`): the chip already speaks the protocol.
    public var skipSync: Bool = false
    /// ESP32 only: force the VDDSDIO regulator.
    public var vddsdioOverride: VDDSDIOOverride? = nil
    /// Receives the low-level trace from the first reset on. `nil` = no trace.
    public var trace: AsyncStream<TraceEvent>.Continuation? = nil

    /// The defaults: automatic reset, bundled stub, 460,800 baud, seven attempts, no trace.
    public init() {}
}

/// Which code answers the protocol once connected.
public enum StubPolicy: Sendable, Hashable {
    /// Bundled stub v2 for the detected chip (default).
    case load
    /// `--no-stub`.
    case romOnly
    /// Stub supplied by the caller.
    case custom(StubImage)
}

/// Forced voltage of the ESP32 VDDSDIO regulator (the flash supply).
public enum VDDSDIOOverride: Hashable, Sendable {
    /// 1.8 V.
    case volts1_8
    /// 1.9 V.
    case volts1_9
    /// Regulator off.
    case off
}
