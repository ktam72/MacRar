import Foundation

enum FileSystemService {
    static func createExtractionDirectory(for path: String) -> String {
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
