import Foundation

enum ArchiveFormat: CaseIterable {
    case rar
    case sevenZip, zip, gzip, bzip2, xz, lzip, tar, lzh, iso, cab, arj, cpio, zCompress

    var displayName: String {
        switch self {
        case .rar: return "RAR"
        case .sevenZip: return "7z"
        case .zip: return "ZIP"
        case .gzip: return "GZIP"
        case .bzip2: return "BZIP2"
        case .xz: return "XZ"
        case .lzip: return "LZIP"
        case .tar: return "TAR"
        case .lzh: return "LHA/LZH"
        case .iso: return "ISO"
        case .cab: return "CAB"
        case .arj: return "ARJ"
        case .cpio: return "CPIO"
        case .zCompress: return "Z"
        }
    }

    var usesUnrar: Bool { self == .rar }

    private static let signatures: [(ArchiveFormat, offset: Int, bytes: [UInt8])] = [
        (.rar,      0, [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]),
        (.sevenZip, 0, [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]),
        (.zip,      0, [0x50, 0x4B, 0x03, 0x04]),
        (.gzip,     0, [0x1F, 0x8B, 0x08]),
        (.bzip2,    0, [0x42, 0x5A, 0x68]),
        (.xz,       0, [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]),
        (.lzip,     0, [0x4C, 0x5A, 0x49, 0x50]),
        (.zCompress,0, [0x1F, 0x9D]),
        (.zCompress,0, [0x1F, 0xA0]),
        (.cab,      0, [0x4D, 0x53, 0x43, 0x46]),
        (.cab,      0, [0x49, 0x53, 0x63, 0x28]),
        (.arj,      0, [0x60, 0xEA]),
        (.lzh,      2, [0x2D, 0x6C, 0x68]),
    ]

    static func detect(from url: URL) -> ArchiveFormat? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fileHandle.close() }

        let data = fileHandle.readData(ofLength: 260)
        guard data.count >= 4 else { return nil }

        for (format, offset, sigBytes) in signatures {
            guard offset + sigBytes.count <= data.count else { continue }
            let slice = Array(data[offset..<(offset + sigBytes.count)])
            if slice == sigBytes {
                return format
            }
        }

        if data.count > 262 {
            let tarMagic = Array(data[257..<262])
            if tarMagic == [0x75, 0x73, 0x74, 0x61, 0x72] {
                return .tar
            }
        }

        return nil
    }

    static var supportedFormatsText: String {
        allCases.filter { !$0.usesUnrar }.map { $0.displayName }.joined(separator: " / ")
    }
}
