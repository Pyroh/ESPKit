// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import CZlib

/// Compression zlib (RFC 1950) par la libz du système.
package enum Zlib {
    package struct Failure: Error, CustomStringConvertible {
        package var code: Int32
        package var description: String { "erreur zlib \(code)" }
    }

    /// Flux zlib complet (en-tête, deflate, Adler-32). Niveau 9 par défaut, comme esptool.
    package static func compress(_ data: Data, level: Int32 = 9) throws -> Data {
        var capacity = compressBound(uLong(data.count))
        var out = Data(count: Int(capacity))
        let status = out.withUnsafeMutableBytes { (dest: UnsafeMutableRawBufferPointer) -> Int32 in
            data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int32 in
                compress2(dest.bindMemory(to: Bytef.self).baseAddress, &capacity,
                          source.bindMemory(to: Bytef.self).baseAddress, uLong(data.count), level)
            }
        }
        guard status == Z_OK else { throw Failure(code: status) }
        out.count = Int(capacity)
        return out
    }

    /// Décompression d'un flux complet.
    package static func decompress(_ data: Data) throws -> Data {
        let inflater = try Inflater()
        let out = try inflater.feed(data)
        guard inflater.isFinished else { throw Failure(code: Z_BUF_ERROR) }
        return out
    }

    /// Décompression par morceaux, pour suivre un flux reçu bloc par bloc.
    package final class Inflater {
        private var stream = z_stream()
        package private(set) var isFinished = false

        package init() throws {
            let status = inflateInit_(&stream, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
            guard status == Z_OK else { throw Failure(code: status) }
        }

        deinit { inflateEnd(&stream) }

        /// Décompresse `chunk` et rend ce qui en sort.
        package func feed(_ chunk: Data) throws -> Data {
            guard !isFinished, !chunk.isEmpty else { return Data() }
            var output = Data()
            var input = [UInt8](chunk)
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            let inputCount = input.count
            try input.withUnsafeMutableBufferPointer { inPtr in
                stream.next_in = inPtr.baseAddress
                stream.avail_in = uInt(inputCount)
                repeat {
                    let status = buffer.withUnsafeMutableBufferPointer { outPtr -> Int32 in
                        stream.next_out = outPtr.baseAddress
                        stream.avail_out = uInt(outPtr.count)
                        return inflate(&stream, Z_NO_FLUSH)
                    }
                    let produced = buffer.count - Int(stream.avail_out)
                    output.append(contentsOf: buffer.prefix(produced))
                    switch status {
                    case Z_STREAM_END:
                        isFinished = true
                        return
                    case Z_OK:
                        continue
                    case Z_BUF_ERROR where stream.avail_in == 0:
                        return
                    default:
                        throw Failure(code: status)
                    }
                } while stream.avail_in > 0 || stream.avail_out == 0
            }
            stream.next_in = nil
            return output
        }
    }
}
