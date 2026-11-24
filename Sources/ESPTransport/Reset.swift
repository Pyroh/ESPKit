// SPDX-License-Identifier: MIT OR Apache-2.0

/// How to put the chip into download mode.
///
/// On development boards, DTR drives GPIO0 (boot pin) and RTS drives EN (reset)
/// through two transistors: an asserted line pulls the pin low.
public enum EntryReset: Hashable, Sendable {
    /// USB-Serial-JTAG if the port reports it; otherwise UnixTight and classic, in turn.
    case automatic
    /// ``ResetSequence/classic(holdBootFor:)``: one line at a time, works with every driver.
    case classic(holdBootFor: Duration = .milliseconds(50))
    /// ``ResetSequence/unixTight(holdBootFor:)``: both lines in one system call, no spurious state.
    case unixTight(holdBootFor: Duration = .milliseconds(50))
    /// The sequence of Espressif's built-in USB-Serial-JTAG peripheral (ESP32-S3, C3, C6, H2…).
    case usbSerialJTAG
    /// Your own sequence (esptool's `--before custom`).
    case custom(ResetSequence)
    /// Leaves the lines alone: the chip is already in download mode.
    case none
}

/// What to do with the chip at the end of the session.
public enum ExitReset: Hashable, Sendable {
    /// Restarts into the application.
    case hard
    /// Software reset through the stub.
    case soft
    /// RTC watchdog reset (USB-OTG chips).
    case watchdog
    /// Does nothing: the chip stays in the ROM bootloader.
    case stayInBootloader
    /// Leaves the stub running for a later reconnection.
    case stayInStub
}

/// Sequence of DTR/RTS actions (the equivalent of `--before custom`).
public struct ResetSequence: Hashable, Sendable, ExpressibleByArrayLiteral {
    /// One action on the control lines. `true` asserts the line, which pulls its pin low.
    public enum Step: Hashable, Sendable {
        /// Sets DTR (GPIO0 on common boards).
        case dtr(Bool)
        /// Sets RTS (EN on common boards).
        case rts(Bool)
        /// Both lines in a single system call.
        case lines(dtr: Bool, rts: Bool)
        /// Pauses.
        case wait(Duration)
    }

    /// The actions, in order.
    public var steps: [Step]

    /// A sequence from a list of steps.
    public init(_ steps: [Step]) { self.steps = steps }
    /// A sequence from an array literal: `[.rts(true), .wait(.milliseconds(100)), .rts(false)]`.
    public init(arrayLiteral elements: Step...) { self.steps = elements }
}

extension ResetSequence {
    /// Portable sequential reset: EN low, then released while GPIO0 is held low.
    public static func classic(holdBootFor hold: Duration = .milliseconds(50)) -> ResetSequence {
        [
            .dtr(false), .rts(true),          // GPIO0 high, EN low: chip held in reset
            .wait(.milliseconds(100)),
            .dtr(true), .rts(false),          // GPIO0 low, EN high: the chip boots into download mode
            .wait(hold),
            .dtr(false),                      // GPIO0 released
        ]
    }

    /// POSIX variant: both lines change together, with no spurious intermediate state.
    public static func unixTight(holdBootFor hold: Duration = .milliseconds(50)) -> ResetSequence {
        [
            .lines(dtr: false, rts: false),
            .lines(dtr: true, rts: true),
            .lines(dtr: false, rts: true),    // GPIO0 haut, EN bas
            .wait(.milliseconds(100)),
            .lines(dtr: true, rts: false),    // GPIO0 bas, EN haut
            .wait(hold),
            .lines(dtr: false, rts: false),
            .dtr(false),
        ]
    }

    /// Built-in USB-Serial-JTAG peripheral: DTR and RTS are virtual, and the sequence goes
    /// through (1,1) rather than (0,0).
    public static let usbSerialJTAG: ResetSequence = [
        .rts(false), .dtr(false),
        .wait(.milliseconds(100)),
        .dtr(true), .rts(false),
        .wait(.milliseconds(100)),
        .rts(true), .dtr(false), .rts(true),
        .wait(.milliseconds(100)),
        .dtr(false), .rts(false),
    ]

    /// Pulse on EN to restart the chip. Over native USB, the chip drops off the bus
    /// during the reset, so it is given time to come back.
    public static func hardReset(overUSB: Bool) -> ResetSequence {
        overUSB
            ? [.rts(true), .wait(.milliseconds(200)), .rts(false), .wait(.milliseconds(200))]
            : [.rts(true), .wait(.milliseconds(100)), .rts(false)]
    }
}

extension Transport {
    /// Plays a reset sequence on this transport.
    public func perform(_ sequence: ResetSequence) async throws {
        for step in sequence.steps {
            try await perform(step)
        }
    }

    /// Plays a single step.
    public func perform(_ step: ResetSequence.Step) async throws {
        switch step {
        case .dtr(let value): try await setControlLines(dtr: value, rts: nil)
        case .rts(let value): try await setControlLines(dtr: nil, rts: value)
        case .lines(let dtr, let rts): try await setControlLines(dtr: dtr, rts: rts)
        case .wait(let duration): try await Task.sleep(for: duration)
        }
    }
}
