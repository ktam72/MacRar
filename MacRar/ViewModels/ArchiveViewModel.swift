import Foundation
import SwiftUI

class ArchiveViewModel: ObservableObject {
    @Published var logMessages: [String] = []
    @Published var isProcessing = false
    @Published var droppedFilePath: String?
    @Published var extractionProgress: Double = 0.0

    private let archiveExtractor = ArchiveExtractor()

    let libarchiveVersionText: String
    @Published var unrarVersionText: String

    init() {
        libarchiveVersionText = archive_version_string().map { String(cString: $0) } ?? "不明"
        unrarVersionText = "読込中..."
        Self.fetchUnrarVersionAsync { [weak self] ver in
            DispatchQueue.main.async {
                self?.unrarVersionText = ver ?? "N/A"
            }
        }
    }

    private static func fetchUnrarVersionAsync(completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            guard let unrarPath = findUnrarPath() else {
                completion(nil)
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: unrarPath)
            process.arguments = []
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
                try process.run()
                process.waitUntilExit()
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outData, encoding: .utf8) ?? ""
                let errOut = String(data: errData, encoding: .utf8) ?? ""
                let combined = (output + errOut).trimmingCharacters(in: .whitespacesAndNewlines)
                if combined.isEmpty { completion(nil); return }
                let firstLine = combined.components(separatedBy: .newlines).first ?? ""
                let pattern = /\d+\.\d+[\w.]*/
                if let match = firstLine.firstMatch(of: pattern) {
                    completion(String(match.output))
                } else {
                    completion(firstLine)
                }
            } catch {
                completion(nil)
            }
        }
    }

    // MARK: - ファイル処理入口

    func processFile(at path: String) {
        isProcessing = true
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

        let extractionDir = createExtractionDirectory(for: path)
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
                try archiveExtractor.extract(
                    archive: path,
                    to: destination,
                    progress: { value in
                        DispatchQueue.main.async {
                            self.extractionProgress = value
                        }
                    },
                    log: { msg in
                        self.addLog(msg)
                    }
                )
                DispatchQueue.main.async {
                    self.addLog("✅ 解凍成功！保存先: \((destination as NSString).lastPathComponent)")
                    self.extractionProgress = 1.0
                    self.isProcessing = false
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
        guard let unrarPath = Self.findUnrarPath() else {
            addLog("❌ エラー: unrarが見つかりません")
            resetState()
            return
        }
        addLog("解凍開始（unrar）")

        let arguments = ["x", "-y", "-mt2", path, destination]

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: unrarPath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                self?.parseUnrarProgress(from: output)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                self?.addLog("unrar: \(output)")
            }
        }

        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.isProcessing = false
                self?.extractionProgress = process.terminationStatus == 0 ? 1.0 : 0.0
                if process.terminationStatus == 0 {
                    self?.addLog("✅ 解凍成功！保存先: \((destination as NSString).lastPathComponent)")
                    NSWorkspace.shared.open(URL(fileURLWithPath: destination))
                } else {
                    self?.addLog("❌ 解凍失敗！終了コード: \(process.terminationStatus)")
                }
            }
        }

        do {
            try process.run()
            addLog("✅ unrarプロセス起動")
        } catch {
            addLog("❌ プロセス実行失敗: \(error.localizedDescription)")
            resetState()
        }
    }

    // MARK: - unrar進捗解析

    private func parseUnrarProgress(from output: String) {
        let pattern = #"(\d+)%$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output),
              let percent = Double(output[range]) else { return }
        DispatchQueue.main.async {
            self.extractionProgress = percent / 100.0
        }
    }

    // MARK: - ログ出力

    func addLog(_ message: String) {
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
            self.isProcessing = false
            self.extractionProgress = 0.0
        }
    }

    // MARK: - unrarパス検索

    private static func findUnrarPath() -> String? {
        if let exeURL = Bundle.main.executableURL {
            let unrarURL = exeURL.deletingLastPathComponent().appendingPathComponent("unrar")
            if FileManager.default.fileExists(atPath: unrarURL.path) {
                return unrarURL.path
            }
        }
        let devPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Libs/unrar/unrar").path
        if FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }
        return nil
    }

    // MARK: - 展開先ディレクトリ作成

    private func createExtractionDirectory(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let parentDir = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let dirName = "\(baseName)_uncompressed"
        let dirURL = parentDir.appendingPathComponent(dirName)
        let dirPath = dirURL.path

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return dirPath
            } else {
                return ""
            }
        }

        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            return dirPath
        } catch {
            return ""
        }
    }
}
