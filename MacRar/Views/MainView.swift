import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject var viewModel: ArchiveViewModel

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.libarchiveVersionText)
                    Text("unrar \(viewModel.unrarVersionText)")
                }
                .font(.system(size: 22))
                .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            DropZoneView(viewModel: viewModel)
                .frame(height: 150)
                .padding()

            Divider()

            VStack(alignment: .leading) {
                HStack {
                    Text("ログ (\(viewModel.logMessages.count) 行)")
                        .font(.headline)
                    Spacer()
                }

                LogTextView(logMessages: $viewModel.logMessages)
                    .frame(minHeight: 200)
                    .border(Color.gray, width: 1)

                HStack {
                    Button("ログをクリア") {
                        viewModel.logMessages.removeAll()
                    }
                    .disabled(viewModel.logMessages.isEmpty)

                    Spacer()

                    Text("\(viewModel.logMessages.count) 行")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            if viewModel.extractionState == .running {
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.extractionProgress) {
                        Text("解凍中...")
                    } currentValueLabel: {
                        Text("\(Int(viewModel.extractionProgress * 100))%")
                    }
                    .progressViewStyle(.linear)
                    .padding(.horizontal)

                    Text("進捗: \(Int(viewModel.extractionProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom)
            }
        }
        .padding()
        .frame(width: 600, height: 800)
    }
}

struct DropZoneView: View {
    @ObservedObject var viewModel: ArchiveViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                .foregroundColor(.gray)

            VStack(spacing: 6) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.blue)
                Text("アーカイブファイルをここにドロップ")
                    .foregroundColor(.secondary)
                Text("7z / ZIP / tar / gz / bz2 / xz / LHA/LZH / ISO / CAB 等")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let filePath = viewModel.droppedFilePath {
                    Text("選択中: \((filePath as NSString).lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        viewModel.processFile(at: url.path)
                    }
                }
            }
        }
    }
}
