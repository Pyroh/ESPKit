// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import ESPSecure

// Interoperability with espsecure, used as a black box. Skipped unless
// ESPKIT_SECURE_REFERENCES names a folder holding:
//   key-<scheme>.pem, digest-<scheme>.bin, signed-<scheme>.bin (espsecure generate-signing-key,
//   digest-sbv2-public-key, sign-data); plain.bin, xts128.key, xts256.key and
//   enc-<key>-<address>.bin (espsecure encrypt-flash-data --aes-xts).
// Secure Boot v1: key-v1.pem, v1-derived256.bin, v1-derived192.bin (digest-private-key),
//   v1-sbkey.bin, v1-iv.bin, v1-input.bin, v1-digest.bin (digest-secure-bootloader), v1-signed.bin.
// ESPKIT_ESPSECURE (the espsecure command) also enables espsecure's verification of
// images signed by ESPKit: this is the phase 3 milestone.

private let folder = ProcessInfo.processInfo.environment["ESPKIT_SECURE_REFERENCES"].map { URL(fileURLWithPath: $0) }
private let espsecure = ProcessInfo.processInfo.environment["ESPKIT_ESPSECURE"]
private let schemes = ["rsa3072", "ecdsa256", "ecdsa384"]

private func file(_ name: String) throws -> Data { try Data(contentsOf: try #require(folder).appendingPathComponent(name)) }

@Suite("espsecure interoperability", .enabled(if: folder != nil))
struct EspsecureInteropTests {
    @Test(arguments: schemes)
    func publicKeyDigestMatches(scheme: String) throws {
        let key = try SecureBootV2.SigningKey(pemRepresentation: String(decoding: file("key-\(scheme).pem"), as: UTF8.self))
        #expect(key.publicKey.digest == (try file("digest-\(scheme).bin")))
    }

    @Test(arguments: schemes)
    func verifiesEspsecureSignatures(scheme: String) throws {
        let key = try SecureBootV2.SigningKey(pemRepresentation: String(decoding: file("key-\(scheme).pem"), as: UTF8.self))
        try SecureBootV2.verify(file("signed-\(scheme).bin"), publicKey: key.publicKey)
    }

    @Test(arguments: schemes)
    func espsecureAcceptsESPKitSignatures(scheme: String) throws {
        let pem = String(decoding: try file("key-\(scheme).pem"), as: UTF8.self)
        let key = try SecureBootV2.SigningKey(pemRepresentation: pem)
        // Same image as the one espsecure signed: the digest must match.
        let reference = try SecureBootV2.signatureBlocks(in: file("signed-\(scheme).bin"))[0]
        let unsigned = try file("signed-\(scheme).bin").dropLast(4096)
        let signed = try SecureBootV2.sign(Data(unsigned), with: [key])
        #expect(try SecureBootV2.signatureBlocks(in: signed)[0].imageDigest == reference.imageDigest)
        #expect(signed.prefix(signed.count - 4096) == unsigned)

        guard espsecure != nil else { return }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("espkit-signed-\(scheme).bin")
        try signed.write(to: output)
        let log = try run(["verify-signature", "--version", "2",
                           "--keyfile", try #require(folder).appendingPathComponent("key-\(scheme).pem").path, output.path])
        #expect(log.contains("verification successful"), "espsecure: \(log)")
    }

    @Test func secureBootV1MatchesEspsecure() throws {
        guard FileManager.default.fileExists(atPath: try #require(folder).appendingPathComponent("key-v1.pem").path) else { return }
        let pem = String(decoding: try file("key-v1.pem"), as: UTF8.self)
        #expect(try SecureBootV1.derivedKey(fromPrivateKeyPEM: pem) == (try file("v1-derived256.bin")))
        #expect(try SecureBootV1.derivedKey(fromPrivateKeyPEM: pem, bitLength: 192) == (try file("v1-derived192.bin")))
        let digest = try SecureBootV1.digest(bootloader: file("v1-input.bin"), key: file("v1-sbkey.bin"), iv: file("v1-iv.bin"))
        #expect(digest == (try file("v1-digest.bin")))
        try SecureBootV1.verify(file("v1-signed.bin"), publicKeyPEM: pem)

        let signed = try SecureBootV1.sign(file("v1-input.bin"), privateKeyPEM: pem)
        #expect(signed.count == (try file("v1-signed.bin")).count)
        guard espsecure != nil else { return }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("espkit-signed-v1.bin")
        try signed.write(to: output)
        let log = try run(["verify-signature", "--version", "1",
                           "--keyfile", try #require(folder).appendingPathComponent("key-v1.pem").path, output.path])
        #expect(log.contains("Signature is valid"), "espsecure: \(log)")
    }

    @Test(.enabled(if: espsecure != nil), arguments: [SecureBootV2.Scheme.rsa3072, .ecdsa256, .ecdsa384])
    func espsecureReadsESPKitKeys(scheme: SecureBootV2.Scheme) throws {
        let key = try SecureBootV2.SigningKey.generate(scheme)
        let directory = FileManager.default.temporaryDirectory
        let pem = directory.appendingPathComponent("espkit-key-\(scheme).pem")
        let digest = directory.appendingPathComponent("espkit-digest-\(scheme).bin")
        let signed = directory.appendingPathComponent("espkit-own-\(scheme).bin")
        try Data(key.pemRepresentation.utf8).write(to: pem)
        try SecureBootV2.sign(Data(repeating: 0x5A, count: 12_345), with: [key]).write(to: signed)
        let verify = try run(["verify-signature", "--version", "2", "--keyfile", pem.path, signed.path])
        #expect(verify.contains("verification successful"), "\(verify)")
        _ = try run(["digest-sbv2-public-key", "--keyfile", pem.path, "--output", digest.path])
        #expect(try Data(contentsOf: digest) == key.publicKey.digest)
    }

    @Test(arguments: [("xts128", FlashEncryption.Scheme.xtsAES128), ("xts256", .xtsAES256)])
    func encryptsLikeEspsecure(name: String, scheme: FlashEncryption.Scheme) throws {
        let plain = try file("plain.bin")
        let key = try file("\(name).key")
        for address: UInt32 in [0x0, 0x1_0000, 0x1080] {
            let expected = try file("enc-\(name)-0x\(String(address, radix: 16)).bin")
            #expect(try FlashEncryption.encrypt(plain, at: address, key: key, scheme: scheme) == expected, "0x\(String(address, radix: 16))")
            #expect(try FlashEncryption.decrypt(expected, at: address, key: key, scheme: scheme) == plain)
        }
    }

    /// e32-<config>-<address>.bin: `espsecure encrypt-flash-data --flash-crypt-conf <config>` of p256.bin.
    @Test func encryptsLikeEspsecureOnESP32() throws {
        let key = try file("esp32.key")
        let plain = try file("p256.bin")
        for config: UInt8 in [0x0, 0x1, 0x2, 0x4, 0x8, 0xF] {
            for address: UInt32 in [0x0, 0x1000, 0x1_2340, 0xF_EDC0] {
                let name = "e32-0x\(String(config, radix: 16))-0x\(String(address, radix: 16)).bin"
                let expected = try file(name)
                #expect(try FlashEncryption.encrypt(plain, at: address, key: key, scheme: .esp32(cryptConfig: config)) == expected, "\(name)")
                #expect(try FlashEncryption.decrypt(expected, at: address, key: key, scheme: .esp32(cryptConfig: config)) == plain)
            }
        }
    }

    @Test func handlesPartialUnitsLikeEspsecure() throws {
        let key = try file("xts128.key")
        for (input, address) in [("plain.bin", UInt32(0x1010)), ("plain208.bin", 0x1010), ("plain208.bin", 0x1000)] {
            let expected = try file("enc-mis-0x\(String(address, radix: 16))-\(input)")
            #expect(try FlashEncryption.encrypt(file(input), at: address, key: key, scheme: .xtsAES128) == expected, "\(input) at 0x\(String(address, radix: 16))")
        }
    }
}

/// Runs espsecure and returns its output; fails if the command fails.
private func run(_ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [try #require(espsecure)] + arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let log = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, "espsecure \(arguments.first ?? ""): \(log)")
    return log
}
