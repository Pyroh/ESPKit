// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Dispatch
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Port série POSIX (`/dev/cu.*` sur macOS, `/dev/ttyUSB*` ou `/dev/ttyACM*` sur Linux).
///
/// Les appels système bloquants (`poll`, `read`, `write`) tournent sur une file dédiée : ils
/// n'occupent jamais un fil du pool coopératif de Swift Concurrency.
public actor SerialPort: Transport {
    public nonisolated let path: String
    public nonisolated let usbIdentity: USBIdentity?

    private var descriptor: Int32 = -1
    private let io: DispatchQueue

    /// Ne fait pas d'I/O : le port s'ouvre avec `open()`.
    /// L'identité USB est relevée ici, à partir de la liste des ports présents.
    public init(path: String) {
        self.path = path
        self.usbIdentity = (try? SerialPorts.available())?.first(where: { $0.path == path })?.usb
        self.io = DispatchQueue(label: "ESPKit.SerialPort \(path)")
    }

    deinit {
        if descriptor >= 0 { _ = systemClose(descriptor) }
    }

    // MARK: Transport

    public func open() async throws {
        guard descriptor < 0 else { return }
        let path = self.path
        descriptor = try await onIOQueue { try Self.openDescriptor(path: path) }
    }

    public func close() async {
        guard descriptor >= 0 else { return }
        let fd = descriptor
        descriptor = -1
        await onIOQueue { _ = systemClose(fd) }
    }

    public func write(_ data: Data) async throws {
        let fd = try openDescriptor()
        try await onIOQueue { try Self.writeAll(fd: fd, data: data) }
    }

    public func read(maxCount: Int, timeout: Duration) async throws -> Data {
        let fd = try openDescriptor()
        return try await onIOQueue { try Self.read(fd: fd, maxCount: maxCount, timeout: timeout) }
    }

    public func discardInput() async throws {
        let fd = try openDescriptor()
        try await onIOQueue {
            guard tcflush(fd, TCIFLUSH) == 0 else { throw Self.ioError() }
        }
    }

    public func setBaudRate(_ rate: Int) async throws {
        let fd = try openDescriptor()
        try await onIOQueue { try Self.applyBaudRate(rate, fd: fd) }
    }

    public func setControlLines(dtr: Bool?, rts: Bool?) async throws {
        guard dtr != nil || rts != nil else { return }
        let fd = try openDescriptor()
        try await onIOQueue {
            var bits: Int32 = 0
            guard ioctl(fd, PortIoctl.getModemBits, &bits) == 0 else { throw Self.ioError() }
            if let dtr { bits = dtr ? bits | PortIoctl.dtrBit : bits & ~PortIoctl.dtrBit }
            if let rts { bits = rts ? bits | PortIoctl.rtsBit : bits & ~PortIoctl.rtsBit }
            guard ioctl(fd, PortIoctl.setModemBits, &bits) == 0 else { throw Self.ioError() }
        }
    }

    // MARK: Implémentation

    private func openDescriptor() throws -> Int32 {
        guard descriptor >= 0 else { throw TransportError.closed }
        return descriptor
    }

    private func onIOQueue<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            io.async { continuation.resume(with: Result { try body() }) }
        }
    }

    private func onIOQueue(_ body: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            io.async {
                body()
                continuation.resume()
            }
        }
    }

    private static func openDescriptor(path: String) throws -> Int32 {
        let fd = systemOpen(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            let code = errno
            throw code == EBUSY ? TransportError.portBusy(path: path) : TransportError.openFailed(path: path, errno: code)
        }
        do {
            // Accès exclusif : un second `open` échouera avec EBUSY.
            guard ioctl(fd, PortIoctl.exclusive) == 0 else {
                throw errno == EBUSY ? TransportError.portBusy(path: path) : ioError()
            }
            var options = termios()
            guard tcgetattr(fd, &options) == 0 else { throw ioError() }
            cfmakeraw(&options)
            options.c_cflag |= tcflag_t(CLOCAL) | tcflag_t(CREAD)
            // Les constantes n'ont pas le même type selon le système (CRTSCTS est non signé sous Linux).
            options.c_cflag &= ~(tcflag_t(CRTSCTS) | tcflag_t(CSTOPB) | tcflag_t(PARENB))
            withUnsafeMutableBytes(of: &options.c_cc) { cc in
                cc[Int(VMIN)] = 0
                cc[Int(VTIME)] = 0
            }
            guard tcsetattr(fd, TCSANOW, &options) == 0 else { throw ioError() }
            try applyBaudRate(115_200, fd: fd)
            _ = tcflush(fd, TCIOFLUSH)
            return fd
        } catch {
            _ = systemClose(fd)
            throw error
        }
    }

    private static func applyBaudRate(_ rate: Int, fd: Int32) throws {
        guard rate > 0 else { throw TransportError.unsupportedBaudRate(rate) }
        #if canImport(Darwin)
        // IOSSIOSPEED accepte n'importe quel débit, standard ou non.
        var speed = speed_t(rate)
        guard ioctl(fd, PortIoctl.setSpeed, &speed) == 0 else {
            throw errno == EINVAL ? TransportError.unsupportedBaudRate(rate) : ioError()
        }
        #else
        guard let constant = standardSpeed(rate) else { throw TransportError.unsupportedBaudRate(rate) }
        var options = termios()
        guard tcgetattr(fd, &options) == 0 else { throw ioError() }
        cfsetispeed(&options, constant)
        cfsetospeed(&options, constant)
        guard tcsetattr(fd, TCSANOW, &options) == 0 else { throw ioError() }
        #endif
    }

    #if !canImport(Darwin)
    /// Débits standard sous Linux. Les débits arbitraires (termios2/BOTHER) arrivent en phase 1.
    private static func standardSpeed(_ rate: Int) -> speed_t? {
        switch rate {
        case 9_600: speed_t(B9600)
        case 19_200: speed_t(B19200)
        case 38_400: speed_t(B38400)
        case 57_600: speed_t(B57600)
        case 115_200: speed_t(B115200)
        case 230_400: speed_t(B230400)
        case 460_800: speed_t(B460800)
        case 921_600: speed_t(B921600)
        case 1_500_000: speed_t(B1500000)
        case 2_000_000: speed_t(B2000000)
        default: nil
        }
    }
    #endif

    private static func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = systemWrite(fd, base + offset, buffer.count - offset)
                if written > 0 {
                    offset += written
                    continue
                }
                let code = errno
                if written < 0 && (code == EAGAIN || code == EINTR) {
                    var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&descriptor, 1, 1_000)
                    if descriptor.revents & Int16(POLLHUP | POLLNVAL) != 0 { throw TransportError.deviceRemoved }
                    continue
                }
                throw disconnectionOrIOError(code)
            }
        }
    }

    private static func read(fd: Int32, maxCount: Int, timeout: Duration) throws -> Data {
        guard maxCount > 0 else { return Data() }
        let milliseconds = max(0, Int32(clamping: timeout.components.seconds * 1_000
                                        + timeout.components.attoseconds / 1_000_000_000_000_000))
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, milliseconds)
        if ready < 0 {
            if errno == EINTR { return Data() }
            throw ioError()
        }
        if ready == 0 { return Data() }
        if descriptor.revents & Int16(POLLNVAL) != 0 { throw TransportError.closed }
        var buffer = Data(count: maxCount)
        let count = buffer.withUnsafeMutableBytes { systemRead(fd, $0.baseAddress, maxCount) }
        if count > 0 { return buffer.prefix(count) }
        if count == 0 || descriptor.revents & Int16(POLLHUP) != 0 { throw TransportError.deviceRemoved }
        let code = errno
        if code == EAGAIN || code == EINTR { return Data() }
        throw disconnectionOrIOError(code)
    }

    private static func disconnectionOrIOError(_ code: Int32) -> TransportError {
        code == ENXIO || code == ENODEV || code == EIO ? .deviceRemoved : .ioFailed(errno: code)
    }

    private static func ioError() -> TransportError { .ioFailed(errno: errno) }
}

