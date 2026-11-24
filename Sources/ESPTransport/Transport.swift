// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTargets

/// Byte channel to a chip. ESPKit provides `SerialPort`; implement this protocol
/// for another link (network, tests).
public protocol Transport: Sendable {
    /// Opens the link. Called once by `ESPDevice.connect`; calling it again on an open link does nothing.
    func open() async throws
    /// Closes the link. Never fails; later calls throw ``TransportError/closed``.
    func close() async
    /// Sends every byte of `data`, in order.
    func write(_ data: Data) async throws
    /// Returns at most `maxCount` bytes as soon as some arrive, or empty data when the timeout expires.
    func read(maxCount: Int, timeout: Duration) async throws -> Data
    /// Drops the bytes received but not read yet.
    func discardInput() async throws
    /// Switches the local side to `rate` baud (the chip is switched separately, by the protocol).
    func setBaudRate(_ rate: Int) async throws
    /// Changes DTR and/or RTS **in a single system call** when both are given.
    func setControlLines(dtr: Bool?, rts: Bool?) async throws
    /// USB identity of the port, if known (used to choose the automatic reset).
    var usbIdentity: USBIdentity? { get }
}

/// USB identity of a serial port.
public struct USBIdentity: Hashable, Sendable {
    /// USB vendor ID (0x303A for Espressif, 0x1A86 for WCH's CH340, 0x10C4 for Silicon Labs' CP210x…).
    public var vendorID: UInt16
    /// USB product ID.
    public var productID: UInt16
    /// The device's serial number string, if it has one.
    public var serialNumber: String?
    /// The manufacturer string.
    public var manufacturer: String?
    /// The product string.
    public var product: String?

    /// A USB identity; the strings are optional, as many adapters omit some.
    public init(vendorID: UInt16, productID: UInt16, serialNumber: String? = nil,
                manufacturer: String? = nil, product: String? = nil) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.manufacturer = manufacturer
        self.product = product
    }

    /// Espressif's USB vendor ID.
    public static let espressifVendorID: UInt16 = 0x303A
    /// Product ID of the built-in USB-Serial-JTAG peripheral.
    public static let usbSerialJTAGProductID: UInt16 = 0x1001

    /// True for Espressif's built-in USB-Serial-JTAG peripheral (303A:1001).
    public var isEspressifUSBSerialJTAG: Bool {
        vendorID == Self.espressifVendorID && productID == Self.usbSerialJTAGProductID
    }
}

/// Serial transport errors.
public enum TransportError: ESPKitError, Equatable {
    /// `open(2)` or the port configuration failed with this `errno`.
    case openFailed(path: String, errno: Int32)
    /// Another program holds the port (`TIOCEXCL` or `flock` refused).
    case portBusy(path: String)
    /// A read, write or control call failed with this `errno`.
    case ioFailed(errno: Int32)
    /// The driver refused this baud rate.
    case unsupportedBaudRate(Int)
    /// The port went away: cable unplugged, or USB-Serial-JTAG re-enumeration after a reset.
    case deviceRemoved
    /// The transport was used after `close()`.
    case closed

    /// A message for people, in English.
    public var description: String {
        switch self {
        case .openFailed(let path, let code): "Cannot open \(path): \(String(cString: strerror(code)))"
        case .portBusy(let path): "Port \(path) is already in use by another program"
        case .ioFailed(let code): "Serial port I/O error: \(String(cString: strerror(code)))"
        case .unsupportedBaudRate(let rate): "Baud rate not supported by the port: \(rate)"
        case .deviceRemoved: "The serial port went away (cable unplugged or USB device re-enumerated)"
        case .closed: "The serial port is closed"
        }
    }
}
