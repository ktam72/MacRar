import Foundation
import SwiftUI

final class ArchiveViewModel: ObservableObject {
    @Published var extractionState: ExtractionState = .idle
    @Published var extractionProgress: Double = 0.0
    @Published var logMessages: [String] = []
    @Published var droppedFilePath: String?
    @Published var unrarVersionText: String

    let libarchiveVersionText: String

    private let libArchiveService: LibArchiveService
    private let unrarService: UnrarService

    init(
        libArchiveService: LibArchiveService = LibArchiveService(),
        unrarService: UnrarService = UnrarService()
    ) {
        self.libArchiveService = libArchiveService
        self.unrarService = unrarService
        libarchiveVersionText = archive_version_string().map { String(cString: $0) } ?? "不明"
        unrarVersionText = "読込中..."
        fetchUnrarVersion()
    }

    private func fetchUnrarVersion() {
        UnrarService.fetchVersion { [weak self] ver in
            DispatchQueue.main.async {
                self?.unrarVersionText = ver ?? "N/A"
            }
        }
    }

    // MARK: - ファイル処理入口

    func processFile(at path: String) {
        extractionState = .running
        extractionProgress = 0.0
        logMessages.removeAll()

        let fileName = (path as NSString).lastPathComponent
        addLog("=== 処理開始: \(fileName) ===")
        droppedFilePath = path

        let fileURL = URL(fileURLWithPath: path)

        guard let format = ArchiveFormat.detect(from: fileURL) else {
            let ext = fileURL.pathExtension
            addLog("❌ エラー: 未対応のファイル形式です（.\(ext.isEmpty ? "不明" : ext)）")
            resetState()
            return
        }
        addLog("✅ 形式検出: \(format.displayName)")

        let extractionDir = FileSystemService.createExtractionDirectory(for: path)
        guard !extractionDir.isEmpty else {
            addLog("❌ エラー: 展開先ディレクトリ作成失敗")
            resetState()
            return
        }
        addLog("✅ 展開先: \((extractionDir as NSString).lastPathComponent)")

        if format.usesUnrar {
            extractWithUnrar(at: path, to: extractionDir)
        } else {
            extractWithLibArchive(at: path, to: extractionDir)
        }
    }

    // MARK: - libarchive による解凍

    private func extractWithLibArchive(at path: String, to destination: String) {
        addLog("解凍開始（libarchive）")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try libArchiveService.extract(
                    archive: path,
                    to: destination,
                    progress: { value in
                        DispatchQueue.main.async {
                            self.extractionProgress = value
                        }
                    },
                    log: { [weak self] msg in
                        self?.addLog(msg)
                    }
                )
                DispatchQueue.main.async {
                    self.addLog("✅ 解凍成功！保存先: \((destination as NSString).lastPathComponent)")
                    self.extractionProgress = 1.0
                    self.extractionState = .completed
                    NSWorkspace.shared.open(URL(fileURLWithPath: destination))
                }
            } catch {
                DispatchQueue.main.async {
                    self.addLog("❌ 解凍失敗: \(error.localizedDescription)")
                    self.resetState()
                }
            }
        }
    }

    // MARK: - unrar による解凍

    private func extractWithUnrar(at path: String, to destination: String) {
        addLog("解凍開始（unrar）")

        unrarService.extract(
            archive: path,
            to: destination,
            progressHandler: { [weak self] value in
                DispatchQueue.main.async {
                    self?.extractionProgress = value
                }
            },
            logHandler: { [weak self] msg in
                self?.addLog(msg)
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.addLog("✅ 解凍成功！保存先: \((destination as NSString).lastPathComponent)")
                        self.extractionProgress = 1.0
                        self.extractionState = .completed
                        NSWorkspace.shared.open(URL(fileURLWithPath: destination))
                    case let .failure(error):
                        self.addLog("❌ 解凍失敗: \(error.localizedDescription)")
                        self.resetState()
                    }
                }
            }
        )
        addLog("✅ unrarプロセス起動")
    }

    // MARK: - ログ出力

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"

        if Thread.isMainThread {
            logMessages.append(logEntry)
        } else {
            DispatchQueue.main.async {
                self.logMessages.append(logEntry)
            }
        }
    }

    // MARK: - 状態リセット

    private func resetState() {
        DispatchQueue.main.async {
            self.extractionState = .idle
            self.extractionProgress = 0.0
        }
    }
}

// MARK: - 抽出状態

enum ExtractionState {
    case idle, running, completed
}
