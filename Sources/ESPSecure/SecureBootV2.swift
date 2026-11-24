// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Crypto
import _CryptoExtras
import enum ESPSupport.Zlib

/// Secure Boot v2: image signing and the public key digests to burn into eFuses.
///
/// Format (ESP-IDF C headers): the image is padded with 0xFF to 4 KiB, then followed by a
/// 4 KiB sector holding 1 to 3 blocks of 1,216 bytes, the rest 0xFF. Each block carries
/// the image digest, the public key and the signature, little-endian for the hardware,
/// then a CRC-32 of its first 1,196 bytes.
public enum SecureBootV2 {
    /// Signature algorithm.
    public enum Scheme: Hashable, Sendable, CustomStringConvertible {
        /// RSA-3072 with PSS padding, SHA-256 (every Secure Boot v2 chip but the C2).
        case rsa3072
        /// ECDSA P-192 with SHA-256 (ESP32-C2). Not supported yet.
        case ecdsa192
        /// ECDSA P-256 with SHA-256.
        case ecdsa256
        /// ECDSA P-384 with SHA-384.
        case ecdsa384

        /// For example "ECDSA P-256".
        public var description: String {
            switch self {
            case .rsa3072: "RSA-3072"
            case .ecdsa192: "ECDSA P-192"
            case .ecdsa256: "ECDSA P-256"
            case .ecdsa384: "ECDSA P-384"
            }
        }

        /// SHA-384 for P-384, SHA-256 otherwise.
        func imageDigest(_ data: Data) -> Data {
            self == .ecdsa384 ? Data(Crypto.SHA384.hash(data: data)) : Data(Crypto.SHA256.hash(data: data))
        }

        var coordinateLength: Int { self == .ecdsa384 ? 48 : 32 }
    }

    // MARK: Keys

    /// A private signing key held in memory.
    public struct SigningKey: Sendable {
        enum Backing: Sendable {
            case rsa(signing: _RSA.Signing.PrivateKey, raw: _RSA.BlindSigning.PrivateKey<Crypto.SHA384>)
            case p256(P256.Signing.PrivateKey)
            case p384(P384.Signing.PrivateKey)
        }

        let backing: Backing
        /// The matching public key.
        public let publicKey: PublicKey

        /// The key's algorithm.
        public var scheme: Scheme { publicKey.scheme }

        /// A new random key, like `espsecure generate-signing-key --version 2`.
        /// - Throws: `SecureBootError.schemeNotSupported` for P-192 (not supported yet).
        public static func generate(_ scheme: Scheme) throws -> SigningKey {
            switch scheme {
            case .rsa3072:
                let key = try _RSA.Signing.PrivateKey(keySize: .bits3072)
                return try SigningKey(pemRepresentation: key.pemRepresentation)
            case .ecdsa256: return SigningKey(.p256(P256.Signing.PrivateKey()))
            case .ecdsa384: return SigningKey(.p384(P384.Signing.PrivateKey()))
            case .ecdsa192: throw SecureBootError.schemeNotSupported(.ecdsa192, chip: nil)
            }
        }

        /// PEM key: RSA-3072 (PKCS#1 or PKCS#8), ECDSA P-256 or P-384 (SEC1 or PKCS#8).
        /// - Throws: `SecureBootError.invalidKey`.
        public init(pemRepresentation pem: String) throws {
            if let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) {
                self.init(.p256(key))
            } else if let key = try? P384.Signing.PrivateKey(pemRepresentation: pem) {
                self.init(.p384(key))
            } else if let key = try? _RSA.Signing.PrivateKey(pemRepresentation: pem) {
                guard key.keySizeInBits == 3072 else {
                    throw SecureBootError.invalidKey("\(key.keySizeInBits)-bit RSA; Secure Boot v2 needs 3072 bits")
                }
                let raw = try _RSA.BlindSigning.PrivateKey<Crypto.SHA384>(pemRepresentation: pem)
                self.init(.rsa(signing: key, raw: raw))
            } else {
                throw SecureBootError.invalidKey("unreadable PEM, or a curve other than P-256 and P-384")
            }
        }

        private init(_ backing: Backing) {
            self.backing = backing
            switch backing {
            case .rsa(let key, _): publicKey = PublicKey(rsa: key.publicKey)
            case .p256(let key): publicKey = PublicKey(.p256(key.publicKey))
            case .p384(let key): publicKey = PublicKey(.p384(key.publicKey))
            }
        }

