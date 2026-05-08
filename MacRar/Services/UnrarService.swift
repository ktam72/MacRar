import Foundation

final class UnrarService {
    func extract(
        archive path: String,
        to destination: String,
        progressHandler: @escaping (Double) -> Void,
        logHandler: @escaping (String) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let unrarPath = Self.findUnrarPath() else {
            completion(.failure(UnrarError.notFound))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: unrarPath)
        process.arguments = ["x", "-y", "-mt2", path, destination]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !output.isEmpty {
                Self.parseProgress(from: output, handler: progressHandler)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !output.isEmpty {
                logHandler("unrar: \(output)")
            }
        }

        process.terminationHandler = { proc in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            if proc.terminationStatus == 0 {
                completion(.success(()))
            } else {
                completion(.failure(UnrarError.exitCode(proc.terminationStatus)))
            }
        }

        do {
            try process.run()
        } catch {
            completion(.failure(error))
        }
    }

    static func findUnrarPath() -> String? {
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

    static func fetchVersion(completion: @escaping (String?) -> Void) {
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
                let combined = (
                    (String(data: outData, encoding: .utf8) ?? "")
                        + (String(data: errData, encoding: .utf8) ?? "")
                ).trimmingCharacters(in: .whitespacesAndNewlines)
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

    enum UnrarError: LocalizedError {
        case notFound
        case exitCode(Int32)

        var errorDescription: String? {
            switch self {
            case .notFound: "unrar 実行ファイルが見つかりません"
            case let .exitCode(code): "unrar 終了コード \(code)"
            }
        }
    }
}

private extension UnrarService {
    static func parseProgress(from output: String, handler: (Double) -> Void) {
        let pattern = #"(\d+)%$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output),
              let percent = Double(output[range]) else { return }
        handler(percent / 100.0)
    }
}
