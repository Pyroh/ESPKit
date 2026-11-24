// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import ESPTransport
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Pseudo-terminal : le côté esclave joue le port série, le maître joue la puce.
private struct PseudoTerminal {
    let master: Int32
    let slavePath: String

    init() throws {
        #if os(Linux)
        // La glibc masque posix_openpt et ptsname sans _XOPEN_SOURCE : on passe par /dev/ptmx.
        master = open("/dev/ptmx", O_RDWR | O_NOCTTY)
        var unlock: Int32 = 0
        var number: UInt32 = 0
        guard master >= 0,
              ioctl(master, 0x4004_5431, &unlock) == 0,            // TIOCSPTLCK
              ioctl(master, 0x8004_5430, &number) == 0 else {       // TIOCGPTN
            throw TransportError.ioFailed(errno: errno)
        }
        slavePath = "/dev/pts/\(number)"
        #else
        master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0, let name = ptsname(master) else {
            throw TransportError.ioFailed(errno: errno)
        }
        slavePath = String(cString: name)
        #endif
    }

    func close() { _ = Foundation.close(master) }
}

@Suite("SerialPort sur pseudo-terminal")
struct SerialPortTests {
    #if os(Linux)
    @Test func setsArbitraryBaudRateWithTermios2() throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        let fd = open(pty.slavePath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        #expect(fd >= 0)
        defer { _ = Glibc.close(fd) }
        try SerialPort.applyBaudRate(1_234_567, fd: fd)
        #expect(try SerialPort.currentBaudRate(fd: fd) == 1_234_567)
        try SerialPort.applyBaudRate(460_800, fd: fd)
        #expect(try SerialPort.currentBaudRate(fd: fd) == 460_800)
    }

    @Test func exchangesBytesThroughTheSlaveSide() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        let port = SerialPort(path: pty.slavePath)
        try await port.open()
        try await port.setBaudRate(921_600)
        try await port.write(Data("ping".utf8))
        var buffer = [UInt8](repeating: 0, count: 16)
        var pollDescriptor = pollfd(fd: pty.master, events: Int16(POLLIN), revents: 0)
        #expect(poll(&pollDescriptor, 1, 1_000) == 1)
        let count = read(pty.master, &buffer, buffer.count)
        #expect(Data(buffer.prefix(max(count, 0))) == Data("ping".utf8))

        _ = "pong".withCString { write(pty.master, $0, 4) }
        let reply = try await port.read(maxCount: 16, timeout: .seconds(1))
        #expect(reply == Data("pong".utf8))
        await port.close()
    }
    #endif

    @Test func reportsMissingDevice() async {
        let port = SerialPort(path: "/dev/espkit-absent")
        await #expect(throws: TransportError.self) { try await port.open() }
    }
}
