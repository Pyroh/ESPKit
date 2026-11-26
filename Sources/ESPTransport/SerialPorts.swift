// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
#if canImport(IOKit)
import IOKit
#endif

/// A serial port present on the machine.
public struct SerialPortInfo: Hashable, Sendable {
    /// For example "/dev/cu.usbmodem1101".
    public var path: String
    /// USB identity of the adapter behind the port; `nil` for a native UART.
    public var usb: USBIdentity?

    /// A port description; ``SerialPorts/available()`` builds these.
    public init(path: String, usb: USBIdentity? = nil) {
        self.path = path
        self.usb = usb
    }
}

/// Port selection criteria. A `nil` criterion is ignored.
public struct PortFilter: Hashable, Sendable {
    /// USB vendor ID to match.
    public var vendorID: UInt16?
    /// USB product ID to match.
    public var productID: UInt16?
    /// Substring the device path must contain, for example "usbmodem".
    public var pathContains: String?
    /// Substring the USB serial number must contain.
    public var serialNumberContains: String?

    /// A filter; with no criterion it matches every port.
    public init(vendorID: UInt16? = nil, productID: UInt16? = nil,
                pathContains: String? = nil, serialNumberContains: String? = nil) {
        self.vendorID = vendorID
        self.productID = productID
        self.pathContains = pathContains
        self.serialNumberContains = serialNumberContains
    }

    /// True if `port` meets every criterion that is set.
    public func matches(_ port: SerialPortInfo) -> Bool {
        if let vendorID, port.usb?.vendorID != vendorID { return false }
        if let productID, port.usb?.productID != productID { return false }
        if let pathContains, !port.path.contains(pathContains) { return false }
        if let serialNumberContains {
            guard let serial = port.usb?.serialNumber, serial.contains(serialNumberContains) else { return false }
        }
        return true
    }
}

/// Serial port discovery.
public enum SerialPorts {
    /// Serial ports present (macOS: IOKit; Linux: sysfs). Does not open them.
    public static func available() throws -> [SerialPortInfo] {
        #if canImport(IOKit)
        try availableFromIOKit()
        #elseif os(Linux)
        availableFromSysfs()
        #else
        []
        #endif
    }

    /// The present ports that `filter` matches.
    public static func available(matching filter: PortFilter) throws -> [SerialPortInfo] {
        try available().filter(filter.matches)
    }
}

#if canImport(IOKit)
extension SerialPorts {
    private static func availableFromIOKit() throws -> [SerialPortInfo] {
        guard let matching = IOServiceMatching("IOSerialBSDClient") else { return [] }
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard status == KERN_SUCCESS else { throw TransportError.ioFailed(errno: status) }
        defer { IOObjectRelease(iterator) }

        var ports: [SerialPortInfo] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            // The "callout" device (/dev/cu.*) does not wait for carrier, unlike /dev/tty.*.
            guard let path = property(service, "IOCalloutDevice", searchParents: false) as? String else { continue }
            ports.append(SerialPortInfo(path: path, usb: usbIdentity(of: service)))
        }
        return ports.sorted { $0.path < $1.path }
    }

    private static func usbIdentity(of service: io_object_t) -> USBIdentity? {
        guard let vendor = (property(service, "idVendor", searchParents: true) as? NSNumber)?.uint16Value,
              let product = (property(service, "idProduct", searchParents: true) as? NSNumber)?.uint16Value
        else { return nil }
        return USBIdentity(
            vendorID: vendor,
            productID: product,
            serialNumber: property(service, "USB Serial Number", searchParents: true) as? String,
            manufacturer: property(service, "USB Vendor Name", searchParents: true) as? String,
            product: property(service, "USB Product Name", searchParents: true) as? String
        )
    }

    private static func property(_ service: io_object_t, _ key: String, searchParents: Bool) -> Any? {
        if searchParents {
            let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            return IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault, options)
        }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
#endif

#if os(Linux)
extension SerialPorts {
    /// Walks /sys/class/tty: only ports backed by a real device are returned.
    private static func availableFromSysfs() -> [SerialPortInfo] {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: "/sys/class/tty")
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else { return [] }
        var ports: [SerialPortInfo] = []
        for name in names {
            let deviceLink = root.appendingPathComponent(name).appendingPathComponent("device")
            guard let device = try? fileManager.destinationOfSymbolicLink(atPath: deviceLink.path) else { continue }
            let deviceURL = URL(fileURLWithPath: device, relativeTo: deviceLink.deletingLastPathComponent())
                .standardizedFileURL
            // 8250 ports with no hardware behind them show up too: keep only USB and ACM,
            // plus UARTs whose driver is not "serial8250".
            let isUSB = name.hasPrefix("ttyUSB") || name.hasPrefix("ttyACM")
            if !isUSB {
                let driver = (try? fileManager.destinationOfSymbolicLink(atPath: deviceURL.appendingPathComponent("driver").path))
                guard let driver, !driver.hasSuffix("serial8250") else { continue }
            }
            ports.append(SerialPortInfo(path: "/dev/\(name)", usb: usbIdentity(startingAt: deviceURL)))
        }
        return ports.sorted { $0.path < $1.path }
    }

    /// Walks up the sysfs tree to the USB node that holds idVendor/idProduct.
    private static func usbIdentity(startingAt start: URL) -> USBIdentity? {
        var directory = start
        for _ in 0..<6 {
            let vendorFile = directory.appendingPathComponent("idVendor")
            if let vendor = readHex(vendorFile), let product = readHex(directory.appendingPathComponent("idProduct")) {
                return USBIdentity(
                    vendorID: vendor,
                    productID: product,
                    serialNumber: readText(directory.appendingPathComponent("serial")),
                    manufacturer: readText(directory.appendingPathComponent("manufacturer")),
                    product: readText(directory.appendingPathComponent("product"))
                )
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    private static func readText(_ url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func readHex(_ url: URL) -> UInt16? {
        readText(url).flatMap { UInt16($0, radix: 16) }
    }
}
#endif
