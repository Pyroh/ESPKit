// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Crypto
import _CryptoExtras
import enum ESPSupport.Zlib

/// Secure Boot v2 : signature des images et empreinte des clés publiques à brûler en eFuse.
///
/// Format (en-têtes C d'ESP-IDF) : l'image est complétée par 0xFF jusqu'à 4 Kio, puis suivie d'un
/// secteur de 4 Kio contenant de 1 à 3 blocs de 1 216 octets, le reste à 0xFF. Chaque bloc porte
/// le condensé de l'image, la clé publique et la signature, en little-endian pour le matériel,
/// puis un CRC-32 des 1 196 premiers octets.
public enum SecureBootV2 {
    public enum Scheme: Hashable, Sendable, CustomStringConvertible {
        case rsa3072, ecdsa192, ecdsa256, ecdsa384

        public var description: String {
            switch self {
            case .rsa3072: "RSA-3072"
            case .ecdsa192: "ECDSA P-192"
            case .ecdsa256: "ECDSA P-256"
            case .ecdsa384: "ECDSA P-384"
            }
        }

        /// SHA-384 pour P-384, SHA-256 sinon.
        func imageDigest(_ data: Data) -> Data {
            self == .ecdsa384 ? Data(Crypto.SHA384.hash(data: data)) : Data(Crypto.SHA256.hash(data: data))
        }

        var coordinateLength: Int { self == .ecdsa384 ? 48 : 32 }
    }

    // MARK: Clés

    public struct SigningKey: Sendable {
        enum Backing: Sendable {
            case rsa(signing: _RSA.Signing.PrivateKey, raw: _RSA.BlindSigning.PrivateKey<Crypto.SHA384>)
            case p256(P256.Signing.PrivateKey)
            case p384(P384.Signing.PrivateKey)
        }

        let backing: Backing
        public let publicKey: PublicKey

        public var scheme: Scheme { publicKey.scheme }

        /// - Throws: `SecureBootError.schemeNotSupported` pour P-192 (pas encore pris en charge).
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

