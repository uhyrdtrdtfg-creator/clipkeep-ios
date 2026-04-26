import UIKit
import SwiftUI
import ClipKeepCore
import UniformTypeIdentifiers

// MARK: – Extracted content model

enum SharedContent {
    case text(String)
    case url(URL)
    case image(Data, String?)   // data, UTType identifier
    case file(Data, String?, String?)  // data, fileName, UTType identifier

    var preview: String {
        switch self {
        case .text(let s):           return s
        case .url(let u):            return u.absoluteString
        case .image:                 return "图片"
        case .file(_, let name, _):  return name ?? "文件"
        }
    }

    var iconName: String {
        switch self {
        case .text:  return "text.alignleft"
        case .url:   return "link"
        case .image: return "photo"
        case .file:  return "doc.fill"
        }
    }

    var label: String {
        switch self {
        case .text:  return "文本"
        case .url:   return "链接"
        case .image: return "图片"
        case .file:  return "文件"
        }
    }
}

// MARK: – Extension view controller

final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        Task {
            let content = await extractContent()
            await MainActor.run { mountUI(content: content) }
        }
    }

    // MARK: Mount SwiftUI card

    private func mountUI(content: SharedContent?) {
        let card = ShareCardView(
            content: content,
            onSave: { [weak self] in
                if let c = content { self?.save(c) }
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(
                    withError: NSError(domain: "ClipKeepShare", code: NSUserCancelledError))
            }
        )

        let host = UIHostingController(rootView: card)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    // MARK: Content extraction

    private func extractContent() async -> SharedContent? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }

        for item in items {
            for provider in (item.attachments ?? []) {
                // Image first — Photos gives both image + URL; we want the image.
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                   let (data, typeID) = await loadRawData(from: provider, typeID: UTType.image.identifier) {
                    return .image(data, typeID)
                }
                // Web URL (Safari, links) — skip asset-library / file URLs.
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await loadURL(from: provider),
                   url.scheme == "http" || url.scheme == "https" {
                    return .url(url)
                }
                // Plain text (Notes, selected text, etc.)
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = await loadText(from: provider) {
                    return .text(text)
                }
                // Any remaining URL (non-web schemes like file://, tel:, mailto:)
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await loadURL(from: provider) {
                    return .url(url)
                }
                // Generic file (PDF, zip, etc.)
                for typeID in provider.registeredTypeIdentifiers {
                    guard let utype = UTType(typeID),
                          !utype.conforms(to: .url),
                          !utype.conforms(to: .plainText),
                          !utype.conforms(to: .image) else { continue }
                    if let (data, _) = await loadRawData(from: provider, typeID: typeID) {
                        return .file(data, provider.suggestedName, typeID)
                    }
                }
            }
        }
        return nil
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                if let s = item as? String {
                    cont.resume(returning: s)
                } else if let d = item as? Data {
                    cont.resume(returning: String(data: d, encoding: .utf8))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                cont.resume(returning: item as? URL)
            }
        }
    }

    private func loadRawData(from provider: NSItemProvider, typeID: String) async -> (Data, String)? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: typeID) { item, _ in
                if let data = item as? Data {
                    cont.resume(returning: (data, typeID))
                } else if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    cont.resume(returning: (data, typeID))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    // MARK: Save to shared ClipStore

    private func save(_ content: SharedContent) {
        switch content {
        case .text(let s):
            ClipStore.shared.add(s)
        case .url(let u):
            ClipStore.shared.add(u.absoluteString)
        case .image(let data, let typeID):
            ClipStore.shared.add(CapturedClip(kind: .image, content: "图片", data: data, typeIdentifier: typeID))
        case .file(let data, let name, let typeID):
            ClipStore.shared.add(CapturedClip(kind: .file, content: name ?? "文件", data: data, fileName: name, typeIdentifier: typeID))
        }
    }
}

// MARK: – SwiftUI card view

struct ShareCardView: View {
    let content: SharedContent?
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var saved = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tap-to-dismiss dimming layer
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { if !saved { onCancel() } }

            card
                .background(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 24, y: -6)
        }
    }

    @ViewBuilder
    private var card: some View {
        if saved {
            savedConfirmation
        } else {
            previewCard
        }
    }

    // MARK: Saved confirmation

    private var savedConfirmation: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 36)
            Text("已保存到 ClipKeep")
                .font(.system(size: 17, weight: .semibold))
            Spacer().frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 52)
    }

    // MARK: Preview card

    private var previewCard: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 18)

            // Header row
            HStack(spacing: 12) {
                Image(systemName: content?.iconName ?? "doc.on.clipboard")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    Text("保存到 ClipKeep")
                        .font(.system(size: 16, weight: .semibold))
                    Text(content?.label ?? "内容")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            // Content preview
            if let preview = content?.preview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        Color(UIColor.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            }

            // Action buttons
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("取消")
                        .font(.system(size: 16, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            Color(UIColor.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .foregroundStyle(.primary)
                }

                Button {
                    saved = true
                    onSave()
                } label: {
                    Text("保存")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 36)
        }
    }
}
