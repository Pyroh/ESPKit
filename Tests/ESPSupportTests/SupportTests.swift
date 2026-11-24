// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import ESPSupport

private func hexString(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

@Suite("MD5")
struct MD5Tests {
    // RFC 1321 test vectors, appendix A.5.
    @Test(arguments: [
        ("", "d41d8cd98f00b204e9800998ecf8427e"),
        ("a", "0cc175b9c0f1b6a831c399e269772661"),
        ("abc", "900150983cd24fb0d6963f7d28e17f72"),
        ("message digest", "f96b697d7cb7938d525a2f31aaf161d0"),
        ("abcdefghijklmnopqrstuvwxyz", "c3fcd3d76192e4007dfb496cca67e13b"),
        ("12345678901234567890123456789012345678901234567890123456789012345678901234567890",
         "57edf4a22be3c955ac49da2e2107b67a"),
    ])
    func rfcVectors(input: String, expected: String) {
        #expect(hexString(MD5.hash(Data(input.utf8))) == expected)
    }

    @Test func incrementalMatchesOneShot() {
        let data = Data((0..<10_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        var md5 = MD5()
        for chunk in stride(from: 0, to: data.count, by: 777) {
            md5.update(data.subdata(in: chunk..<min(chunk + 777, data.count)))
        }
        #expect(md5.finalize() == MD5.hash(data))
    }
}

@Suite("SHA-256")
struct SHA256Tests {
    @Test(arguments: [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
    ])
    func fipsVectors(input: String, expected: String) {
        #expect(hexString(SHA256.hash(Data(input.utf8))) == expected)
    }

    @Test func millionA() {
        #expect(hexString(SHA256.hash(Data(repeating: 0x61, count: 1_000_000)))
                == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
}

@Suite("zlib")
struct ZlibTests {
    @Test func roundTrip() throws {
        let data = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 % 251) })
        let compressed = try Zlib.compress(data)
        #expect(compressed.count < data.count / 10)
        #expect(compressed.first == 0x78)                 // zlib header
        #expect(try Zlib.decompress(compressed) == data)
    }

    @Test func inflaterAcceptsArbitraryChunks() throws {
        let data = Data((0..<100_000).map { _ in UInt8.random(in: 0...255) })
        let compressed = try Zlib.compress(data)
        let inflater = try Zlib.Inflater()
        var out = Data()
        for start in stride(from: 0, to: compressed.count, by: 1_000) {
            out.append(try inflater.feed(compressed.subdata(in: start..<min(start + 1_000, compressed.count))))
        }
        #expect(inflater.isFinished)
        #expect(out == data)
    }

    @Test func truncatedStreamIsRejected() throws {
        let compressed = try Zlib.compress(Data(repeating: 7, count: 10_000))
        #expect(throws: Zlib.Failure.self) { try Zlib.decompress(compressed.prefix(compressed.count - 4)) }
    }
}
