// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ESPTargets
@testable import ESPSecure

private func image(_ count: Int) -> Data { Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) }) }

@Suite("Secure Boot v2")
struct SecureBootV2Tests {
    @Test(arguments: [SecureBootV2.Scheme.rsa3072, .ecdsa256, .ecdsa384])
    func signsAndVerifies(scheme: SecureBootV2.Scheme) throws {
        let key = try SecureBootV2.SigningKey.generate(scheme)
        let signed = try SecureBootV2.sign(image(10_000), with: [key])
        #expect(signed.count == 12_288 + 4_096)
        #expect(signed[10_000..<12_288].allSatisfy { $0 == 0xFF })
        try SecureBootV2.verify(signed, publicKey: key.publicKey)
        let blocks = try SecureBootV2.signatureBlocks(in: signed)
        #expect(blocks.count == 1 && blocks[0].scheme == scheme && blocks[0].publicKey == key.publicKey)

        // One byte changed in the image: no signature verifies any more.
        var tampered = signed
        tampered[100] ^= 1
        #expect(throws: SecureBootError.signatureInvalid) { try SecureBootV2.verify(tampered, publicKey: key.publicKey) }
        // Another key does not verify.
        let other = try SecureBootV2.SigningKey.generate(scheme)
        #expect(throws: SecureBootError.signatureInvalid) { try SecureBootV2.verify(signed, publicKey: other.publicKey) }
    }

    @Test func pemRoundTrips() throws {
        for scheme in [SecureBootV2.Scheme.rsa3072, .ecdsa256, .ecdsa384] {
            let key = try SecureBootV2.SigningKey.generate(scheme)
            let reloaded = try SecureBootV2.SigningKey(pemRepresentation: key.pemRepresentation)
            #expect(reloaded.publicKey == key.publicKey)
            let publicKey = try SecureBootV2.PublicKey(pemRepresentation: key.publicKey.pemRepresentation)
            #expect(publicKey.digest == key.publicKey.digest)
            #expect(publicKey.digest.count == 32)
        }
        #expect(throws: SecureBootError.self) { try SecureBootV2.SigningKey(pemRepresentation: "-----BEGIN NOTHING-----") }
        #expect(throws: SecureBootError.schemeNotSupported(.ecdsa192, chip: nil)) { try SecureBootV2.SigningKey.generate(.ecdsa192) }
    }

    @Test func appendsUpToThreeSignatures() async throws {
        let keys = try (0..<3).map { _ in try SecureBootV2.SigningKey.generate(.ecdsa256) }
        let once = try await SecureBootV2.sign(image(5_000), with: [keys[0]])
        let thrice = try await SecureBootV2.sign(once, with: [keys[1], keys[2]], appendingTo: true)
        #expect(thrice.count == once.count)
        #expect(try SecureBootV2.signatureBlocks(in: thrice).count == 3)
        for key in keys { try SecureBootV2.verify(thrice, publicKey: key.publicKey) }
        let extra = try SecureBootV2.SigningKey.generate(.ecdsa256)
        await #expect(throws: SecureBootError.tooManySignatures) {
            try await SecureBootV2.sign(thrice, with: [extra], appendingTo: true)
        }
    }

    @Test func attachesARemoteSignature() async throws {
        let key = try SecureBootV2.SigningKey.generate(.rsa3072)
        let body = image(8_192)
        let signature = try await key.sign(imageDigest: SecureBootV2.Scheme.rsa3072.imageDigest(body))
        let signed = try SecureBootV2.attach(signature: signature, publicKey: key.publicKey, to: body)
        try SecureBootV2.verify(signed, publicKey: key.publicKey)
        var bad = signature
        bad[0] ^= 1
        #expect(throws: SecureBootError.signatureInvalid) { try SecureBootV2.attach(signature: bad, publicKey: key.publicKey, to: body) }
    }

    @Test func unsignedImagesHaveNoBlock() {
        #expect(throws: SecureBootError.noSignatureBlock) { try SecureBootV2.signatureBlocks(in: image(8_192)) }
    }

    @Test func montgomeryParameters() {
        // n = 0xC5 (197): R = 2⁸, R² mod n = 65536 mod 197 = 132; −197⁻¹ mod 2³² = 0x2E8BA2E9·…
        let n = BigUInt(bigEndian: Data([0xC5]))
        #expect(BigUInt.powerOfTwo(16, modulo: n).littleEndian(count: 1) == Data([UInt8(65_536 % 197)]))
        #expect(n.negativeInverseModWord &* 197 == UInt32.max)       // n · (−n⁻¹) ≡ −1
    }
}

