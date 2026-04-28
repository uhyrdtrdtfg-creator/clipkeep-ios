import SwiftUI
import Vision
import ClipKeepCore

// MARK: – Detail view for image / file clipboard items

struct ClipDetailView: View {
    let item: ClipItem
    @Environment(\.dismiss) private var dismiss

    @State private var recognizedText: String
    @State private var isRecognizing = false
    @State private var copiedOCR = false
    @State private var showCopyToast = false

    init(item: ClipItem) {
        self.item = item
        // Pre-populate with any cached OCR result so the user doesn't wait again.
        _recognizedText = State(initialValue: item.recognizedText ?? "")
    }

    // MARK: – Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    contentPreview
                    if item.kind == .image {
                        ocrSection
                    }
                }
                .padding()
            }
            .navigationTitle(item.kind == .image ? "图片详情" : "文件详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        _ = ClipStore.shared.copyToPasteboard(item)
                        showCopyToast = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            showCopyToast = false
                        }
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .toast(isShowing: $showCopyToast, message: "已复制")
    }

    // MARK: – Content preview

    @ViewBuilder
    private var contentPreview: some View {
        switch item.kind {
        case .image:
            if let url = ClipStore.shared.assetURL(for: item),
               let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                imagePlaceholder
            }
        case .file:
            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.fileName ?? item.content)
                        .font(.headline)
                        .lineLimit(2)
                    if let bytes = item.byteCount {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        case .text:
            EmptyView()
        }
    }

    private var imagePlaceholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 48))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: – OCR section

    @ViewBuilder
    private var ocrSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader

            if isRecognizing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("识别中…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if recognizedText.isEmpty {
                ocrEmptyState
            } else {
                ocrResult
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var sectionHeader: some View {
        HStack {
            Label("文字识别", systemImage: "text.viewfinder")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            if !isRecognizing && !recognizedText.isEmpty {
                Button {
                    recognizedText = ""
                    Task { await performOCR() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var ocrEmptyState: some View {
        Button {
            Task { await performOCR() }
        } label: {
            Label("识别图中文字", systemImage: "text.viewfinder")
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var ocrResult: some View {
        // Recognized text — long-press enables system copy / translate / look up
        Text(recognizedText)
            .font(.system(size: 15))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)

        Button {
            UIPasteboard.general.string = recognizedText
            copiedOCR = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copiedOCR = false
            }
        } label: {
            Label(copiedOCR ? "已复制" : "复制文字",
                  systemImage: copiedOCR ? "checkmark" : "doc.on.doc")
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Color(UIColor.tertiarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: copiedOCR)
    }

    // MARK: – Vision OCR

    private func performOCR() async {
        guard let url = ClipStore.shared.assetURL(for: item),
              let uiImage = UIImage(contentsOfFile: url.path),
              let cgImage = uiImage.cgImage else { return }

        isRecognizing = true

        // Run on a background thread — Vision's text recognition is CPU-intensive.
        let text = await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // List languages in priority order; Vision auto-detects the dominant one.
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])

            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value

        recognizedText = text
        isRecognizing = false

        // Persist the result so it survives restarts and makes the image searchable.
        if !text.isEmpty {
            ClipStore.shared.saveRecognizedText(id: item.id, text: text)
        }
    }
}
