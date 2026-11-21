import Foundation
import Compression

/// Just enough of a zip reader to open Excel (.xlsx) and Word (.docx) files, which are zip archives.
/// Uses Apple's Compression framework, so no extra library is needed.
struct ZipReader {
    private struct Item {
        let method: Int
        let compressedSize: Int
        let size: Int
        let localOffset: Int
    }

    private let bytes: [UInt8]
    private var items: [String: Item] = [:]

    var names: [String] { Array(items.keys) }

    init?(data: Data) {
        bytes = [UInt8](data)
        guard bytes.count > 22, bytes[0] == 0x50, bytes[1] == 0x4B else { return nil }

        // The end-of-central-directory record sits in the last 64 KB.
        var eocd = -1
        var i = bytes.count - 22
        let stop = max(0, bytes.count - 65_557)
        while i >= stop {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)

        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4B50 else { break }
            let method = u16(p + 10)
            let compressed = u32(p + 20)
            let size = u32(p + 24)
            let nameLength = u16(p + 28)
            let extraLength = u16(p + 30)
            let commentLength = u16(p + 32)
            let local = u32(p + 42)
            guard p + 46 + nameLength <= bytes.count else { break }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)
            items[name] = Item(method: method, compressedSize: compressed, size: size, localOffset: local)
            p += 46 + nameLength + extraLength + commentLength
        }
        if items.isEmpty { return nil }
    }

    func contains(_ name: String) -> Bool { items[name] != nil }

    /// The unzipped contents of one file in the archive.
    func data(_ name: String) -> Data? {
        guard let item = items[name] else { return nil }
        let h = item.localOffset
        guard h + 30 <= bytes.count, u32(h) == 0x0403_4B50 else { return nil }
        let start = h + 30 + u16(h + 26) + u16(h + 28)
        let end = start + item.compressedSize
        guard end <= bytes.count else { return nil }

        switch item.method {
        case 0:
            return Data(bytes[start..<end])
        case 8:
            // Zip stores raw DEFLATE, which is what COMPRESSION_ZLIB decodes.
            guard item.size > 0 else { return Data() }
            var out = [UInt8](repeating: 0, count: item.size)
            let written = bytes.withUnsafeBufferPointer { src -> Int in
                out.withUnsafeMutableBufferPointer { dst -> Int in
                    compression_decode_buffer(dst.baseAddress!, item.size,
                                              src.baseAddress! + start, item.compressedSize,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            guard written > 0 else { return nil }
            return Data(out.prefix(written))
        default:
            return nil
        }
    }

    private func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
    private func u32(_ i: Int) -> Int {
        Int(bytes[i]) | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2]) << 16 | Int(bytes[i + 3]) << 24
    }
}