// MARK: - Appels système

// Les noms POSIX `open`, `close`, `read` et `write` sont masqués par les méthodes de l'acteur.
private func systemOpen(_ path: String, _ flags: Int32) -> Int32 { open(path, flags) }
private func systemClose(_ fd: Int32) -> Int32 { close(fd) }
private func systemRead(_ fd: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int { read(fd, buffer, count) }
private func systemWrite(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int { write(fd, buffer, count) }

/// Requêtes `ioctl` des ports série. Les macros `_IOR`/`_IOW` ne sont pas importées en Swift.
private enum PortIoctl {
    #if canImport(Darwin)
    static let exclusive: UInt = 0x2000_740D        // TIOCEXCL   = _IO('t', 13)
    static let getModemBits: UInt = 0x4004_746A     // TIOCMGET   = _IOR('t', 106, int)
    static let setModemBits: UInt = 0x8004_746D     // TIOCMSET   = _IOW('t', 109, int)
    static let setSpeed: UInt = 0x8008_5402         // IOSSIOSPEED = _IOW('T', 2, speed_t)
    #else
    static let exclusive: UInt = 0x540C             // TIOCEXCL
    static let getModemBits: UInt = 0x5415          // TIOCMGET
    static let setModemBits: UInt = 0x5418          // TIOCMSET
    #endif
    static let dtrBit: Int32 = 0x002                // TIOCM_DTR
    static let rtsBit: Int32 = 0x004                // TIOCM_RTS
}
