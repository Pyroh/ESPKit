// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import ESPTargets

/// Byte channel to a chip. ESPKit provides `SerialPort`; implement this protocol
/// for another link (network, tests).
public protocol Transport: Sendable {
    func open() async throws
    func close() async
    func write(_ data: Data) async throws
    /// Returns at most `maxCount` bytes as soon as some arrive, or empty data when the timeout expires.
    func read(maxCount: Int, timeout: Duration) async throws -> Data
    func discardInput() async throws
    func setBaudRate(_ rate: Int) async throws
    /// Changes DTR and/or RTS **in a single system call** when both are given.
    func setControlLines(dtr: Bool?, rts: Bool?) async throws
    /// USB identity of the port, if known (used to choose the automatic reset).
    var usbIdentity: USBIdentity? { get }
}

/// USB identity of a serial port.
public struct USBIdentity: Hashable, Sendable {
    public var vendorID: UInt16
    public var productID: UInt16
    public var serialNumber: String?
    public var manufacturer: String?
    public var product: String?

    public init(vendorID: UInt16, productID: UInt16, serialNumber: String? = nil,
                manufacturer: String? = nil, product: String? = nil) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.manufacturer = manufacturer
        self.product = product
    }

    /// Identifiant USB d'Espressif.
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
    case openFailed(path: String, errno: Int32)
    case portBusy(path: String)
    case ioFailed(errno: Int32)
    case unsupportedBaudRate(Int)
    /// The port went away: cable unplugged, or USB-Serial-JTAG re-enumeration after a reset.
    case deviceRemoved
    case closed

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
