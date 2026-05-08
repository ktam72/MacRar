import Foundation

struct UnrarArchive {
    let path: String
    var isSolid: Bool = false
    var files: [UnrarFile] = []
    var totalUncompressedSize: UInt64 = 0
    var totalCompressedSize: UInt64 = 0
}

struct UnrarFile {
    let name: String
    let isDirectory: Bool
    let uncompressedSize: UInt64
    let compressedSize: UInt64
    let isEncrypted: Bool
    let isSolid: Bool
}