        /// The private key in PEM (PKCS#8 for RSA, SEC1 for ECDSA), readable by espsecure.
        public var pemRepresentation: String {
            switch backing {
            case .rsa(let key, _): key.pemRepresentation
            case .p256(let key): key.pemRepresentation
            case .p384(let key): key.pemRepresentation
            }
        }

        /// Standard (big-endian) signature of the image digest.
        func signature(forDigest digest: Data) throws -> Data {
            switch backing {
            case .rsa(_, let raw):
                // RSA-PSS with SHA-256, MGF1-SHA-256 and a 32-byte salt: the EMSA-PSS encoding
                // (RFC 8017, § 9.1.1) is done here, then the raw RSA operation by swift-crypto.
                var salt = Data(count: 32)
                var generator = SystemRandomNumberGenerator()
                for index in salt.indices { salt[index] = generator.next() }
                let encoded = PSS.encode(digest: digest, salt: salt, modulusBits: 3072)
                return try raw.blindSignature(for: encoded).rawRepresentation
            case .p256(let key):
                return try key.signature(for: RawDigest(bytes: digest, length: 32)).rawRepresentation
            case .p384(let key):
                return try key.signature(for: RawDigest(bytes: digest, length: 48)).rawRepresentation
            }
        }
    }

    /// A public verification key.
    public struct PublicKey: Hashable, Sendable {
        enum Backing: Sendable {
            case rsa(_RSA.Signing.PublicKey, modulus: Data, exponent: UInt32)
            case p256(P256.Signing.PublicKey)
            case p384(P384.Signing.PublicKey)
        }

        let backing: Backing

        /// Reads a PEM public key: RSA-3072, ECDSA P-256 or P-384.
        /// - Throws: `SecureBootError.invalidKey`.
        public init(pemRepresentation pem: String) throws {
            if let key = try? P256.Signing.PublicKey(pemRepresentation: pem) {
                self.init(.p256(key))
            } else if let key = try? P384.Signing.PublicKey(pemRepresentation: pem) {
                self.init(.p384(key))
            } else if let key = try? _RSA.Signing.PublicKey(pemRepresentation: pem), key.keySizeInBits == 3072 {
                self.init(rsa: key)
            } else {
                throw SecureBootError.invalidKey("unreadable PEM public key, or neither RSA-3072, P-256 nor P-384")
            }
        }

        init(_ backing: Backing) { self.backing = backing }

        init(rsa key: _RSA.Signing.PublicKey) {
            let primitives = try? key.getKeyPrimitives()
            let modulus = primitives?.modulus ?? Data()
            let exponent = (primitives?.publicExponent ?? Data()).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            self.backing = .rsa(key, modulus: modulus, exponent: exponent)
        }

        /// The key's algorithm.
        public var scheme: Scheme {
            switch backing {
            case .rsa: .rsa3072
            case .p256: .ecdsa256
            case .p384: .ecdsa384
            }
        }

        /// The public key in PEM (SubjectPublicKeyInfo).
        public var pemRepresentation: String {
            switch backing {
            case .rsa(let key, _, _): key.pemRepresentation
            case .p256(let key): key.pemRepresentation
            case .p384(let key): key.pemRepresentation
            }
        }

        /// SHA-256 of the key in the format the ROM expects, to burn into `SECURE_BOOT_DIGESTn`.
        public var digest: Data { Data(Crypto.SHA256.hash(data: blockEncoding)) }

        /// The key as it appears in the signature block.
        /// RSA: n (LE), e, R² mod n (LE), −n⁻¹ mod 2³²; ECDSA: curve ID, then x and y (LE).
        var blockEncoding: Data {
            switch backing {
            case .rsa(_, let modulus, let exponent):
                let n = BigUInt(bigEndian: modulus)
                var out = n.littleEndian(count: 384)
                out.appendLE32(exponent)
                out.append(BigUInt.powerOfTwo(2 * 3072, modulo: n).littleEndian(count: 384))
                out.appendLE32(n.negativeInverseModWord)
                return out
            case .p256(let key): return Self.curvePoint(curve: 2, x963: key.x963Representation, length: 32)
            case .p384(let key): return Self.curvePoint(curve: 3, x963: key.x963Representation, length: 48)
            }
        }

        private static func curvePoint(curve: UInt8, x963: Data, length: Int) -> Data {
            let point = Data(x963.dropFirst())                // 04 ‖ x ‖ y, en big-endian
            return Data([curve]) + Data(point.prefix(length).reversed()) + Data(point.suffix(length).reversed())
        }

        /// Reads the key back from a signature block.
        init(blockEncoding data: Data, scheme: Scheme) throws {
            let bytes = Data(data)
            switch scheme {
            case .rsa3072:
                let modulus = Data(bytes.prefix(384).reversed())
                let exponent = bytes.subdata(in: 384..<388).reversed().reduce(Data()) { $0 + [$1] }
                self.init(rsa: try _RSA.Signing.PublicKey(n: modulus, e: exponent))
            case .ecdsa256, .ecdsa384:
                let length = scheme.coordinateLength
                let x = Data(bytes.subdata(in: 1..<1 + length).reversed())
                let y = Data(bytes.subdata(in: 1 + length..<1 + 2 * length).reversed())
                let x963 = Data([4]) + x + y
                self.init(scheme == .ecdsa256 ? .p256(try P256.Signing.PublicKey(x963Representation: x963))
                                              : .p384(try P384.Signing.PublicKey(x963Representation: x963)))
            case .ecdsa192:
                throw SecureBootError.schemeNotSupported(.ecdsa192, chip: nil)
            }
        }

        /// Two keys are equal when their signature-block encodings are.
        public static func == (lhs: PublicKey, rhs: PublicKey) -> Bool { lhs.blockEncoding == rhs.blockEncoding }
        /// Hashes the signature-block encoding.
        public func hash(into hasher: inout Hasher) { hasher.combine(blockEncoding) }

        /// Verifies a standard (big-endian) signature over the image.
        func isValidSignature(_ signature: Data, forImage image: Data) -> Bool {
            switch backing {
            case .rsa(let key, _, _):
                return key.isValidSignature(_RSA.Signing.RSASignature(rawRepresentation: signature),
                                            for: Crypto.SHA256.hash(data: image), padding: .PSS)
            case .p256(let key):
                guard let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else { return false }
                return key.isValidSignature(parsed, for: Crypto.SHA256.hash(data: image))
            case .p384(let key):
                guard let parsed = try? P384.Signing.ECDSASignature(rawRepresentation: signature) else { return false }
                return key.isValidSignature(parsed, for: Crypto.SHA384.hash(data: image))
            }
        }
    }

    /// Abstract signer: local key, HSM, remote service.
    public protocol Signer: Sendable {
        /// The public key matching the signatures this signer produces.
        var publicKey: PublicKey { get }
        /// Signs the image digest (SHA-256, or SHA-384 for P-384) and returns the standard
        /// big-endian signature: RSA-PSS (MGF1-SHA-256, 32-byte salt) over 384 bytes,
        /// or ECDSA r ‖ s.
        func sign(imageDigest: Data) async throws -> Data
    }

    /// Signature block read from an image.
    public struct SignatureBlock: Hashable, Sendable {
        /// Algorithm of the block.
        public var scheme: Scheme
        /// Image digest stored in the block (SHA-256, or SHA-384 for P-384).
        public var imageDigest: Data
        /// Public key stored in the block.
        public var publicKey: PublicKey
        /// Standard signature, big-endian.
        public var signature: Data
    }

    // MARK: Signature

    /// Appends one signature block per signer (at most 3, existing ones included).
    /// The image is padded to 4 KiB if needed. For the signature to land on an MMU
    /// boundary, build the image with `ImageOptions.securePadding = .v2`.
    /// - Parameters:
    ///   - image: the image to sign, signed already or not.
    ///   - signers: one block is added per signer, in order.
    ///   - existing: keep the blocks of the signature sector already present.
    /// - Throws: `SecureBootError`, and the signers' errors.
    public static func sign(_ image: Data, with signers: [any Signer],
                            appendingTo existing: Bool = false) async throws -> Data {
        var (body, blocks) = try split(image, keepingSignatures: existing)
        guard !signers.isEmpty else { throw SecureBootError.noSignatureBlock }
        guard blocks.count + signers.count <= 3 else { throw SecureBootError.tooManySignatures }
        for signer in signers {
            let digest = signer.publicKey.scheme.imageDigest(body)
            let signature = try await signer.sign(imageDigest: digest)
            blocks.append(try makeBlock(digest: digest, publicKey: signer.publicKey, signature: signature, image: body))
        }
        return assemble(body, blocks)
    }

    /// Synchronous version for local keys.
    public static func sign(_ image: Data, with keys: [SigningKey], appendingTo existing: Bool = false) throws -> Data {
        var (body, blocks) = try split(image, keepingSignatures: existing)
        guard !keys.isEmpty else { throw SecureBootError.noSignatureBlock }
        guard blocks.count + keys.count <= 3 else { throw SecureBootError.tooManySignatures }
        for key in keys {
            let digest = key.scheme.imageDigest(body)
            blocks.append(try makeBlock(digest: digest, publicKey: key.publicKey,
                                        signature: try key.signature(forDigest: digest), image: body))
        }
        return assemble(body, blocks)
    }

    /// Inserts a signature computed elsewhere (remote signing), after the existing blocks.
    /// - Throws: `SecureBootError.signatureInvalid` if it does not verify.
    public static func attach(signature: Data, publicKey: PublicKey, to image: Data) throws -> Data {
        var (body, blocks) = try split(image, keepingSignatures: true)
        guard blocks.count < 3 else { throw SecureBootError.tooManySignatures }
        let digest = publicKey.scheme.imageDigest(body)
        blocks.append(try makeBlock(digest: digest, publicKey: publicKey, signature: signature, image: body))
        return assemble(body, blocks)
    }

    /// Blocks of the final signature sector (valid CRC).
    /// - Throws: `SecureBootError.noSignatureBlock`.
    public static func signatureBlocks(in image: Data) throws -> [SignatureBlock] {
        let blocks = try parseSector(image)
        guard !blocks.isEmpty else { throw SecureBootError.noSignatureBlock }
        return blocks
    }

    /// Throws `SecureBootError.signatureInvalid` if no block verifies with `publicKey`.
    public static func verify(_ image: Data, publicKey: PublicKey) throws {
        let blocks = try signatureBlocks(in: image)
        let body = Data(image.prefix(image.count - 4096))
        for block in blocks where block.publicKey == publicKey {
            if block.imageDigest == block.scheme.imageDigest(body),
               publicKey.isValidSignature(block.signature, forImage: body) {
                return
            }
        }
        throw SecureBootError.signatureInvalid
    }

    // MARK: Format

    static let blockLength = 1216
    static let crcCoverage = 1196
    static let sectorLength = 4096

    /// Image to sign (padded to 4 KiB) and the existing blocks.
    private static func split(_ image: Data, keepingSignatures: Bool) throws -> (Data, [Data]) {
        var body = Data(image)
        var blocks: [Data] = []
        if keepingSignatures, let parsed = try? parseSector(body), !parsed.isEmpty {
            let sector = body.suffix(sectorLength)
            blocks = (0..<parsed.count).map { Data(sector.dropFirst($0 * blockLength).prefix(blockLength)) }
            body = Data(body.prefix(body.count - sectorLength))
            // Every block signs the same image.
            for block in parsed where block.imageDigest != block.scheme.imageDigest(body) {
                throw SecureBootError.signatureInvalid
            }
        }
        if body.count % sectorLength != 0 {
            body.append(Data(repeating: 0xFF, count: sectorLength - body.count % sectorLength))
        }
        return (body, blocks)
    }

    private static func assemble(_ body: Data, _ blocks: [Data]) -> Data {
        var sector = blocks.reduce(Data(), +)
        sector.append(Data(repeating: 0xFF, count: sectorLength - sector.count))
        return body + sector
    }

    /// 1,216-byte block; the signature is verified before it is stored.
    private static func makeBlock(digest: Data, publicKey: PublicKey, signature: Data, image: Data) throws -> Data {
        let scheme = publicKey.scheme
        var block: Data
        switch scheme {
        case .rsa3072:
            guard signature.count == 384 else { throw SecureBootError.signatureInvalid }
            block = Data([0xE7, 0x02, 0x00, 0x00]) + digest + publicKey.blockEncoding + Data(signature.reversed())
        case .ecdsa256, .ecdsa384:
            let length = scheme.coordinateLength
            guard signature.count == 2 * length else { throw SecureBootError.signatureInvalid }
            let r = Data(signature.prefix(length).reversed()), s = Data(signature.suffix(length).reversed())
            block = Data([0xE7, 0x03, scheme == .ecdsa384 ? 0x01 : 0x00, 0x00]) + digest + publicKey.blockEncoding + r + s
            block.append(Data(count: crcCoverage - block.count))
        case .ecdsa192:
            throw SecureBootError.schemeNotSupported(.ecdsa192, chip: nil)
        }
        guard publicKey.isValidSignature(signature, forImage: image) else { throw SecureBootError.signatureInvalid }
        block.appendLE32(Zlib.crc32(block))
        block.append(Data(count: blockLength - block.count))
        return block
    }

    private static func parseSector(_ image: Data) throws -> [SignatureBlock] {
        guard image.count >= sectorLength, image.count % sectorLength == 0 else { return [] }
        let sector = Data(image.suffix(sectorLength))
        var blocks: [SignatureBlock] = []
        for index in 0..<3 {
            let block = sector.subdata(in: index * blockLength..<(index + 1) * blockLength)
            guard block[0] == 0xE7, Zlib.crc32(block.prefix(crcCoverage)) == block.readLE32(at: crcCoverage) else { break }
            let scheme: Scheme
            switch (block[1], block[2]) {
            case (0x02, _): scheme = .rsa3072
            case (0x03, 0x01): scheme = .ecdsa384
            case (0x03, _): scheme = block[36] == 1 ? .ecdsa192 : .ecdsa256
            default: throw SecureBootError.invalidKey("unknown block version \(block[1])")
            }
            let digestLength = scheme == .ecdsa384 ? 48 : 32
            let keyStart = 4 + digestLength
            let keyLength = scheme == .rsa3072 ? 776 : 1 + 2 * scheme.coordinateLength
            let signatureLength = scheme == .rsa3072 ? 384 : 2 * scheme.coordinateLength
            let rawSignature = block.subdata(in: keyStart + keyLength..<keyStart + keyLength + signatureLength)
            let signature: Data = scheme == .rsa3072
                ? Data(rawSignature.reversed())
                : Data(rawSignature.prefix(signatureLength / 2).reversed()) + Data(rawSignature.suffix(signatureLength / 2).reversed())
            blocks.append(SignatureBlock(scheme: scheme, imageDigest: block.subdata(in: 4..<keyStart),
                                         publicKey: try PublicKey(blockEncoding: block.subdata(in: keyStart..<keyStart + keyLength), scheme: scheme),
                                         signature: signature))
        }
        return blocks
    }
}

