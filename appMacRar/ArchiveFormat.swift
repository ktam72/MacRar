import Foundation

enum ArchiveFormat: CaseIterable {
    case rar
    case sevenZip, zip, gzip, bzip2
    // swiftlint:disable:next identifier_name
    case xz
    case lzip, tar, lzh, iso, cab, arj, cpio, zCompress

    var displayName: String {
        switch self {
        case .rar: "RAR"
        case .sevenZip: "7z"
        case .zip: "ZIP"
        case .gzip: "GZIP"
        case .bzip2: "BZIP2"
        case .xz: "XZ"
        case .lzip: "LZIP"
        case .tar: "TAR"
        case .lzh: "LHA/LZH"
        case .iso: "ISO"
        case .cab: "CAB"
        case .arj: "ARJ"
        case .cpio: "CPIO"
        case .zCompress: "Z"
        }
    }

    var usesUnrar: Bool {
        self == .rar
    }

    private struct FormatSignature {
        let format: ArchiveFormat
        let offset: Int
        let bytes: [UInt8]
    }

    private static let signatures: [FormatSignature] = [
        FormatSignature(format: .rar, offset: 0, bytes: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]),
        FormatSignature(format: .sevenZip, offset: 0, bytes: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]),
        FormatSignature(format: .zip, offset: 0, bytes: [0x50, 0x4B, 0x03, 0x04]),
        FormatSignature(format: .gzip, offset: 0, bytes: [0x1F, 0x8B, 0x08]),
        FormatSignature(format: .bzip2, offset: 0, bytes: [0x42, 0x5A, 0x68]),
        FormatSignature(format: .lzip, offset: 0, bytes: [0x4C, 0x5A, 0x49, 0x50]),
        FormatSignature(format: .xz, offset: 0, bytes: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]),
        FormatSignature(format: .zCompress, offset: 0, bytes: [0x1F, 0x9D]),
        FormatSignature(format: .zCompress, offset: 0, bytes: [0x1F, 0xA0]),
        FormatSignature(format: .cab, offset: 0, bytes: [0x4D, 0x53, 0x43, 0x46]),
        FormatSignature(format: .cab, offset: 0, bytes: [0x49, 0x53, 0x63, 0x28]),
        FormatSignature(format: .arj, offset: 0, bytes: [0x60, 0xEA]),
        FormatSignature(format: .lzh, offset: 2, bytes: [0x2D, 0x6C, 0x68])
    ]

    static func detect(from url: URL) -> ArchiveFormat? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fileHandle.close() }

        let data = fileHandle.readData(ofLength: 260)
        guard data.count >= 4 else { return nil }

        for signature in signatures {
            guard signature.offset + signature.bytes.count <= data.count else { continue }
            let slice = Array(data[signature.offset ..< (signature.offset + signature.bytes.count)])
            if slice == signature.bytes {
                return signature.format
            }
        }

        if data.count > 262 {
            let tarMagic = Array(data[257 ..< 262])
            if tarMagic == [0x75, 0x73, 0x74, 0x61, 0x72] {
                return .tar
            }
        }

        return nil
    }

    static var supportedFormatsText: String {
        allCases.filter { !$0.usesUnrar }.map(\.displayName).joined(separator: " / ")
    }
}
