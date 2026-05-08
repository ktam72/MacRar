import Foundation

enum ArchiveExtractionError: LocalizedError {
    case openFailed(String)
    case extractFailed(String)
    case unsupportedFormat
    case emptyArchive

    var errorDescription: String? {
        switch self {
        case let .openFailed(msg): "アーカイブを開けません: \(msg)"
        case let .extractFailed(msg): "展開エラー: \(msg)"
        case .unsupportedFormat: "未対応のアーカイブ形式です"
        case .emptyArchive: "アーカイブが空です"
        }
    }
}

final class LibArchiveService: ExtractionService {
    private let maxEntryCount = 500_000
    private let maxTotalSize: Int64 = 10 * 1024 * 1024 * 1024

    func extract(
        archive path: String,
        to destination: String,
        progress: @escaping (Double) -> Void,
        log: ((String) -> Void)? = nil
    ) throws {
        setlocale(LC_ALL, "en_US.UTF-8")

        let fileSize = try fileSizeOfArchive(at: path, log: log)

        let archive = try openArchive(path: path, log: log)
        defer { archive_read_free(archive) }

        reportFormatName(archive, log: log)

        let originalCWD = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(destination)
        defer { FileManager.default.changeCurrentDirectoryPath(originalCWD) }

        var entryCount = 0
        var totalExtractedSize: Int64 = 0
        var entry: OpaquePointer?

        while archive_read_next_header(archive, &entry) == ARCHIVE_OK {
            entryCount += 1
            try checkEntryCountLimit(entryCount)

            let entrySize = archive_entry_size(entry!)
            totalExtractedSize = try accumulateSize(
                totalExtractedSize, entrySize: entrySize
            )

            try extractEntry(archive, entry: entry!, log: log)

            let bytesConsumed = archive_filter_bytes(archive, -1)
            if fileSize > 0 {
                progress(min(Double(bytesConsumed) / Double(fileSize), 1.0))
            }
        }

        log?("全エントリ処理完了: \(entryCount)件")

        try closeArchive(archive, log: log)
        log?("アーカイブクローズ完了")
    }

    // MARK: - Private Helpers

    private func fileSizeOfArchive(at path: String, log: ((String) -> Void)?) throws -> UInt64 {
        let fileSize = (
            try? FileManager.default.attributesOfItem(atPath: path)
        )?[.size] as? UInt64 ?? 0
        log?(
            "アーカイブサイズ: "
                + ByteCountFormatter.string(
                    fromByteCount: Int64(fileSize), countStyle: .file
                )
        )
        guard fileSize > 0 else {
            throw ArchiveExtractionError.emptyArchive
        }
        return fileSize
    }

    private func openArchive(path: String, log: ((String) -> Void)?) throws -> OpaquePointer {
        guard let archive = archive_read_new() else {
            throw ArchiveExtractionError.openFailed("archive_read_new failed")
        }
        archive_read_support_filter_all(archive)
        archive_read_support_format_all(archive)

        let resultCode = archive_read_open_filename(archive, path, 10240)
        guard resultCode == ARCHIVE_OK else {
            let err = archive_error_string(archive).map { String(cString: $0) } ?? "不明"
            log?("open失敗: \(err)")
            archive_read_free(archive)
            throw ArchiveExtractionError.openFailed(err)
        }
        log?("アーカイブオープン成功")
        return archive
    }

    private func reportFormatName(_ archive: OpaquePointer, log: ((String) -> Void)?) {
        let formatName = archive_format_name(archive).map { String(cString: $0) } ?? "不明"
        log?("libarchive認識形式: \(formatName)")
    }

    private func checkEntryCountLimit(_ count: Int) throws {
        if count > maxEntryCount {
            throw ArchiveExtractionError.extractFailed(
                "エントリ数が制限(\(maxEntryCount))を超過しました"
            )
        }
    }

    private func accumulateSize(_ current: Int64, entrySize: Int64) throws -> Int64 {
        guard entrySize > 0 else { return current }
        let newTotal = current + entrySize
        if newTotal > maxTotalSize {
            throw ArchiveExtractionError.extractFailed(
                "展開後の合計サイズが制限("
                    + ByteCountFormatter.string(
                        fromByteCount: maxTotalSize, countStyle: .file
                    )
                    + ")を超過しました"
            )
        }
        return newTotal
    }

    private func extractEntry(
        _ archive: OpaquePointer,
        entry: OpaquePointer,
        log: ((String) -> Void)?
    ) throws {
        let flags = ARCHIVE_EXTRACT_TIME
            | ARCHIVE_EXTRACT_SECURE_NODOTDOT
            | ARCHIVE_EXTRACT_SECURE_SYMLINKS
            | ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS
            | ARCHIVE_EXTRACT_UNLINK
        let result = archive_read_extract(archive, entry, flags)

        switch result {
        case ARCHIVE_OK:
            break
        case ARCHIVE_WARN:
            let name = archive_entry_pathname(entry).map { String(cString: $0) } ?? "?"
            let msg = archive_error_string(archive).map { String(cString: $0) } ?? "詳細不明"
            log?("  WARN: \(name) — \(msg)")
        case ARCHIVE_RETRY:
            let name = archive_entry_pathname(entry).map { String(cString: $0) } ?? "?"
            let msg = archive_error_string(archive).map { String(cString: $0) } ?? "詳細不明"
            log?("  RETRY: \(name) — \(msg)")
            throw ArchiveExtractionError.extractFailed(msg)
        case ARCHIVE_FATAL:
            let name = archive_entry_pathname(entry).map { String(cString: $0) } ?? "?"
            let err = archive_error_string(archive).map { String(cString: $0) } ?? "詳細不明"
            log?("  FATAL: \(name) — \(err)")
            throw ArchiveExtractionError.extractFailed(err)
        default:
            let name = archive_entry_pathname(entry).map { String(cString: $0) } ?? "?"
            log?("  不明(result=\(result)): \(name)")
        }
    }

    private func closeArchive(_ archive: OpaquePointer, log: ((String) -> Void)?) throws {
        let closeResult = archive_read_close(archive)
        if closeResult != ARCHIVE_OK, closeResult != ARCHIVE_EOF {
            let err = archive_error_string(archive).map { String(cString: $0) } ?? "不明"
            log?("closeエラー: \(err)")
            throw ArchiveExtractionError.extractFailed(err)
        }
    }
}