extension SecureBootV2.SigningKey: SecureBootV2.Signer {
    /// Signs locally; never suspends.
    public func sign(imageDigest: Data) async throws -> Data {
        try signature(forDigest: imageDigest)
    }
}

/// Precomputed digest, to sign with ECDSA without going through the hash function again.
struct RawDigest: Digest {
    static var byteCount: Int { 48 }
    var bytes: [UInt8]

    init(bytes: Data, length: Int) { self.bytes = Array(bytes.prefix(length)) }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try bytes.withUnsafeBytes(body) }
    func makeIterator() -> IndexingIterator<[UInt8]> { bytes.makeIterator() }
    var description: String { bytes.map { String(format: "%02x", $0) }.joined() }
}

/// EMSA-PSS encoding (RFC 8017, § 9.1.1) with SHA-256 and MGF1-SHA-256.
enum PSS {
    static func encode(digest: Data, salt: Data, modulusBits: Int) -> Data {
        let emBits = modulusBits - 1
        let emLength = (emBits + 7) / 8
        let h = Data(Crypto.SHA256.hash(data: Data(count: 8) + digest + salt))
        var db = Data(count: emLength - salt.count - h.count - 2)
        db.append(0x01)
        db.append(salt)
        let mask = mgf1(seed: h, length: db.count)
        for index in db.indices { db[index] ^= mask[index] }
        db[db.startIndex] &= 0xFF >> (8 * emLength - emBits)
        return db + h + [0xBC]
    }

    static func mgf1(seed: Data, length: Int) -> Data {
        var out = Data()
        var counter: UInt32 = 0
        while out.count < length {
            out.append(Data(Crypto.SHA256.hash(data: seed + withUnsafeBytes(of: counter.bigEndian) { Data($0) })))
            counter += 1
        }
        return out.prefix(length)
    }
}

extension Data {
    func readLE32(at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 { value |= UInt32(self[startIndex + offset + i]) << (8 * i) }
        return value
    }

    mutating func appendLE32(_ value: UInt32) {
        for i in 0..<4 { append(UInt8(truncatingIfNeeded: value >> (8 * UInt32(i)))) }
    }
}