        /// Clé PEM : RSA-3072 (PKCS#1 ou PKCS#8), ECDSA P-256 ou P-384 (SEC1 ou PKCS#8).
        /// - Throws: `SecureBootError.invalidKey`.
        public init(pemRepresentation pem: String) throws {
            if let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) {
                self.init(.p256(key))
            } else if let key = try? P384.Signing.PrivateKey(pemRepresentation: pem) {
                self.init(.p384(key))
            } else if let key = try? _RSA.Signing.PrivateKey(pemRepresentation: pem) {
                guard key.keySizeInBits == 3072 else {
                    throw SecureBootError.invalidKey("RSA de \(key.keySizeInBits) bits ; Secure Boot v2 veut 3072 bits")
                }
                let raw = try _RSA.BlindSigning.PrivateKey<Crypto.SHA384>(pemRepresentation: pem)
                self.init(.rsa(signing: key, raw: raw))
            } else {
                throw SecureBootError.invalidKey("PEM illisible, ou courbe autre que P-256 et P-384")
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

        public var pemRepresentation: String {
            switch backing {
            case .rsa(let key, _): key.pemRepresentation
            case .p256(let key): key.pemRepresentation
            case .p384(let key): key.pemRepresentation
            }
        }

        /// Signature standard (big-endian) du condensé de l'image.
        func signature(forDigest digest: Data) throws -> Data {
            switch backing {
            case .rsa(_, let raw):
                // RSA-PSS avec SHA-256, MGF1-SHA-256 et un sel de 32 octets : l'encodage EMSA-PSS
                // (RFC 8017, § 9.1.1) est fait ici, puis l'opération RSA brute par swift-crypto.
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

    public struct PublicKey: Hashable, Sendable {
        enum Backing: Sendable {
            case rsa(_RSA.Signing.PublicKey, modulus: Data, exponent: UInt32)
            case p256(P256.Signing.PublicKey)
            case p384(P384.Signing.PublicKey)
        }

        let backing: Backing

        /// - Throws: `SecureBootError.invalidKey`.
        public init(pemRepresentation pem: String) throws {
            if let key = try? P256.Signing.PublicKey(pemRepresentation: pem) {
                self.init(.p256(key))
            } else if let key = try? P384.Signing.PublicKey(pemRepresentation: pem) {
                self.init(.p384(key))
            } else if let key = try? _RSA.Signing.PublicKey(pemRepresentation: pem), key.keySizeInBits == 3072 {
                self.init(rsa: key)
            } else {
                throw SecureBootError.invalidKey("clé publique PEM illisible, ou ni RSA-3072, ni P-256, ni P-384")
            }
        }

        init(_ backing: Backing) { self.backing = backing }

        init(rsa key: _RSA.Signing.PublicKey) {
            let primitives = try? key.getKeyPrimitives()
            let modulus = primitives?.modulus ?? Data()
            let exponent = (primitives?.publicExponent ?? Data()).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            self.backing = .rsa(key, modulus: modulus, exponent: exponent)
        }

        public var scheme: Scheme {
            switch backing {
            case .rsa: .rsa3072
            case .p256: .ecdsa256
            case .p384: .ecdsa384
            }
        }

        public var pemRepresentation: String {
            switch backing {
            case .rsa(let key, _, _): key.pemRepresentation
            case .p256(let key): key.pemRepresentation
            case .p384(let key): key.pemRepresentation
            }
        }

        /// SHA-256 de la clé au format attendu par la ROM, à brûler dans `SECURE_BOOT_DIGESTn`.
        public var digest: Data { Data(Crypto.SHA256.hash(data: blockEncoding)) }

        /// Clé telle qu'elle figure dans le bloc de signature.
        /// RSA : n (LE), e, R² mod n (LE), −n⁻¹ mod 2³² ; ECDSA : identifiant de courbe, puis x et y (LE).
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

        /// Relit la clé d'un bloc de signature.
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

        public static func == (lhs: PublicKey, rhs: PublicKey) -> Bool { lhs.blockEncoding == rhs.blockEncoding }
        public func hash(into hasher: inout Hasher) { hasher.combine(blockEncoding) }

        /// Vérifie une signature standard (big-endian) sur l'image.
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

    /// Signataire abstrait : clé locale, HSM, service distant.
    public protocol Signer: Sendable {
        var publicKey: PublicKey { get }
        /// Signe le condensé de l'image (SHA-256, ou SHA-384 pour P-384) et rend la signature
        /// standard, en big-endian : RSA-PSS (MGF1-SHA-256, sel de 32 octets) sur 384 octets,
        /// ou ECDSA r ‖ s.
        func sign(imageDigest: Data) async throws -> Data
    }

    /// Bloc de signature lu dans une image.
    public struct SignatureBlock: Hashable, Sendable {
        public var scheme: Scheme
        public var imageDigest: Data
        public var publicKey: PublicKey
        /// Signature standard, en big-endian.
        public var signature: Data
    }

    // MARK: Signature

    /// Ajoute un bloc de signature par signataire (3 au maximum, existants compris).
    /// L'image est complétée à 4 Kio si besoin. Pour que la signature tombe sur une frontière
    /// MMU, construire l'image avec `ImageOptions.securePadding = .v2`.
    /// - Parameter existing: garder les blocs du secteur de signature déjà présent.
    /// - Throws: `SecureBootError`, et les erreurs des signataires.
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

    /// Version synchrone pour des clés locales.
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

    /// Insère une signature calculée ailleurs (signature à distance), après les blocs existants.
    /// - Throws: `SecureBootError.signatureInvalid` si elle ne vérifie pas.
    public static func attach(signature: Data, publicKey: PublicKey, to image: Data) throws -> Data {
        var (body, blocks) = try split(image, keepingSignatures: true)
        guard blocks.count < 3 else { throw SecureBootError.tooManySignatures }
        let digest = publicKey.scheme.imageDigest(body)
        blocks.append(try makeBlock(digest: digest, publicKey: publicKey, signature: signature, image: body))
        return assemble(body, blocks)
    }

    /// Blocs du secteur de signature final (CRC valide).
    /// - Throws: `SecureBootError.noSignatureBlock`.
    public static func signatureBlocks(in image: Data) throws -> [SignatureBlock] {
        let blocks = try parseSector(image)
        guard !blocks.isEmpty else { throw SecureBootError.noSignatureBlock }
        return blocks
    }

    /// Lève `SecureBootError.signatureInvalid` si aucun bloc ne vérifie avec `publicKey`.
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

    /// Image à signer (complétée à 4 Kio) et blocs existants.
    private static func split(_ image: Data, keepingSignatures: Bool) throws -> (Data, [Data]) {
        var body = Data(image)
        var blocks: [Data] = []
        if keepingSignatures, let parsed = try? parseSector(body), !parsed.isEmpty {
            let sector = body.suffix(sectorLength)
            blocks = (0..<parsed.count).map { Data(sector.dropFirst($0 * blockLength).prefix(blockLength)) }
            body = Data(body.prefix(body.count - sectorLength))
            // Tous les blocs signent la même image.
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

    /// Bloc de 1 216 octets ; la signature est vérifiée avant d'être rangée.
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
            default: throw SecureBootError.invalidKey("version de bloc \(block[1]) inconnue")
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
    public func sign(imageDigest: Data) async throws -> Data {
        try signature(forDigest: imageDigest)
    }
}

/// Condensé déjà calculé, pour signer en ECDSA sans repasser par la fonction de hachage.
struct RawDigest: Digest {
    static var byteCount: Int { 48 }
    var bytes: [UInt8]

    init(bytes: Data, length: Int) { self.bytes = Array(bytes.prefix(length)) }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try bytes.withUnsafeBytes(body) }
    func makeIterator() -> IndexingIterator<[UInt8]> { bytes.makeIterator() }
    var description: String { bytes.map { String(format: "%02x", $0) }.joined() }
}

/// Encodage EMSA-PSS (RFC 8017, § 9.1.1) avec SHA-256 et MGF1-SHA-256.
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