@Suite("Flash encryption")
struct FlashEncryptionTests {
    @Test(arguments: [FlashEncryption.Scheme.xtsAES128, .xtsAES256])
    func roundTrips(scheme: FlashEncryption.Scheme) throws {
        let key = FlashEncryption.generateKey(for: scheme)
        #expect(key.count == scheme.keyLength)
        let plain = image(1_040)
        let encrypted = try FlashEncryption.encrypt(plain, at: 0x1_0010, key: key, scheme: scheme)
        #expect(encrypted != plain)
        #expect(try FlashEncryption.decrypt(encrypted, at: 0x1_0010, key: key, scheme: scheme) == plain)
        // Encryption depends on the address.
        #expect(try FlashEncryption.encrypt(plain, at: 0x2_0010, key: key, scheme: scheme) != encrypted)
    }

    @Test func esp32SchemeRoundTripsAndDependsOnConfig() throws {
        let key = FlashEncryption.generateKey(for: .esp32())
        let plain = image(256)
        let encrypted = try FlashEncryption.encrypt(plain, at: 0x1_2340, key: key, scheme: .esp32())
        #expect(try FlashEncryption.decrypt(encrypted, at: 0x1_2340, key: key, scheme: .esp32()) == plain)
        #expect(try FlashEncryption.encrypt(plain, at: 0x1_2340, key: key, scheme: .esp32(cryptConfig: 0)) != encrypted)
        #expect(FlashEncryption.esp32TweakPattern.count == 256)
        #expect(FlashEncryption.tweakedKey(key, address: 0x1_2340, config: 0) == key)
        #expect(throws: FlashEncryptionError.self) { try FlashEncryption.encrypt(image(16), at: 0, key: key, scheme: .esp32()) }
    }

    @Test func checksArguments() {
        let key = FlashEncryption.generateKey(for: .xtsAES128)
        #expect(throws: FlashEncryptionError.self) { try FlashEncryption.encrypt(image(20), at: 0, key: key, scheme: .xtsAES128) }
        #expect(throws: FlashEncryptionError.self) { try FlashEncryption.encrypt(image(32), at: 8, key: key, scheme: .xtsAES128) }
        #expect(throws: FlashEncryptionError.self) { try FlashEncryption.encrypt(image(32), at: 0, key: key, scheme: .xtsAES256) }
        #expect(FlashEncryption.Scheme.default(for: .esp8266) == nil)
        #expect(FlashEncryption.Scheme.default(for: .esp32s3) == .xtsAES128)
    }
}

@Suite("Secure Boot v1")
struct SecureBootV1Tests {
    private let pem: String

    init() throws {
        pem = try SecureBootV2.SigningKey.generate(.ecdsa256).pemRepresentation
    }

    @Test func signsAndVerifies() throws {
        let data = image(1000)
        let signed = try SecureBootV1.sign(data, privateKeyPEM: pem)
        #expect(signed.count == data.count + 68)
        #expect(signed.prefix(data.count) == data)
        try SecureBootV1.verify(signed, publicKeyPEM: pem)

        var tampered = signed
        tampered[10] ^= 1
        #expect(throws: SecureBootError.signatureInvalid) { try SecureBootV1.verify(tampered, publicKeyPEM: pem) }
        let other = try SecureBootV2.SigningKey.generate(.ecdsa256).pemRepresentation
        #expect(throws: SecureBootError.signatureInvalid) { try SecureBootV1.verify(signed, publicKeyPEM: other) }
    }

    @Test func digestBlockLayout() throws {
        let iv = Data(repeating: 0x11, count: 128), key = Data(repeating: 0x22, count: 32)
        let bootloader = image(1000)
        let out = try SecureBootV1.digest(bootloader: bootloader, key: key, iv: iv)
        #expect(out.count == 0x1000 + 1024)                     // bootloader padded to 128 bytes
        #expect(out.prefix(128) == iv)
        #expect(out[192..<0x1000].allSatisfy { $0 == 0xFF })
        #expect(out[0x1000..<0x1000 + 1000] == bootloader)
        #expect(out.suffix(24).allSatisfy { $0 == 0xFF })
        // The digest depends on the key.
        let other = try SecureBootV1.digest(bootloader: bootloader, key: Data(repeating: 0x23, count: 32), iv: iv)
        #expect(other[128..<192] != out[128..<192])
    }

    @Test func refusesBadInputs() throws {
        #expect(throws: SecureBootError.self) { try SecureBootV1.digest(bootloader: image(16), key: Data(count: 24)) }
        #expect(throws: SecureBootError.self) { try SecureBootV1.digest(bootloader: image(16), key: Data(count: 32), iv: Data(count: 16)) }
        #expect(throws: SecureBootError.self) { try SecureBootV1.derivedKey(fromPrivateKeyPEM: pem, bitLength: 128) }
        let rsa = try SecureBootV2.SigningKey.generate(.rsa3072).pemRepresentation
        #expect(throws: SecureBootError.self) { try SecureBootV1.sign(image(16), privateKeyPEM: rsa) }
        #expect(try SecureBootV1.derivedKey(fromPrivateKeyPEM: pem, bitLength: 192).count == 24)
    }
}
