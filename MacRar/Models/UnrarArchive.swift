import Foundation

struct UnrarArchive {
    let path: String
    var isSolid: Bool = false
    var files: [UnrarFile] = []
    var totalUncompressedSize: UInt64 = 0
    var totalCompressedSize: UInt64 = 0

    // 解凍状態
    var extractionState: ExtractionState = .idle
    var extractionProgress: Double = 0.0
    var currentFile: String?

    enum ExtractionState {
        case idle, running, completed, failed(Error)
    }
}

struct UnrarFile {
    let name: String
    let isDirectory: Bool
    let uncompressedSize: UInt64
    let compressedSize: UInt64
    let isEncrypted: Bool
    let isSolid: Bool
}
