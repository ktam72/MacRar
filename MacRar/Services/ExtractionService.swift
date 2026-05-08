import Foundation

protocol ExtractionService {
    func extract(
        archive path: String,
        to destination: String,
        progress: @escaping (Double) -> Void,
        log: ((String) -> Void)?
    ) throws
}
