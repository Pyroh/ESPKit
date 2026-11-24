// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Dispatch
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// POSIX serial port (`/dev/cu.*` on macOS, `/dev/ttyUSB*` or `/dev/ttyACM*` on Linux).
///
/// Blocking system calls (`poll`, `read`, `write`) run on a dedicated queue: they never
/// occupy a thread of the Swift Concurrency cooperative pool.
public actor SerialPort: Transport {
    public nonisolated let path: String
    public nonisolated let usbIdentity: USBIdentity?

    private var descriptor: Int32 = -1
    private let io: DispatchQueue

    /// Performs no I/O: the port opens with `open()`.
    /// The USB identity is looked up here, from the list of present ports.
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

    // MARK: Implementation

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
            // Exclusive access: a second `open` fails with EBUSY.
            guard ioctl(fd, PortIoctl.exclusive) == 0 else {
                throw errno == EBUSY ? TransportError.portBusy(path: path) : ioError()
            }
            var options = termios()
            guard tcgetattr(fd, &options) == 0 else { throw ioError() }
            cfmakeraw(&options)
            options.c_cflag |= tcflag_t(CLOCAL) | tcflag_t(CREAD)
            // The constants have different types per system (CRTSCTS is unsigned on Linux).
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

    static func applyBaudRate(_ rate: Int, fd: Int32) throws {
        guard rate > 0 else { throw TransportError.unsupportedBaudRate(rate) }
        #if canImport(Darwin)
        // IOSSIOSPEED accepts any baud rate, standard or not.
        var speed = speed_t(rate)
        guard ioctl(fd, PortIoctl.setSpeed, &speed) == 0 else {
            throw errno == EINVAL ? TransportError.unsupportedBaudRate(rate) : ioError()
        }
        #else
        if let constant = standardSpeed(rate) {
            var options = termios()
            guard tcgetattr(fd, &options) == 0 else { throw ioError() }
            cfsetispeed(&options, constant)
            cfsetospeed(&options, constant)
            guard tcsetattr(fd, TCSANOW, &options) == 0 else { throw ioError() }
        } else {
            try applyArbitraryBaudRate(rate, fd: fd)
        }
        #endif
    }

    #if !canImport(Darwin)
    /// Standard baud rates on Linux, set through the classic termios API.
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

    /// Arbitrary baud rate: termios2 with BOTHER, the speed is given as a plain number.
    private static func applyArbitraryBaudRate(_ rate: Int, fd: Int32) throws {
        guard rate <= Int(UInt32.max) else { throw TransportError.unsupportedBaudRate(rate) }
        var options = Termios2()
        try withUnsafeMutablePointer(to: &options) { pointer in
            guard ioctl(fd, PortIoctl.getTermios2, pointer) == 0 else { throw ioError() }
            pointer.pointee.c_cflag &= ~(Termios2.cbaud | Termios2.cbaud << Termios2.inputShift)
            pointer.pointee.c_cflag |= Termios2.bother | Termios2.bother << Termios2.inputShift
            pointer.pointee.c_ispeed = UInt32(rate)
            pointer.pointee.c_ospeed = UInt32(rate)
            guard ioctl(fd, PortIoctl.setTermios2, pointer) == 0 else {
                throw errno == EINVAL ? TransportError.unsupportedBaudRate(rate) : ioError()
            }
        }
    }

    /// Reads back the baud rate actually set (for tests).
    static func currentBaudRate(fd: Int32) throws -> Int {
        var options = Termios2()
        let status = withUnsafeMutablePointer(to: &options) { ioctl(fd, PortIoctl.getTermios2, $0) }
        guard status == 0 else { throw ioError() }
        return Int(options.c_ospeed)
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

// MARK: - System calls

// The POSIX names `open`, `close`, `read` and `write` are shadowed by the actor's methods.
private func systemOpen(_ path: String, _ flags: Int32) -> Int32 { open(path, flags) }
private func systemClose(_ fd: Int32) -> Int32 { close(fd) }
private func systemRead(_ fd: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int { read(fd, buffer, count) }
private func systemWrite(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int { write(fd, buffer, count) }

/// Serial port `ioctl` requests. The `_IOR`/`_IOW` macros are not imported into Swift.
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
    static let getTermios2: UInt = 0x802C_542A      // TCGETS2 = _IOR('T', 0x2A, struct termios2)
    static let setTermios2: UInt = 0x402C_542B      // TCSETS2 = _IOW('T', 0x2B, struct termios2)
    #endif
    static let dtrBit: Int32 = 0x002                // TIOCM_DTR
    static let rtsBit: Int32 = 0x004                // TIOCM_RTS
}

#if !canImport(Darwin)
/// The Linux kernel's `struct termios2` (x86-64, arm64: 44 bytes), missing from the glibc headers.
struct Termios2 {
    var c_iflag: UInt32 = 0
    var c_oflag: UInt32 = 0
    var c_cflag: UInt32 = 0
    var c_lflag: UInt32 = 0
    var c_line: UInt8 = 0
    var c_cc: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
               UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var c_ispeed: UInt32 = 0
    var c_ospeed: UInt32 = 0

    static let cbaud: UInt32 = 0o010017
    static let bother: UInt32 = 0o010000
    /// The input baud rate bits are shifted by 16 (IBSHIFT).
    static let inputShift: UInt32 = 16
}
#endif
