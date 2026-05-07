import Foundation

enum ArchiveExtractionError: LocalizedError {
    case openFailed(String)
    case extractFailed(String)
    case unsupportedFormat
    case emptyArchive

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "アーカイブを開けません: \(msg)"
        case .extractFailed(let msg): return "展開エラー: \(msg)"
        case .unsupportedFormat: return "未対応のアーカイブ形式です"
        case .emptyArchive: return "アーカイブが空です"
        }
    }
}

class ArchiveExtractor {
    private let maxEntryCount = 500_000

    func extract(archive path: String, to destination: String, progress: @escaping (Double) -> Void, log: ((String) -> Void)? = nil) throws {
        setlocale(LC_ALL, "en_US.UTF-8")

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? UInt64 ?? 0
        log?("アーカイブサイズ: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))")

        guard fileSize > 0 else {
            throw ArchiveExtractionError.emptyArchive
        }

        let a = archive_read_new()
        defer { archive_read_free(a) }

        archive_read_support_filter_all(a)
        archive_read_support_format_all(a)

        let r = archive_read_open_filename(a, path, 10240)
        guard r == ARCHIVE_OK else {
            let err = archive_error_string(a).map { String(cString: $0) } ?? "不明"
            log?("open失敗: \(err)")
            throw ArchiveExtractionError.openFailed(err)
        }
        log?("アーカイブオープン成功")

        let formatName = archive_format_name(a).map { String(cString: $0) } ?? "不明"
        log?("libarchive認識形式: \(formatName)")

        let fm = FileManager.default
        let originalCWD = fm.currentDirectoryPath
        fm.changeCurrentDirectoryPath(destination)
        defer { fm.changeCurrentDirectoryPath(originalCWD) }

        var entryCount = 0
        var entry: OpaquePointer?

        while archive_read_next_header(a, &entry) == ARCHIVE_OK {
            entryCount += 1
            if entryCount > maxEntryCount {
                throw ArchiveExtractionError.extractFailed("エントリ数が制限(\(maxEntryCount))を超過しました")
            }

            let flags = ARCHIVE_EXTRACT_TIME
                      | ARCHIVE_EXTRACT_SECURE_NODOTDOT
                      | ARCHIVE_EXTRACT_SECURE_SYMLINKS
                      | ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS
                      | ARCHIVE_EXTRACT_UNLINK
            let result = archive_read_extract(a, entry, flags)

            switch result {
            case ARCHIVE_OK:
                break
            case ARCHIVE_WARN:
                let name = archive_entry_pathname(entry).map { String(cString: $0) } ?? "?"
                let msg = archive_error_string(a).map { String(cString: $0) } ?? "詳細不明"
                log?("  WARN: \(name) — \(msg)")
            case ARCHIVE_RETRY:
                let name = archive_entry_pathname(entry).map { String(cString: $0) } ?? "?"
                let msg = archive_error_string(a).map { String(cString: $0) } ?? "詳細不明"
                log?("  RETRY: \(name) — \(msg)")
                throw ArchiveExtractionError.extractFailed(msg)
            case ARCHIVE_FATAL:
                let name = archive_entry_pathname(entry).map { String(cString: $0) } ?? "?"
                let err = archive_error_string(a).map { String(cString: $0) } ?? "詳細不明"
                log?("  FATAL: \(name) — \(err)")
                throw ArchiveExtractionError.extractFailed(err)
            default:
                let name = archive_entry_pathname(entry).map { String(cString: $0) } ?? "?"
                log?("  不明(result=\(result)): \(name)")
            }

            let bytesConsumed = archive_filter_bytes(a, -1)
            if fileSize > 0 {
                progress(min(Double(bytesConsumed) / Double(fileSize), 1.0))
            }
        }

        log?("全エントリ処理完了: \(entryCount)件")

        let closeResult = archive_read_close(a)
        if closeResult != ARCHIVE_OK && closeResult != ARCHIVE_EOF {
            let err = archive_error_string(a).map { String(cString: $0) } ?? "不明"
            log?("closeエラー: \(err)")
            throw ArchiveExtractionError.extractFailed(err)
        }
        log?("アーカイブクローズ完了")
    }
}
